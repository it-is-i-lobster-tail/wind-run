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
}
