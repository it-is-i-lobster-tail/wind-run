//
//  WorkoutsTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// The Workout page: its built-in workouts, the runner's own ones, and the distance or time a run sets out for.
@MainActor
struct WorkoutsTests {
    @Test func theBuiltInWorkoutsAreDistanceTimeIntervalsThenFree() {
        #expect(WorkoutChoice.builtIn.map(\.name) == ["Distance Run", "Timed Run", "Intervals", "Free Run"])
        #expect(WorkoutChoice.builtIn.map(\.type) == [.distance, .time, .intervals, .free])
    }

    @Test func eachTypeOpensWhatItNeedsFirst() {
        let city = WorkoutChoice(name: "City Run", type: .distance)
        #expect(city.firstStep == .distance(city))
        #expect(WorkoutChoice.timedRun.firstStep == .time(.timedRun))
        #expect(WorkoutChoice.intervals.firstStep == .intervals(.intervals))
        // A free run has nothing to pick, so it goes straight to Start.
        #expect(WorkoutChoice.freeRun.firstStep == .ready(.free(name: "Free Run")))
    }

    @Test func aRunnersWorkoutKeepsItsNameAndType() throws {
        let container = WindRunSchema.makeContainer(inMemory: true)
        let context = container.mainContext
        let workout = Workout(name: "Trail Blaster", type: .time)
        context.insert(workout)
        try context.save()

        let saved = try #require(try context.fetch(FetchDescriptor<Workout>()).first)
        #expect(saved.name == "Trail Blaster")
        #expect(saved.type == .time)
        #expect(WorkoutChoice(saved).firstStep == .time(WorkoutChoice(saved)))

        context.delete(saved)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Workout>()) == 0)
    }

    @Test func aTypeFromANewerVersionStartsAsAFreeRun() {
        let workout = Workout(name: "Night Run", type: .distance)
        workout.typeValue = "somethingNew"
        #expect(workout.type == .free)
    }

    @Test func changingTheTypeForgetsTheLastGoal() {
        let workout = Workout(name: "City Run", type: .distance)
        workout.lastGoal = 5_000
        workout.type = .distance
        #expect(workout.lastGoal == 5_000)
        workout.type = .time
        #expect(workout.lastGoal == nil)
    }

    @Test func namesAreKeptShort() {
        let workout = Workout(name: "", type: .free)
        workout.name = String(repeating: "a", count: 60)
        #expect(workout.name.count == Workout.nameLimit)
    }

    @Test func aRunnersWorkoutRemembersItsOwnDistance() {
        let defaults = UserDefaults(suiteName: "WorkoutsTests.\(UUID().uuidString)")!
        let workout = Workout(name: "City Run", type: .distance)
        let choice = WorkoutChoice(workout)
        #expect(choice.lastGoal(defaults: defaults) == nil)
        choice.saveGoal(8_000, defaults: defaults)
        #expect(workout.lastGoal == 8_000)
        // The built-in Distance Run keeps its own.
        #expect(WorkoutChoice.distanceRun.lastGoal(defaults: defaults) == nil)
        WorkoutChoice.distanceRun.saveGoal(10_000, defaults: defaults)
        #expect(WorkoutChoice.distanceRun.lastGoal(defaults: defaults) == 10_000)
        #expect(WorkoutChoice.timedRun.lastGoal(defaults: defaults) == nil)
    }

    @Test func theDistanceWheelStartsFromLastTimeInWholeUnits() {
        #expect(DistanceGoalView.startingAmount(lastMeters: nil, unit: .kilometers) == 5)
        #expect(DistanceGoalView.startingAmount(lastMeters: nil, unit: .miles) == 3)
        #expect(DistanceGoalView.startingAmount(lastMeters: 10_000, unit: .kilometers) == 10)
        // Picked in miles, then the runner switched to kilometers.
        #expect(DistanceGoalView.startingAmount(lastMeters: 5 * 1_609.344, unit: .kilometers) == 8)
        #expect(DistanceGoalView.startingAmount(lastMeters: 200, unit: .kilometers) == 1)
        #expect(DistanceGoalView.startingAmount(lastMeters: 500_000, unit: .kilometers) == 100)
    }

    /// A half marathon picked last time opens as a half marathon, in either unit, not rounded to 21 or 13.
    @Test func aRaceDistanceIsKeptToTheMeter() {
        #expect(DistanceGoalView.startingMeters(lastMeters: 21_097.5, unit: .kilometers) == 21_097.5)
        #expect(DistanceGoalView.startingMeters(lastMeters: 42_195, unit: .miles) == 42_195)
        #expect(DistanceGoalView.startingMeters(lastMeters: 8_000, unit: .kilometers) == 8_000)
        #expect(DistanceGoalView.startingMeters(lastMeters: nil, unit: .miles) == 3 * 1_609.344)
        #expect(DistanceGoalView.race(at: 21_097.5)?.spokenName == "Half marathon")
        #expect(WorkoutFormat.distance(21_097.5, unit: .kilometers) == "21.1 km")
        #expect(WorkoutFormat.distance(42_195, unit: .miles) == "26.2 mi")
        #expect(WorkoutFormat.distance(5_000, unit: .miles) == "3.1 mi")
    }

    @Test func theTimeWheelsStartFromLastTimeToTheMinute() {
        #expect(TimeGoalView.startingSeconds(last: nil) == 30 * 60)
        #expect(TimeGoalView.startingSeconds(last: 45 * 60 + 20) == 45 * 60)
        #expect(TimeGoalView.startingSeconds(last: 10) == 60)
    }

    @Test func goalsAreWrittenShort() {
        #expect(WorkoutFormat.distance(5_000, unit: .kilometers) == "5 km")
        #expect(WorkoutFormat.distance(13 * 1_609.344, unit: .miles) == "13 mi")
        #expect(WorkoutFormat.time(45 * 60) == "45 min")
        #expect(WorkoutFormat.time(60 * 60) == "1 h")
        #expect(WorkoutFormat.time(90 * 60) == "1 h 30 min")
    }

    @Test func aRunKeepsItsGoal() {
        let run = Run()
        #expect(run.goal == nil)
        run.goal = .distance(meters: 5_000)
        #expect(run.goal == .distance(meters: 5_000))
        #expect(run.goalSecondsValue == nil)
        run.goal = .time(seconds: 1_800)
        #expect(run.goal == .time(seconds: 1_800))
        #expect(run.goalMetersValue == nil)
        run.goal = nil
        #expect(run.goal == nil)
    }

    @Test func aGoalIsReachedAtItsDistanceOrTime() {
        #expect(!RunGoal.distance(meters: 5_000).isReached(elapsed: 9_999, meters: 4_999))
        #expect(RunGoal.distance(meters: 5_000).isReached(elapsed: 0, meters: 5_000))
        #expect(!RunGoal.time(seconds: 1_800).isReached(elapsed: 1_799, meters: 99_999))
        #expect(RunGoal.time(seconds: 1_800).isReached(elapsed: 1_800, meters: 0))
    }

    @Test func theGoalShowsOnTheDisplayScreen() {
        let distance = RunSnapshot(elapsed: 600, meters: 2_000, unit: .kilometers, goalMeters: RunGoal.distance(meters: 5_000).meters)
        #expect(DisplayMetric.distance.reading(distance).label == "OF 5.00 KM")
        let time = RunSnapshot(elapsed: 600, meters: 2_000, unit: .kilometers, goalSeconds: RunGoal.time(seconds: 1_800).seconds)
        #expect(DisplayMetric.elapsed.reading(time).label == "OF 30:00")
    }

    @Test func pickedDistancesAndTimesSyncLikeOtherSettings() {
        #expect(CloudSettings.keys.contains(WorkoutGoalMemory.distanceKey))
        #expect(CloudSettings.keys.contains(WorkoutGoalMemory.timeKey))
    }
}
