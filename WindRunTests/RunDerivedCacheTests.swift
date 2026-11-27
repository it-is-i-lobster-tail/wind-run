//
//  RunDerivedCacheTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// The quick ways the summary reads a run: the pause clock, the fixes read once, and the cache that keeps
/// what's worked out from them.
@MainActor
struct RunDerivedCacheTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let container = WindRunSchema.makeContainer(inMemory: true)

    /// A finished run with a fix every second for ten minutes, a heart rate reading every five, and two pauses.
    private func makeRun() -> Run {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        var paused = 0.0
        for second in 1...600 {
            if second == 200 || second == 400 {
                let date = start.addingTimeInterval(Double(second) + paused)
                run.pause(at: date)
                run.resume(at: date.addingTimeInterval(30))
                paused += 30
            }
            let date = start.addingTimeInterval(Double(second) + paused)
            run.record(RouteSample(timestamp: date, latitude: Double(second) * 3 / 111_111, longitude: 0,
                                   altitude: 10, horizontalAccuracy: 5, verticalAccuracy: 4, speed: 3, speedAccuracy: 0.5))
            if second % 5 == 0 { run.record(HeartRateSample(timestamp: date, beatsPerMinute: 140)) }
        }
        run.finish(at: start.addingTimeInterval(601 + paused))
        return run
    }

    @Test func thePauseClockAgreesWithTheRun() {
        let run = makeRun()
        let clock = run.pauseClock
        for offset in stride(from: -10.0, through: 700, by: 0.5) {
            let date = start.addingTimeInterval(offset)
            #expect(clock.activeTime(at: date) == run.activeTime(at: date))
            #expect(clock.pausedTime(at: date) == run.pausedTime(at: date))
            #expect(clock.contains(date) == run.pauses.contains { $0.contains(date) })
        }
    }

    @Test func aPauseStillGoingCountsUpToTheMoment() {
        let clock = PauseClock(start: start, pauses: [(start.addingTimeInterval(10), start.addingTimeInterval(20)), (start.addingTimeInterval(50), nil)])
        #expect(clock.pausedTime(at: start.addingTimeInterval(60)) == 20)
        #expect(clock.activeTime(at: start.addingTimeInterval(60)) == 40)
        #expect(clock.contains(start.addingTimeInterval(1_000)))
        #expect(!clock.contains(start.addingTimeInterval(20)))
        #expect(clock.hasPauseStarting(from: start.addingTimeInterval(5), before: start.addingTimeInterval(11)))
        #expect(!clock.hasPauseStarting(from: start.addingTimeInterval(11), before: start.addingTimeInterval(50)))
    }

    @Test func readingsAreTheRouteInOrder() {
        let run = makeRun()
        #expect(run.routeReadings.map(\.timestamp) == run.route.map(\.timestamp))
        #expect(run.routeReadings.map(\.latitudeValue) == run.route.map(\.latitudeValue))
        #expect(run.startLocation?.coordinate.latitude == run.route.first?.coordinate.latitude)
        #expect(Run.startLocation(in: run.routeReadings)?.coordinate.latitude == run.route.first?.coordinate.latitude)
        #expect(run.heartRateReadings.map(\.timestamp) == run.heartRateSamples.map(\.timestamp))
    }

    @Test func activeRouteLeavesOutThePausesAndBreaksAtThem() {
        let run = makeRun()
        let fixes = run.activeRoute
        #expect(fixes.count == 600)
        #expect(Set(fixes.map(\.stretch)) == [0, 1, 2])
        #expect(fixes.last?.time == 600)
        #expect(fixes.allSatisfy { !run.pauses.contains(where: { pause in pause.contains($0.sample.timestamp) }) })
    }

    @Test func aFinishedRunIsWorkedOutOnceUntilItChanges() {
        let cache = RunDerivedCache()
        let run = makeRun()
        var builds = 0
        let first = cache.value("test", for: run) { builds += 1; return 1 }
        let second = cache.value("test", for: run) { builds += 1; return 2 }
        #expect(first == 1 && second == 1 && builds == 1)

        run.distanceMetersValue += 100
        let changed = cache.value("test", for: run) { builds += 1; return 3 }
        #expect(changed == 3 && builds == 2)

        cache.removeAll()
        _ = cache.value("test", for: run) { builds += 1; return 4 }
        #expect(builds == 3)
    }

    @Test func aNilResultIsKeptToo() {
        let cache = RunDerivedCache()
        let run = makeRun()
        var builds = 0
        let first: Double? = cache.value("rank", for: run) { builds += 1; return nil }
        let second: Double? = cache.value("rank", for: run) { builds += 1; return 5 }
        #expect(first == nil && second == nil && builds == 1)
    }

    @Test func aRunStillGoingIsNeverKept() {
        let cache = RunDerivedCache()
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        var builds = 0
        _ = cache.value("test", for: run) { builds += 1; return 1 }
        _ = cache.value("test", for: run) { builds += 1; return 1 }
        #expect(builds == 2)
        #expect(cache.count == 0)
    }

    @Test func savingTheStoreEmptiesTheCache() throws {
        let cache = RunDerivedCache()
        let run = makeRun()
        _ = cache.value("test", for: run) { 1 }
        #expect(cache.count == 1)
        NotificationCenter.default.post(name: ModelContext.didSave, object: container.mainContext)
        #expect(cache.count == 0)
    }

    @Test func theOldestEntriesGoPastTheLimit() {
        let cache = RunDerivedCache()
        let run = makeRun()
        for index in 0...RunDerivedCache.limit {
            _ = cache.value("kind \(index)", for: run) { index }
        }
        #expect(cache.count == RunDerivedCache.limit)
        var rebuilt = false
        _ = cache.value("kind 0", for: run) { rebuilt = true; return 0 }
        #expect(rebuilt)
    }
}
