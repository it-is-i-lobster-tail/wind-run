//
//  HealthWorkoutTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

@MainActor
struct HealthWorkoutTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let container = WindRunSchema.makeContainer(inMemory: true)

    /// A run heading north a meter a second, with a fix every second.
    private func makeRun(seconds: Int, pause: ClosedRange<Int>? = nil) -> Run {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        for second in 0...seconds {
            if let pause, second == pause.lowerBound {
                run.pause(at: start.addingTimeInterval(Double(second)))
            }
            if let pause, second == pause.upperBound {
                run.resume(at: start.addingTimeInterval(Double(second)))
            }
            run.record(RouteSample(
                timestamp: start.addingTimeInterval(Double(second)),
                latitude: Double(second) / 111_000,
                longitude: 0,
                horizontalAccuracy: 5
            ))
        }
        run.finish(at: start.addingTimeInterval(Double(seconds)))
        return run
    }

    @Test func onlyCompletedRunsBecomeWorkouts() {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        #expect(HealthWorkout(run) == nil)

        run.discard(at: start.addingTimeInterval(60))
        #expect(HealthWorkout(run) == nil)
    }

    @Test func distanceMatchesTheRunInShortStretches() throws {
        let run = makeRun(seconds: 60)
        let workout = try #require(HealthWorkout(run))

        let total = workout.distance.reduce(0) { $0 + $1.meters }
        #expect(abs(total - run.distanceMeters) < 0.001)
        #expect(workout.distance.count == 6)
        #expect(workout.distance.allSatisfy { $0.end.timeIntervalSince($0.start) <= HealthWorkout.segmentLength })
        #expect(workout.route.count == 61)
        #expect(workout.start == start)
        #expect(workout.end == start.addingTimeInterval(60))
    }

    @Test func pausedStretchesAddNoDistance() throws {
        let run = makeRun(seconds: 60, pause: 20...40)
        let workout = try #require(HealthWorkout(run))

        #expect(workout.pauses == [DateInterval(start: start.addingTimeInterval(20), end: start.addingTimeInterval(40))])
        let pause = workout.pauses[0]
        #expect(workout.distance.allSatisfy { $0.end <= pause.start || $0.start >= pause.end })
        let total = workout.distance.reduce(0) { $0 + $1.meters }
        #expect(abs(total - run.distanceMeters) < 0.001)
        // 19 m before the pause and 21 m after it.
        #expect(abs(run.distanceMeters - 40) < 1)
    }

    @Test func fixesFromBeforeTheStartAreLeftOut() throws {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        run.record(RouteSample(timestamp: start.addingTimeInterval(-5), latitude: 0, longitude: 0, horizontalAccuracy: 5))
        run.record(RouteSample(timestamp: start.addingTimeInterval(5), latitude: 10 / 111_000, longitude: 0, horizontalAccuracy: 5))
        run.record(RouteSample(timestamp: start.addingTimeInterval(10), latitude: 20 / 111_000, longitude: 0, horizontalAccuracy: 5))
        run.finish(at: start.addingTimeInterval(10))

        let workout = try #require(HealthWorkout(run))
        #expect(workout.route.count == 2)
        #expect(workout.distance.allSatisfy { $0.start >= start })
    }

    @Test func savedWorkoutIsOnlyRecordedForCompletedRuns() {
        let id = UUID()
        let active = Run(startDate: start)
        container.mainContext.insert(active)
        active.markSavedToHealth(as: id)
        #expect(active.healthWorkoutID == nil)

        let finished = makeRun(seconds: 5)
        finished.markSavedToHealth(as: id)
        #expect(finished.healthWorkoutID == id)
    }
}
