//
//  CoachReplanTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// Re-plans that shrink or drop sessions from a week that was already copied, and the race-day
/// limits on the intake.
@MainActor
struct CoachReplanTests {
    private let container = WindRunSchema.makeContainer(inMemory: true)

    private var service: CoachService {
        CoachService(context: container.mainContext, calendar: CoachFixtures.calendar, unit: .kilometers)
    }

    private func startPlan() throws -> (CoachPlan, CoachState) {
        let intake = CoachFixtures.regularIntake()
        let plan = service.startPlan(intake: intake, goal: intake.goal, level: .steady, insisted: false, now: CoachFixtures.day(0)).0
        return (plan, try #require(service.state(of: plan)))
    }

    private func storedWorkouts() throws -> [CoachWorkout] {
        try container.mainContext.fetch(FetchDescriptor<CoachWorkout>())
    }

    // MARK: Dropped sessions

    @Test func aDroppedSessionLeavesNoRow() throws {
        let (plan, started) = try startPlan()
        var state = started
        let week = try #require(state.weeks.first?.plan)
        let dropped = try #require(week.sessions.last { $0.kind.isRun })
        state.weeks[0].plan.sessions.removeAll { $0.id == dropped.id }

        CoachProjection.apply(state, to: plan, in: container.mainContext, unit: .kilometers, calendar: CoachFixtures.calendar)
        try container.mainContext.save()

        let copied = try #require(plan.week(at: week.index))
        #expect(copied.workouts.count == week.sessions.count - 1)
        #expect(copied.workout(withSessionID: dropped.id) == nil)
        // Deleted, not just unlinked from the week.
        #expect(try storedWorkouts().allSatisfy { $0.sessionID != dropped.id })
        #expect(try storedWorkouts().count == plan.weeks.flatMap(\.workouts).count)
    }

    @Test func aShrunkSessionUpdatesItsRow() throws {
        let (plan, started) = try startPlan()
        var state = started
        let position = try #require(state.weeks[0].plan.sessions.firstIndex { $0.kind.isRun })
        let session = state.weeks[0].plan.sessions[position]
        state.weeks[0].plan.sessions[position].target = session.target.scaled(by: 0.5)

        CoachProjection.apply(state, to: plan, in: container.mainContext, unit: .kilometers, calendar: CoachFixtures.calendar)

        let row = try #require(plan.week(at: state.weeks[0].plan.index)?.workout(withSessionID: session.id))
        let expected = CoachProjection.target(for: state.weeks[0].plan.sessions[position], unit: .kilometers, calendar: CoachFixtures.calendar, weekStart: state.weeks[0].plan.start)
        #expect(row.target == expected)
    }

    @Test func aWeekWithEveryRunDroppedEmptiesButStays() throws {
        let (plan, started) = try startPlan()
        var state = started
        let index = state.weeks[0].plan.index
        state.weeks[0].plan.sessions = []

        CoachProjection.apply(state, to: plan, in: container.mainContext, unit: .kilometers, calendar: CoachFixtures.calendar)

        let copied = try #require(plan.week(at: index))
        #expect(copied.workouts.isEmpty)
        #expect(try storedWorkouts().isEmpty)
    }

    @Test func aDroppedSessionThatWasRunStays() throws {
        let (plan, started) = try startPlan()
        var state = started
        let week = try #require(state.weeks.first?.plan)
        let session = try #require(week.sessions.first { $0.kind.isRun })
        let workout = try #require(plan.week(at: week.index)?.workout(withSessionID: session.id))
        let start = CoachFixtures.day(session.dayOffset, from: week.start)
        let run = Run(kind: .coached, startDate: start)
        container.mainContext.insert(run)
        run.coachWorkoutValue = workout
        run.finish(at: start.addingTimeInterval(30 * 60))

        state.weeks[0].plan.sessions.removeAll { $0.id == session.id }
        CoachProjection.apply(state, to: plan, in: container.mainContext, unit: .kilometers, calendar: CoachFixtures.calendar)

        // The run's session is history, so it keeps its row and its run.
        let kept = try #require(plan.week(at: week.index)?.workout(withSessionID: session.id))
        #expect(kept.runs.map(\.runID) == [run.runID])
    }

    @Test func aWeekTheEngineDropsIsRemoved() throws {
        let (plan, state) = try startPlan()
        let extra = plan.addWeek(order: 40)
        extra.addWorkout(kind: "easy", dayOffset: 1)

        CoachProjection.apply(state, to: plan, in: container.mainContext, unit: .kilometers, calendar: CoachFixtures.calendar)

        #expect(plan.week(at: 40) == nil)
        #expect(plan.weeks.count == state.weeks.count)
    }

    // MARK: Race day

    @Test func raceDayIsTodayOrLaterWithinAYear() {
        let now = CoachFixtures.day(0, hour: 15)
        let calendar = CoachFixtures.calendar
        let model = CoachIntakeModel(flavor: .event, unit: .kilometers, now: now, calendar: calendar)

        func allows(_ date: Date?) -> Bool {
            model.intake.goal.eventDate = date
            return model.goalIsComplete
        }

        #expect(allows(calendar.date(byAdding: .weekOfYear, value: 16, to: now)))
        #expect(allows(calendar.startOfDay(for: now)))
        #expect(!allows(calendar.date(byAdding: .day, value: -1, to: now)))
        #expect(!allows(calendar.date(byAdding: .weekOfYear, value: 53, to: now)))
        #expect(!allows(nil))
    }

    /// A Speed Work goal time is stored in whole minutes inside its distance's limits when the runner moves on,
    /// including the first time the wheels show.
    @Test func speedWorkGoalTimeSettlesInsideItsLimits() {
        let model = CoachIntakeModel(flavor: .speedWork, unit: .kilometers, now: CoachFixtures.day(0), calendar: CoachFixtures.calendar)
        model.position = model.steps.firstIndex(of: .goal) ?? 0
        #expect(model.step == .goal)
        #expect(model.goalIsComplete)

        model.intake.goal.distance = .fiveK
        model.intake.goal.targetSeconds = nil
        model.settleShownAnswer()
        #expect(model.intake.goal.targetSeconds == 18 * 60)

        model.intake.goal.distance = .marathon
        model.intake.goal.targetSeconds = 3 * 3_600 + 12 * 60 + 30
        model.settleShownAnswer()
        #expect(model.intake.goal.targetSeconds == 210 * 60)

        model.intake.goal.distance = .tenK
        model.intake.goal.targetSeconds = 65 * 60 + 20
        model.settleShownAnswer()
        #expect(model.intake.goal.targetSeconds == 66 * 60)

        model.intake.goal.strongFirstTime = true
        model.intake.goal.targetSeconds = nil
        model.settleShownAnswer()
        #expect(model.intake.goal.targetSeconds == nil)
    }
}

/// Plans saved by earlier test builds whose state no longer decodes.
@MainActor
struct UnreadablePlanTests {
    private let container = WindRunSchema.makeContainer(inMemory: true)

    private var service: CoachService {
        CoachService(context: container.mainContext, calendar: CoachFixtures.calendar, unit: .kilometers)
    }

    @Test func anOldStateIsUnreadableAndCanBeStopped() throws {
        let plan = CoachPlan(flavor: CoachGoal.event.rawValue, startDate: CoachFixtures.day(0))
        container.mainContext.insert(plan)
        // A state from before fields were added: valid JSON the engine can't decode.
        plan.saveState(Data(#"{"status":"active","weeks":[]}"#.utf8), rulesVersion: "1")

        #expect(service.state(of: plan) == nil)
        #expect(service.hasUnreadableState(plan))
        #expect(service.currentPlan() === plan)

        service.retireUnreadable(plan)

        #expect(plan.status == .stopped)
        #expect(service.currentPlan() == nil)
    }

    @Test func aCurrentStateIsReadable() throws {
        let intake = CoachFixtures.regularIntake()
        let plan = service.startPlan(intake: intake, goal: intake.goal, level: .steady, insisted: false, now: CoachFixtures.day(0)).0

        #expect(!service.hasUnreadableState(plan))
        service.retireUnreadable(plan)
        #expect(plan.status == .active)
    }

    @Test func aPlanWithNoStateYetIsntUnreadable() {
        let plan = CoachPlan(flavor: CoachGoal.buildDistance.rawValue)
        container.mainContext.insert(plan)
        #expect(!service.hasUnreadableState(plan))
    }
}

/// Every goal at setup gets a plan: nothing is refused, swapped for an easier goal, or set aside.
@MainActor
struct SetupGoalTests {
    private let container = WindRunSchema.makeContainer(inMemory: true)
    private let calendar = CoachFixtures.calendar

    /// One run day used to refuse a 10K race for habit mode; now the race is planned.
    @Test func oneRunDayPlansTheRace() throws {
        let model = CoachIntakeModel(flavor: .event, unit: .kilometers, now: CoachFixtures.day(0), calendar: calendar)
        var intake = CoachFixtures.regularIntake(GoalChoice(flavor: .event, distance: .tenK, eventDate: CoachFixtures.day(140, hour: 9)))
        intake.finished = .yesRecently
        intake.runDays = [.sunday]
        model.intake = intake
        let check = model.checkGoal()
        #expect(check.verdict != .refused)
        #expect(model.savedGoal == nil)

        let service = CoachService(context: container.mainContext, calendar: calendar, unit: .kilometers)
        let plan = service.startPlan(
            intake: model.intake,
            goal: model.intake.goal,
            level: .steady,
            insisted: false,
            savedGoal: model.savedGoal,
            savedGoalEarliest: model.savedGoalEarliest,
            now: CoachFixtures.day(0)
        ).0
        let state = try #require(service.state(of: plan))
        #expect(state.goal == intake.goal)
        #expect(state.event != nil)
        #expect(state.savedGoal == nil)
    }

    /// A marathon 8 weeks out is a big goal: the only other option is the same race on a later day.
    @Test func aLaterRaceDayIsTheSameGoal() throws {
        let model = CoachIntakeModel(flavor: .event, unit: .kilometers, now: CoachFixtures.day(0), calendar: calendar)
        model.intake = CoachFixtures.regularIntake(GoalChoice(flavor: .event, distance: .marathon, eventDate: CoachFixtures.day(56, hour: 9)))
        let check = model.checkGoal()
        #expect(check.verdict == .red)
        let later = try #require(check.alternatives.first?.goal)
        #expect(check.alternatives.allSatisfy { $0.goal.distance == .marathon })

        model.choose(later, from: check)

        #expect(model.intake.goal == later)
        #expect(model.savedGoal == nil)
    }

    @Test func anAlternativeFromAGoodCheckSavesNothing() throws {
        let model = CoachIntakeModel(flavor: .buildDistance, unit: .kilometers, now: CoachFixtures.day(0), calendar: calendar)
        model.intake = CoachFixtures.regularIntake()
        let check = CoachEngine.checkGoal(model.intake.goal, intake: model.intake, level: .steady, now: CoachFixtures.day(0), calendar: calendar)
        if let alternative = check.alternatives.first?.goal {
            model.choose(alternative, from: check)
        }
        #expect(model.savedGoal == nil)
    }
}

/// One run day in plan settings switches to habit mode (one growing run a week) instead of stopping the plan.
@MainActor
struct OneRunDayTests {
    private let container = WindRunSchema.makeContainer(inMemory: true)

    @Test func oneRunDayKeepsThePlanAndSaysSo() throws {
        let intake = CoachFixtures.regularIntake()
        let service = CoachService(context: container.mainContext, calendar: CoachFixtures.calendar, unit: .kilometers)
        let plan = service.startPlan(intake: intake, goal: intake.goal, level: .steady, insisted: false, now: CoachFixtures.day(0)).0
        let inbox = CoachInbox()
        let actions = CoachActions(context: container.mainContext, plan: plan, inbox: inbox)

        let update = actions.perform { state, runs, now, calendar in
            CoachEngine.changeSchedule(runDays: [.sunday], weekdayMaxSeconds: nil, weekendMaxSeconds: nil, longRunDay: nil, state: state, runs: runs, now: now, calendar: calendar)
        }

        #expect(plan.status == .active)
        #expect(service.currentPlan() === plan)
        #expect(try #require(update).state.assessment.habitMode)
    }
}
