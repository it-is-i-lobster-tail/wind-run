//
//  WorkoutsTests.swift
//  Wind Run Tests
//

import Foundation
import HealthKit
import SwiftData
import Testing
@testable import WindRun

/// The Workout page: its built-in workouts, the runner's own ones, and the distance or time a run sets out for.
@MainActor
struct WorkoutsTests {
    @Test func theBuiltInWorkoutsAreDistanceTimeThenFree() {
        #expect(WorkoutChoice.builtIn.map(\.name) == ["Distance Run", "Timed Run", "Free Run", "Cycling", "Hike"])
        #expect(WorkoutChoice.builtIn.map(\.type) == [.distance, .time, .free, .free, .free])
    }

    @Test func hikeHasATrailDisplayAndKeepsCustomDisplayChoices() {
        let library = DisplayLibrary(screens: [.standard])
        #expect(WorkoutChoice.hike.firstStep == .ready(.free(name: "Hike", sport: .hiking)))
        #expect(library.screen(id: nil, sport: .hiking).metrics == [.distance, .elevation, .elapsed, .altitude, .averagePace, .daylight])
        #expect(library.screen(id: UUID(), sport: .hiking) == .hike)
        #expect(library.screen(id: DisplayScreen.standard.id, sport: .hiking) == .standard)
        #expect(WorkoutSport.hiking.healthConfiguration.activityType == .hiking)
    }

    @Test func upgradeAdoptsExistingHikeAndItsHistoryInPlace() throws {
        let container = WindRunSchema.makeContainer(inMemory: true)
        let context = container.mainContext
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let displayID = UUID()
        let draft = WorkoutDraft(name: "hIKe", main: .distance(meters: 5000), unit: .miles, displayScreenID: displayID)
        let plan = draft.save(replacing: nil, in: context)
        plan.createdDateValue = .distantPast
        let run = Run(kind: .intervals)
        context.insert(run)
        run.intervalPlanValue = plan
        let other = WorkoutDraft(name: "Hike training", main: .free).save(replacing: nil, in: context)
        let timeline = plan.timeline
        WorkoutMigration.runIfNeeded(in: context, defaults: defaults)
        WorkoutMigration.runIfNeeded(in: context, defaults: defaults)
        #expect(try context.fetchCount(FetchDescriptor<IntervalPlan>()) == 2)
        #expect(plan.isSavedWorkout && plan.sport == .hiking)
        #expect(plan.timeline == timeline && plan.displayScreenID == displayID && plan.distanceUnit == .miles)
        #expect(run.intervalPlan == plan && run.sport == .hiking)
        #expect(other.sport == .running)
        #expect(WatchSavedWorkout(plan).workoutTypeValue == WorkoutSport.hiking.rawValue)
    }

    @Test func eachTypeOpensWhatItNeedsFirst() {
        #expect(WorkoutChoice.distanceRun.firstStep == .distance(.distanceRun))
        #expect(WorkoutChoice.timedRun.firstStep == .time(.timedRun))
        // A free run has nothing to pick, so it goes straight to Start.
        #expect(WorkoutChoice.cycling.firstStep == .ready(.free(name: "Cycling", sport: .cycling)))
        #expect(WorkoutChoice.freeRun.firstStep == .ready(.free(name: "Free Run")))
    }

    @Test func theBuiltInRunsRememberWhatWasPicked() {
        let defaults = UserDefaults(suiteName: "WorkoutsTests.\(UUID().uuidString)")!
        #expect(WorkoutChoice.distanceRun.lastGoal(defaults: defaults) == nil)
        WorkoutChoice.distanceRun.saveGoal(10_000, defaults: defaults)
        #expect(WorkoutChoice.distanceRun.lastGoal(defaults: defaults) == 10_000)
        #expect(WorkoutChoice.timedRun.lastGoal(defaults: defaults) == nil)
    }

    /// A line for each part, leaving out a warm-up or cooldown the workout doesn't have.
    @Test func aRunnersWorkoutIsSummedUpPartByPart() {
        typealias Part = WorkoutSummary.Part
        #expect(WorkoutSummary.parts(.starter()) == [
            Part(label: "Warm-up", value: "5 min"), Part(label: "Main", value: "20 min run"), Part(label: "Cooldown", value: "5 min"),
        ])
        #expect(WorkoutSummary.parts(WorkoutDraft(name: "", warmup: .open, main: .distance(meters: 5_000), cooldown: .open)) == [
            Part(label: "Warm-up", value: "Until Next"), Part(label: "Main", value: "5 km run"), Part(label: "Cooldown", value: "Until Next"),
        ])
        #expect(WorkoutSummary.parts(WorkoutDraft(name: "", main: .time(90 * 60), unit: .miles)) == [Part(label: "Main", value: "90 min run")])
        // Intervals are just "Intervals" here; the workout's page has the rest.
        let intervals = WorkoutDraft(name: "", main: .intervals(.init(work: .time(300), recovery: .time(120), repeats: 4)), cooldown: .time(300))
        #expect(WorkoutSummary.parts(intervals).map(\.value) == ["Intervals", "5 min"])
        #expect(WorkoutSummary.spoken(WorkoutSummary.parts(intervals)) == "Main, Intervals. Cooldown, 5 min.")
    }

    @Test func theDistanceWheelStartsFromLastTimeInWholeUnits() {
        #expect(DistanceGoalOptions.startingAmount(lastMeters: nil, unit: .kilometers) == 5)
        #expect(DistanceGoalOptions.startingAmount(lastMeters: nil, unit: .miles) == 3)
        #expect(DistanceGoalOptions.startingAmount(lastMeters: 10_000, unit: .kilometers) == 10)
        // Picked in miles, then the runner switched to kilometers.
        #expect(DistanceGoalOptions.startingAmount(lastMeters: 5 * 1_609.344, unit: .kilometers) == 8)
        #expect(DistanceGoalOptions.startingAmount(lastMeters: 200, unit: .kilometers) == 1)
        #expect(DistanceGoalOptions.startingAmount(lastMeters: 500_000, unit: .kilometers) == 100)
    }

    /// A half marathon picked last time opens as a half marathon, in either unit, not rounded to 21 or 13.
    @Test func aRaceDistanceIsKeptToTheMeter() {
        #expect(DistanceGoalOptions.startingMeters(lastMeters: 21_097.5, unit: .kilometers) == 21_097.5)
        #expect(DistanceGoalOptions.startingMeters(lastMeters: 42_195, unit: .miles) == 42_195)
        #expect(DistanceGoalOptions.startingMeters(lastMeters: 8_000, unit: .kilometers) == 8_000)
        #expect(DistanceGoalOptions.startingMeters(lastMeters: nil, unit: .miles) == 3 * 1_609.344)
        #expect(DistanceGoalOptions.race(at: 21_097.5)?.spokenName == "Half marathon")
        #expect(WorkoutFormat.distance(21_097.5, unit: .kilometers) == "21.1 km")
        #expect(WorkoutFormat.distance(42_195, unit: .miles) == "26.2 mi")
        #expect(WorkoutFormat.distance(5_000, unit: .miles) == "3.1 mi")
    }

    @Test func theTimeWheelsStartFromLastTimeToTheMinute() {
        #expect(TimeGoalOptions.startingSeconds(last: nil) == 30 * 60)
        #expect(TimeGoalOptions.startingSeconds(last: 45 * 60 + 20) == 45 * 60)
        #expect(TimeGoalOptions.startingSeconds(last: 10) == 60)
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
        #expect(DisplayMetric.distance.reading(distance).label == "OF 5.0 KM")
        let time = RunSnapshot(elapsed: 600, meters: 2_000, unit: .kilometers, goalSeconds: RunGoal.time(seconds: 1_800).seconds)
        #expect(DisplayMetric.elapsed.reading(time).label == "OF 30:00")
    }

    @Test func pickedDistancesAndTimesSyncLikeOtherSettings() {
        #expect(CloudSettings.keys.contains(WorkoutGoalMemory.distanceKey))
        #expect(CloudSettings.keys.contains(WorkoutGoalMemory.timeKey))
    }
}
