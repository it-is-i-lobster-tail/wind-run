//
//  CoachServiceTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// The app side of the coach: the stored state, the copy of the weeks, and runs going in.
@MainActor
struct CoachServiceTests {
    private let container = WindRunSchema.makeContainer(inMemory: true)

    private var service: CoachService {
        CoachService(context: container.mainContext, calendar: CoachFixtures.calendar, unit: .kilometers)
    }

    private func startPlan() -> CoachPlan {
        let intake = CoachFixtures.regularIntake()
        return service.startPlan(intake: intake, goal: intake.goal, level: .steady, insisted: false, now: CoachFixtures.day(0)).0
    }

    @Test func startingStoresTheStateAndCopiesTheFirstWeek() throws {
        let plan = startPlan()
        let state = try #require(service.state(of: plan))

        #expect(plan.flavor == CoachGoal.buildDistance.rawValue)
        #expect(plan.status == .active)
        #expect(plan.rulesVersion == String(CoachState.currentRulesVersion))
        #expect(plan.weeks.count == state.weeks.count)

        let planned = try #require(state.weeks.first?.plan)
        let week = try #require(plan.week(at: planned.index))
        #expect(week.workouts.count == planned.sessions.count)
        #expect(Set(week.workouts.compactMap(\.sessionID)) == Set(planned.sessions.map(\.id)))
        #expect(week.title == planned.kind.name)
    }

    @Test func refreshingKeepsTheSameRows() throws {
        let plan = startPlan()
        let before = plan.weeks.flatMap(\.workouts)
        service.refresh(plan, now: CoachFixtures.day(0, hour: 12))
        let after = plan.weeks.flatMap(\.workouts)

        #expect(before.map(\.sessionID) == after.map(\.sessionID), "sessions \(before.map(\.sessionID)) then \(after.map(\.sessionID))")
        #expect(before.map(\.persistentModelID) == after.map(\.persistentModelID))
    }

    @Test func aRunStartedFromASessionReachesTheCoach() throws {
        let plan = startPlan()
        let state = try #require(service.state(of: plan))
        let session = try #require(state.weeks.first?.plan.sessions.first { $0.kind.isRun })
        let workout = try #require(plan.weeks.first?.workout(withSessionID: session.id))

        let start = CoachFixtures.day(session.dayOffset, from: state.startDate)
        let run = Run(kind: .coached, startDate: start)
        container.mainContext.insert(run)
        run.coachWorkoutValue = workout
        run.finish(at: start.addingTimeInterval(30 * 60))

        let logged = try #require(service.loggedRuns().first)
        #expect(logged.id == run.runID)
        #expect(logged.plannedSessionID == session.id)
        #expect(logged.source == .manual)
        #expect(abs(logged.movingSeconds - 1_800) < 1)

        let result = try #require(service.saveCheckIn(RunCheckIn(answeredAt: start, rpe: 3, talkTest: true, feel: .ok), for: run, in: plan, now: start.addingTimeInterval(3_600)))
        #expect(result.1.runID == run.runID)
        #expect(run.checkIn?.rpe == 3)
    }

    @Test func stepsBecomeAnIntervalWorkout() {
        let workout = CoachWorkout(kind: "intervals", dayOffset: 0)
        container.mainContext.insert(workout)
        let session = PlannedSession(
            dayOffset: 0,
            kind: .intervals,
            effort: .interval,
            target: Load(meters: 6_000, seconds: 2_400),
            blocks: [
                SessionBlock(steps: [SessionStep(kind: .warmup, goal: .time(seconds: 600), effort: .easy)]),
                SessionBlock(repeats: 4, steps: [
                    SessionStep(kind: .work, goal: .time(seconds: 180), effort: .interval),
                    SessionStep(kind: .recovery, goal: .time(seconds: 120), effort: .easy),
                ]),
            ]
        )
        let week = PlannedWeek(index: 0, start: CoachFixtures.monday, kind: .loading, volumeUnit: .distance, plannedVolume: 20_000, sessions: [session])
        let plan = CoachPlan(flavor: "speedWork", startDate: CoachFixtures.monday)
        container.mainContext.insert(plan)
        plan.addWeek(order: 0).addWorkout(sessionID: session.id, kind: "intervals", dayOffset: 0)

        var state = CoachFixtures.start(CoachFixtures.regularIntake())
        state.weeks = [WeekRecord(plan: week)]
        CoachProjection.apply(state, to: plan, in: container.mainContext, unit: .kilometers, calendar: CoachFixtures.calendar)

        let steps = plan.weeks.first?.workouts.first?.intervalPlan
        #expect(steps?.timeline.count == 9)
        #expect(steps?.timeline.filter { $0.kind == .work }.count == 4)
    }
}

@MainActor
struct CoachRefreshIDTests {
    @Test func sessionIDsSurviveARefreshOnTheSameDay() throws {
        let intake = CoachFixtures.regularIntake()
        let state = CoachFixtures.start(intake)
        let before = state.weeks.flatMap(\.plan.sessions).map(\.id)
        let after = CoachEngine.refresh(state: state, runs: [], now: CoachFixtures.day(0, hour: 12), calendar: CoachFixtures.calendar).state.weeks.flatMap(\.plan.sessions).map(\.id)
        #expect(before == after)
        let roundTripped = try JSONDecoder().decode(CoachState.self, from: JSONEncoder().encode(state))
        #expect(roundTripped == state)
    }
}
