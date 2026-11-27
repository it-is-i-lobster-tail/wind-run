//
//  PackedRouteTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// A finished run's route packed into one piece of data, and older runs packed after the fact.
@MainActor
struct PackedRouteTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let container = WindRunSchema.makeContainer(inMemory: true)

    private func reading(_ second: Int) -> RouteReading {
        RouteReading(
            timestamp: start.addingTimeInterval(Double(second) + 0.123_456),
            latitude: 37.769_412_345_678 + Double(second) * 0.000_027,
            longitude: -122.466_298_765_432,
            altitude: 64.25 + sin(Double(second)),
            horizontalAccuracy: 4.7,
            verticalAccuracy: 3.1,
            speed: second.isMultiple(of: 7) ? -1 : 3.2,
            course: 91.5,
            speedAccuracy: 0.42
        )
    }

    /// A run recorded the way the app records one, a fix a second, left unfinished.
    private func recordingRun(seconds: Int = 300) -> Run {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        for second in 1...seconds {
            let fix = reading(second)
            run.record(RouteSample(timestamp: fix.timestamp, latitude: fix.latitudeValue, longitude: fix.longitudeValue,
                                   altitude: fix.altitudeValue, horizontalAccuracy: fix.horizontalAccuracyValue,
                                   verticalAccuracy: fix.verticalAccuracyValue, speed: fix.speedValue,
                                   course: fix.courseValue, speedAccuracy: fix.speedAccuracyValue))
        }
        return run
    }

    @Test func everyFieldComesBackExactly() throws {
        let readings = (0..<2_000).map(reading)
        let data = try #require(PackedRoute.encode(readings))
        #expect(PackedRoute.decode(data) == readings)
        // Smaller than the fields as they are, before any sync or storage overhead per record.
        #expect(data.count < readings.count * 9 * 8)
    }

    @Test func anEmptyRouteHasNothingToPack() {
        #expect(PackedRoute.encode([]) == nil)
    }

    @Test func dataThatIsntAPackedRouteIsntRead() throws {
        #expect(PackedRoute.decode(Data()) == nil)
        #expect(PackedRoute.decode(Data("not a route".utf8)) == nil)
        var data = try #require(PackedRoute.encode([reading(1)]))
        data[3] = 99
        #expect(PackedRoute.decode(data) == nil)
    }

    @Test func finishingARunPacksItsRoute() throws {
        let run = recordingRun()
        #expect(!run.hasPackedRoute)
        run.finish(at: start.addingTimeInterval(301))
        #expect(run.hasPackedRoute)
        #expect(run.routePackedCountValue == 300)
        #expect(run.packedRoute == run.sampleReadings)
        #expect(run.routeReadings.count == 300)
        // The fixes' own records stay, for older versions of the app.
        #expect(run.route.count == 300)
    }

    @Test func aPackedRunReadsTheSameAsItsFixes() throws {
        let run = recordingRun()
        run.finish(at: start.addingTimeInterval(301))
        let packed = run.activeRoute
        run.routePackedCountValue = nil
        let unpacked = run.activeRoute
        #expect(packed.map(\.sample) == unpacked.map(\.sample))
        #expect(packed.map(\.meters) == unpacked.map(\.meters))
        #expect(packed.map(\.time) == unpacked.map(\.time))
    }

    @Test func aDiscardedRunIsntPacked() {
        let run = recordingRun(seconds: 10)
        run.discard(at: start.addingTimeInterval(11))
        #expect(!run.hasPackedRoute)
    }

    @Test func olderRunsArePackedAndNewOnesWait() async throws {
        let context = container.mainContext
        let old = recordingRun()
        old.finish(at: start.addingTimeInterval(301))
        // As a run recorded before routes were packed.
        old.routeDataValue = nil
        old.routePackedCountValue = nil
        let fresh = recordingRun()
        fresh.finish(at: start.addingTimeInterval(301))
        fresh.routeDataValue = nil
        fresh.routePackedCountValue = nil
        let empty = Run(startDate: start)
        context.insert(empty)
        empty.finish(at: start.addingTimeInterval(60))

        // Only the old ones have settled; `fresh` finished just now as far as this pass knows.
        let now = start.addingTimeInterval(301 + RouteMigration.settlingTime + 1)
        fresh.endDateValue = now
        try context.save()
        let packed = await RouteMigration.packOldRuns(in: context, now: now, pause: .zero)
        #expect(packed == 1)
        #expect(old.routePackedCountValue == 300)
        #expect(old.packedRoute == old.sampleReadings)
        #expect(!fresh.hasPackedRoute)
        #expect(empty.routePackedCountValue == 0)
        #expect(empty.packedRoute == nil)

        // Run again, there's nothing left that has settled.
        #expect(await RouteMigration.packOldRuns(in: context, now: now, pause: .zero) == 0)
    }

    @Test func aRunFromTheWatchArrivesPacked() throws {
        let run = recordingRun()
        run.finish(at: start.addingTimeInterval(301))
        let record = try #require(WatchRunRecord(run))
        let other = WindRunSchema.makeContainer(inMemory: true)
        let received = try #require(try record.save(into: other.mainContext))
        #expect(received.routePackedCountValue == 300)
        #expect(received.packedRoute == run.packedRoute)
    }
}
