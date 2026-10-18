//
//  RunTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

@MainActor
struct RunTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    // Each test gets its own instance, so its own store. It has to outlive the models in it.
    private let container = WindRunSchema.makeContainer(inMemory: true)

    private func makeRun() -> Run {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        return run
    }

    private func sample(at seconds: TimeInterval, kilometersNorth: Double) -> RouteSample {
        RouteSample(
            timestamp: start.addingTimeInterval(seconds),
            latitude: kilometersNorth / 111.0,
            longitude: 0,
            horizontalAccuracy: 5
        )
    }

    @Test func pausesDontCountTowardActiveTime() {
        let run = makeRun()
        run.pause(at: start.addingTimeInterval(600))
        run.resume(at: start.addingTimeInterval(900))
        run.finish(at: start.addingTimeInterval(1_800))

        #expect(run.activeDuration() == 1_500)
        #expect(run.status == .complete)
    }

    @Test func openPauseStopsTheClock() {
        let run = makeRun()
        run.pause(at: start.addingTimeInterval(60))

        #expect(run.activeDuration(at: start.addingTimeInterval(500)) == 60)
    }

    @Test func distanceOnlyGrowsWhileActive() {
        let run = makeRun()
        run.record(sample(at: 0, kilometersNorth: 0))
        run.record(sample(at: 300, kilometersNorth: 1))
        let afterFirstKilometer = run.distanceMeters

        run.pause(at: start.addingTimeInterval(301))
        run.record(sample(at: 400, kilometersNorth: 2))
        #expect(run.distanceMeters == afterFirstKilometer)

        run.resume(at: start.addingTimeInterval(401))
        run.record(sample(at: 700, kilometersNorth: 3))

        #expect(abs(afterFirstKilometer - 1_000) < 10)
        #expect(abs(run.distanceMeters - 2_000) < 20)
        #expect(run.route.count == 4)
    }

    @Test func outOfOrderSamplesAreIgnored() {
        let run = makeRun()
        run.record(sample(at: 100, kilometersNorth: 0))
        run.record(sample(at: 50, kilometersNorth: 1))

        #expect(run.route.count == 1)
        #expect(run.distanceMeters == 0)
    }

    @Test func finishedRunsRefuseChanges() {
        let run = makeRun()
        run.finish(at: start.addingTimeInterval(60))
        run.resume()
        run.record(sample(at: 120, kilometersNorth: 1))

        #expect(run.status == .complete)
        #expect(run.route.isEmpty)
    }

    @Test func paceIsPerKilometer() {
        let run = makeRun()
        run.record(sample(at: 0, kilometersNorth: 0))
        run.record(sample(at: 300, kilometersNorth: 1))
        run.finish(at: start.addingTimeInterval(300))

        let pace = try! #require(run.pace())
        #expect(abs(pace - 300) < 5)
    }
}
