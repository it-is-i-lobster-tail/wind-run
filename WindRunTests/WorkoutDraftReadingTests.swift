//
//  WorkoutDraftReadingTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// How a saved workout is read back into a draft, which unit its distances are guessed to be in, and how the
/// builder writes and reads a part.
@MainActor
struct WorkoutDraftReadingTests {
    private let container = WindRunSchema.makeContainer(inMemory: true)
    private var context: ModelContext { container.mainContext }

    // MARK: Units

    @Test func aDistanceReadsInTheUnitItsRoundIn() {
        #expect(WorkoutDistance.unit(for: 1_000, preferred: .miles) == .kilometers)
        #expect(WorkoutDistance.unit(for: 1_609.344, preferred: .kilometers) == .miles)
        // Round in neither, so it stays in the runner's own.
        #expect(WorkoutDistance.unit(for: 1_234.5, preferred: .miles) == .miles)
        #expect(WorkoutDistance.other(than: .kilometers) == .miles)
        #expect(WorkoutDistance.other(than: .miles) == .kilometers)
    }

    @Test func aWorkoutsUnitIsTheOtherOneOnlyWhenEveryDistanceIsRoundInIt() {
        #expect(WorkoutDraft.guessedUnit([], preferred: .miles) == .miles)
        #expect(WorkoutDraft.guessedUnit([8_046.72], preferred: .kilometers) == .miles)
        #expect(WorkoutDraft.guessedUnit([5_000], preferred: .miles) == .kilometers)
        #expect(WorkoutDraft.guessedUnit([5_000, 1_609.344], preferred: .kilometers) == .kilometers)
    }

    // MARK: Older plans

    @Test func aPlanWithNoStepsOpensAsTheStarterIntervals() {
        let plan = IntervalPlan(name: "Empty", isCustom: true)
        context.insert(plan)
        let draft = WorkoutDraft(plan)
        #expect(draft.main == .starter)
        #expect(draft.warmup == nil)
        #expect(draft.cooldown == nil)
    }

    @Test func aLoneWarmupIsTheMainPart() {
        let plan = IntervalPlan(name: "Warm-up only", isCustom: true)
        plan.addBlock().addStep(.warmup, goal: .time(600))
        context.insert(plan)
        let draft = WorkoutDraft(plan)
        #expect(draft.warmup == nil)
        #expect(draft.main == .time(600))
    }

    @Test func repeatsWithoutARecoveryGetTheStarterRecovery() {
        let plan = IntervalPlan(name: "Strides", isCustom: true)
        plan.addBlock(repeatCount: 3).addStep(.work, goal: .time(60))
        context.insert(plan)
        #expect(WorkoutDraft(plan).main == .intervals(.init(work: .time(60), recovery: .time(120), repeats: 3)))
        #expect(WorkoutMain.Intervals.starterRecoverySeconds == 120)
    }

    @Test func theStarterIntervalsAreFourOfFiveMinutesAndTwo() {
        #expect(WorkoutMain.starter == .intervals(.init(work: .time(300), recovery: .time(120), repeats: 4)))
    }

    @Test func aDraftsTimelineIsTheSavedWorkoutsTimeline() {
        let mains: [WorkoutMain] = [
            .time(45 * 60),
            .distance(meters: 5_000),
            .free,
            .intervals(.init(work: .distance(meters: 400), recovery: .open, repeats: 8)),
            .intervals(.init(work: .open, recovery: .time(60), repeats: 1)),
        ]
        for main in mains {
            let draft = WorkoutDraft(name: "W", warmup: .time(600), main: main, cooldown: .open)
            let plan = draft.save(replacing: nil, in: context)
            #expect(draft.timeline == plan.timeline)
        }
    }

    // MARK: Writing a part

    @Test func aPartsEndReadsAsTheBuilderWritesIt() {
        #expect(WorkoutDistance.endDetail(.open, unit: .kilometers) == "Until you tap Next")
        #expect(WorkoutDistance.endDetail(.open, unit: .kilometers) == WorkoutDistance.untilNextDetail)
        #expect(WorkoutDistance.endDetail(.time(600), unit: .kilometers) == "10 min")
        #expect(WorkoutDistance.endDetail(.time(600), unit: .kilometers) == WorkoutDistance.text(of: .time(600), unit: .kilometers))
        #expect(WorkoutDistance.endDetail(.distance(meters: 1_000), unit: .kilometers) == "1 km")
        #expect(WorkoutDistance.text(of: .open, unit: .kilometers) == "Until Next")
    }

    @Test func workoutTypesAreNamedAsTheBuiltInRows() {
        #expect(WorkoutType.allCases.map(\.name) == ["Distance run", "Timed run", "Intervals", "Free run", "Waypoint"])
    }

    @Test func aGoalOpensOnItsOwnEnding() {
        #expect(WorkoutEnding(.time(60)) == .time)
        #expect(WorkoutEnding(.distance(meters: 400)) == .distance)
        #expect(WorkoutEnding(.open) == .manual)
        #expect(WorkoutEnding(.waypoint(.startingPoint)) == .waypoint)
    }

    @Test func aDistanceRunStartsAtThreeMilesOrFiveKilometers() {
        #expect(WorkoutMainPage.defaultDistanceMeters(.miles) == 3 * 1_609.344)
        #expect(WorkoutMainPage.defaultDistanceMeters(.kilometers) == 5_000)
    }

    @Test func theTimedRunStartsNoLaterThanItsWheelsGo() {
        #expect(TimeGoalOptions.startingSeconds(last: 12 * 3_600) == (9 * 60 + 59) * 60)
        #expect(TimeGoalOptions.startingSeconds(last: Double(TimeGoalOptions.maxHours * 3_600)) == Double(TimeGoalOptions.maxHours * 3_600))
    }

    // MARK: Minutes and seconds

    @Test func timesAndPacesAreWrittenAsMinutesAndSeconds() {
        #expect(WorkoutDistance.minutesSeconds(300) == "5:00")
        #expect(WorkoutDistance.minutesSeconds(89.6) == "1:30")
        #expect(WorkoutDistance.minutesSeconds(65) == "1:05")
        #expect(WorkoutDistance.pacePerUnit(300, unit: .kilometers) == "5:00")
        // 300 s/km is 482.8 s/mi.
        #expect(WorkoutDistance.pacePerUnit(300, unit: .miles) == "8:03")
        #expect(WorkoutDistance.paceText(300...300, unit: .kilometers) == "5:00 min/km")
        #expect(WorkoutDistance.paceText(300...330, unit: .kilometers) == "5:00–5:30 min/km")
        #expect(PaceEntry.text(300, unit: .miles) == WorkoutDistance.pacePerUnit(300, unit: .miles))
        #expect(IntervalSetEntry.timeText(90) == "1:30")
    }

    // MARK: Reading the boxes

    @Test func aTimeIsReadFromItsMinutesAndSeconds() {
        func read(_ minutes: String, _ seconds: String) -> IntervalGoal? {
            WorkoutEndFields.goal(ending: .time, minutes: minutes, seconds: seconds, amount: "", exactMeters: nil, unit: .kilometers)
        }
        #expect(read("5", "30") == .time(330))
        #expect(read("", "45") == .time(45))
        #expect(read("x", "45") == .time(45))
        #expect(read("", "") == nil)
        #expect(read("0", "0") == nil)
    }

    @Test func aDistanceIsReadInTheUnitAndKeepsItsExactMeters() {
        func read(_ amount: String, exact: Double?, unit: DistanceUnit) -> IntervalGoal? {
            WorkoutEndFields.goal(ending: .distance, minutes: "", seconds: "", amount: amount, exactMeters: exact, unit: unit)
        }
        #expect(read("1,5", exact: nil, unit: .kilometers) == .distance(meters: 1_500))
        #expect(read("2", exact: nil, unit: .miles) == .distance(meters: 2 * 1_609.344))
        #expect(read("0", exact: nil, unit: .kilometers) == nil)
        #expect(read("far", exact: nil, unit: .kilometers) == nil)
        // While the box still shows the exact distance, the exact meters are kept.
        let quarterMile = 402.336
        #expect(read(WorkoutDistance.amount(quarterMile, in: .miles), exact: quarterMile, unit: .miles) == .distance(meters: quarterMile))
    }

    @Test func aManualEndIsOpen() {
        #expect(WorkoutEndFields.goal(ending: .manual, minutes: "", seconds: "", amount: "", exactMeters: nil, unit: .kilometers) == .open)
    }
}
