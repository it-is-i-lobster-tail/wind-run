//
//  HealthWorkoutEnergyTests.swift
//  Wind Run Tests
//

import CoreLocation
import Foundation
import Testing
@testable import WindRun

/// A run's calories as Health gets them, and the edges of how its distance is split into stretches.
@MainActor
struct HealthWorkoutEnergyTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let container = WindRunSchema.makeContainer(inMemory: true)

    /// A run heading north a meter a second, with a fix every second, finished at `seconds`.
    private func makeRun(seconds: Int) -> Run {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        for second in 0...seconds {
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

    /// A fix `meters` north of the start, `seconds` in.
    private func fix(_ seconds: TimeInterval, meters: Double) -> (timestamp: Date, location: CLLocation) {
        (start.addingTimeInterval(seconds), CLLocation(latitude: meters / 111_000, longitude: 0))
    }

    @Test func caloriesAreSpreadByTheGroundEachStretchCovered() throws {
        let run = makeRun(seconds: 65)
        run.activeCaloriesValue = 300
        let workout = try #require(HealthWorkout(run))
        #expect(workout.activeCalories == 300)

        let energy = workout.energySegments
        #expect(energy.count == workout.distance.count)
        #expect(!energy.isEmpty)
        let total = energy.reduce(0) { $0 + $1.kilocalories }
        #expect(abs(total - 300) < 1e-9)

        let meters = workout.distance.reduce(0) { $0 + $1.meters }
        for (calories, segment) in zip(energy, workout.distance) {
            #expect(calories.start == segment.start)
            #expect(calories.end == segment.end)
            #expect(abs(calories.kilocalories / 300 - segment.meters / meters) < 1e-9)
        }
    }

    @Test func noCaloriesSendNoEnergy() throws {
        let run = makeRun(seconds: 30)
        run.activeCaloriesValue = 0
        let zero = try #require(HealthWorkout(run))
        #expect(zero.activeCalories == nil)
        #expect(zero.energySegments.isEmpty)

        run.activeCaloriesValue = nil
        let none = try #require(HealthWorkout(run))
        #expect(none.activeCalories == nil)
        #expect(none.energySegments.isEmpty)
    }

    @Test func aStretchAfterAPauseStartsAtTheResume() {
        let pause = DateInterval(start: start.addingTimeInterval(4), end: start.addingTimeInterval(8))
        let segments = HealthWorkout.segments(
            route: [fix(0, meters: 0), fix(5, meters: 5), fix(12, meters: 12)],
            pauses: [pause],
            totalMeters: 100
        )
        #expect(segments.count == 1)
        #expect(segments.first?.start == pause.end)
        #expect(segments.first?.end == start.addingTimeInterval(12))
        #expect(abs((segments.first?.meters ?? 0) - 100) < 1e-9)
    }

    @Test func noDistanceGivesNoStretches() {
        let route = [fix(0, meters: 0), fix(5, meters: 5), fix(10, meters: 10)]
        #expect(HealthWorkout.segments(route: route, pauses: [], totalMeters: 0).isEmpty)
        #expect(HealthWorkout.segments(route: [fix(0, meters: 0)], pauses: [], totalMeters: 100).isEmpty)
    }

    @Test func aPauseStillOpenEndsWithTheRun() throws {
        let run = makeRun(seconds: 60)
        run.pausesValue = (run.pausesValue ?? []) + [RunPause(startDate: start.addingTimeInterval(50))]
        let workout = try #require(HealthWorkout(run))
        #expect(workout.pauses == [DateInterval(start: start.addingTimeInterval(50), end: start.addingTimeInterval(60))])
    }
}
