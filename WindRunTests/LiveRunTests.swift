//
//  LiveRunTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

@MainActor
struct LiveRunTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let container = WindRunSchema.makeContainer(inMemory: true)

    private func makeRun() -> Run {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        return run
    }

    private func status(_ state: LiveRunStatus.State, id: UUID = UUID(), elapsed: TimeInterval = 60) -> LiveRunStatus {
        LiveRunStatus(runID: id, device: .watch, sport: .running, state: state, elapsed: elapsed, meters: 200,
                      currentPace: 300, averagePace: 310, beatsPerMinute: 140)
    }

    @Test func statusTravelsAsJSON() throws {
        let sent = status(.running)
        let data = try #require(sent.encoded())
        #expect(LiveRunStatus.decode(data) == sent)
        // Readings only: nothing about where the run is.
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("latitude") && !text.contains("longitude"))
    }

    @Test func runningTimeCountsOnUntilPaused() {
        let received = Date(timeIntervalSinceReferenceDate: 1_000)
        #expect(status(.running).elapsed(at: received.addingTimeInterval(5), receivedAt: received) == 65)
        #expect(status(.paused).elapsed(at: received.addingTimeInterval(5), receivedAt: received) == 60)
    }

    @Test func endedRunIsNotShownAgainByALateReading() {
        let link = LiveRunLink()
        let id = UUID()
        link.receive(status(.running, id: id))
        #expect(link.remote?.runID == id)
        link.receive(status(.ended, id: id))
        #expect(link.remote == nil)
        link.receive(status(.running, id: id))
        #expect(link.remote == nil)
    }

    @Test func quietAfterNoWord() {
        let link = LiveRunLink()
        let now = Date.now
        link.receive(status(.running), at: now)
        #expect(!link.isQuiet(at: now.addingTimeInterval(5)))
        #expect(link.isQuiet(at: now.addingTimeInterval(LiveRunLink.quietAfter + 1)))
    }

    @Test func appleDistanceStandsInUntilTheFirstGPSFix() {
        let run = makeRun()
        run.recordAppleDistance(120)
        #expect(run.distanceMeters == 120)
        #expect(run.distanceMethod == DistanceEstimator.appleMethod)

        // GPS carries on from Apple's distance once it finds a fix.
        for second in 30...40 {
            run.record(RouteSample(timestamp: start.addingTimeInterval(Double(second)), latitude: Double(second) * 3 / 111_111,
                                   longitude: 0, horizontalAccuracy: 5, speed: 3, speedAccuracy: 0.3))
        }
        #expect(run.distanceMethod == DistanceEstimator.appleThenTrackMethod)
        // The smoothed line reads the 30 m of GPS within a few centimeters, not exactly.
        #expect(abs(run.distanceMeters - 150) < 0.1)
        // Apple's distance after that is kept beside it, not used.
        let measured = run.distanceMeters
        run.recordAppleDistance(400)
        #expect(run.distanceMeters == measured)
        #expect(run.appleDistanceMeters == 400)
    }

    @Test func appleDistanceIsNotUsedOnceGPSCounts() {
        let run = makeRun()
        for second in 0...10 {
            run.record(RouteSample(timestamp: start.addingTimeInterval(Double(second)), latitude: Double(second) * 3 / 111_111,
                                   longitude: 0, horizontalAccuracy: 5, speed: 3, speedAccuracy: 0.3))
        }
        let measured = run.distanceMeters
        run.recordAppleDistance(500)
        #expect(run.distanceMeters == measured)
        #expect(abs(run.distanceMeters - 30) < 0.1)
        #expect(run.distanceMethod == DistanceEstimator.method)
    }
}
