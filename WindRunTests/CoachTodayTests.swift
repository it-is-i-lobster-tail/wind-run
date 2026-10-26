//
//  CoachTodayTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// What the Run screen's second start button offers: today's workout, a rest day with the next run,
/// a finished day, or nothing once the plan is over.
@MainActor
struct CoachTodayTests {
    private let container = WindRunSchema.makeContainer(inMemory: true)
    private let calendar = CoachFixtures.calendar

    private var service: CoachService {
        CoachService(context: container.mainContext, calendar: calendar, unit: .kilometers)
    }

    private func startPlan() -> CoachPlan {
        let intake = CoachFixtures.regularIntake()
        return service.startPlan(intake: intake, goal: intake.goal, level: .steady, insisted: false, now: CoachFixtures.day(0)).0
    }

    /// The first week's runs by day.
    private func firstWeekRuns(_ state: CoachState) throws -> (week: PlannedWeek, runs: [PlannedSession]) {
        let week = try #require(state.weeks.first?.plan)
        return (week, week.sessions.filter { $0.kind.isRun && $0.status.isPlanned }.sorted { $0.dayOffset < $1.dayOffset })
    }

    @Test func aDayWithARunOffersIt() throws {
        let plan = startPlan()
        let state = try #require(service.state(of: plan))
        let (week, runs) = try firstWeekRuns(state)
        let session = try #require(runs.first)
        let workout = try #require(plan.week(at: week.index)?.workout(withSessionID: session.id))

        let now = CoachFixtures.day(session.dayOffset, from: week.start)
        #expect(CoachToday.of(plan, state: state, now: now, calendar: calendar) == .workout(workout))
        #expect(CoachToday.workouts(plan, state: state, now: now, calendar: calendar) == [workout])
    }

    @Test func aRestDayNamesTheNextRun() throws {
        let plan = startPlan()
        let state = try #require(service.state(of: plan))
        let (week, runs) = try firstWeekRuns(state)
        let runDays = Set(runs.map(\.dayOffset))
        // A day with no run that still has a run after it this week.
        let restDay = try #require((0..<7).first { day in !runDays.contains(day) && runs.contains { $0.dayOffset > day } })
        let nextSession = try #require(runs.first { $0.dayOffset > restDay })
        let next = try #require(plan.week(at: week.index)?.workout(withSessionID: nextSession.id))

        let now = CoachFixtures.day(restDay, from: week.start)
        let expected: CoachToday = calendar.startOfDay(for: now) < calendar.startOfDay(for: plan.startDate)
            ? .startsLater(next: next)
            : .rest(next: next)
        #expect(CoachToday.of(plan, state: state, now: now, calendar: calendar) == expected)
    }

    @Test func aFinishedRunMakesTheDayDone() throws {
        let plan = startPlan()
        let state = try #require(service.state(of: plan))
        let (week, runs) = try firstWeekRuns(state)
        let session = try #require(runs.first)
        let workout = try #require(plan.week(at: week.index)?.workout(withSessionID: session.id))

        let start = CoachFixtures.day(session.dayOffset, from: week.start)
        let run = Run(kind: .coached, startDate: start)
        container.mainContext.insert(run)
        run.coachWorkoutValue = workout
        run.finish(at: start.addingTimeInterval(30 * 60))
        let now = start.addingTimeInterval(3_600)
        try #require(service.saveCheckIn(RunCheckIn(answeredAt: now, rpe: 3, talkTest: true, feel: .ok), for: run, in: plan, now: now) != nil)
        let after = try #require(service.state(of: plan))

        let next = CoachToday.nextRun(plan, state: after, now: now, calendar: calendar)
        #expect(CoachToday.of(plan, state: after, now: now, calendar: calendar) == .done(next: next))
        #expect(next?.sessionID != session.id)
    }

    @Test func thePlansFirstDayIsStillToCome() throws {
        let plan = startPlan()
        let state = try #require(service.state(of: plan))
        let now = CoachFixtures.day(-1, from: calendar.startOfDay(for: plan.startDate))

        guard case .startsLater = CoachToday.of(plan, state: state, now: now, calendar: calendar) else {
            Issue.record("Expected the plan to start later")
            return
        }
    }

    @Test func aStoppedPlanOffersOnlyTheFreeRun() throws {
        let plan = startPlan()
        service.perform(on: plan, now: CoachFixtures.day(1)) { state, _, now, _ in CoachEngine.stopPlan(state: state, now: now) }
        let state = try #require(service.state(of: plan))

        #expect(CoachToday.of(plan, state: state, now: CoachFixtures.day(1), calendar: calendar) == nil)
    }
}
