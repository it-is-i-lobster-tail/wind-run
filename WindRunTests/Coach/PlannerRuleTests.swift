//
//  PlannerRuleTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// Planner rules across whole plans: calibration's floor, moves that survive a re-plan, event buffers and
/// starts, fitness checks on their schedule, and Q steps once volume holds (TI-5, AD-9, RC-4, EV-1, EV-10,
/// BD-5c, HL-3, HL-14).
@MainActor
struct PlannerRuleTests {
    let calendar = CoachFixtures.calendar

    func week(_ index: Int, _ state: CoachState) throws -> PlannedWeek {
        try #require(state.weeks.first { $0.plan.index == index }?.plan)
    }

    /// A 10K on the last day of plan week 30 (Sunday 9 August 2026).
    var raceDay: Date { CoachFixtures.day(7 * 30 + 6, hour: 0) }

    /// TI-5: a calibration week after one with no runs still plans at least 30% of V0.
    @Test func calibrationKeepsAFloor() throws {
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        let simulation = CoachFixtures.follow(state, days: 8, skip: { _, day in day < 7 })
        let second = try week(1, simulation.state)
        #expect(second.kind == .calibration)
        #expect(second.plannedVolume >= 0.3 * state.v0 - 0.001)
    }

    /// AD-9: a session the runner moved keeps its day when the week is planned again.
    @Test func movedSessionSurvivesAReplan() throws {
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        let long = try #require(try week(0, state).sessions.first { $0.kind == .long })
        let moved = CoachEngine.moveSession(long.id, toDay: long.dayOffset - 1, state: state, runs: [], now: CoachFixtures.day(0), calendar: calendar).state
        let replanned = CoachEngine.changeLevel(.gentle, state: moved, runs: [], now: CoachFixtures.day(0, hour: 9), calendar: calendar).state
        let session = try #require(try week(0, replanned).sessions.first { $0.id == long.id })
        #expect(session.dayOffset == long.dayOffset - 1)
        #expect(session.movedFrom == long.dayOffset)
    }

    /// RC-4 and EV-1: the unused buffer weeks sit right before the specific phase and hold the week.
    @Test func bufferWeeksHold() throws {
        let goal = GoalChoice(flavor: .event, distance: .tenK, eventDate: raceDay)
        let state = CoachFixtures.follow(CoachFixtures.start(CoachFixtures.regularIntake(goal)), days: 7 * 25).state
        let event = try #require(state.event)
        #expect(event.bufferWeeks == 2)
        func spare(_ plan: PlannedWeek) -> Bool { plan.notes.contains { $0.text.contains("spare week") } }
        #expect(try spare(week(22, state)))
        #expect(try week(22, state).kind == .hold)
        #expect(try (2 ... 21).allSatisfy { try !spare(week($0, state)) })
    }

    /// EV-10 with a time goal: the test replaces the Q in the step-back closest to week 8 after calibration,
    /// then about every 8 weeks.
    @Test func eventTestsOnTheirWeeks() throws {
        let goal = GoalChoice(flavor: .event, distance: .tenK, targetSeconds: 55 * 60, eventDate: raceDay)
        let state = CoachFixtures.follow(CoachFixtures.start(CoachFixtures.regularIntake(goal)), days: 7 * 18).state
        let tests = state.weeks.filter { $0.plan.sessions.contains { $0.kind == .test } }.map(\.plan.index)
        #expect(tests == [10, 16])
        let first = try week(10, state)
        #expect(first.kind == .stepBack)
        let test = try #require(first.sessions.first { $0.kind == .test })
        #expect(test.appTest == AppTest(goal: .time(seconds: 720), controlled: false))
        #expect(first.qualitySessions.allSatisfy { $0.kind == .test })
    }

    /// BD-5c: the first benchmark right after calibration, then every 4-6 weeks.
    @Test func benchmarkCadence() {
        let state = CoachFixtures.follow(CoachFixtures.start(CoachFixtures.regularIntake()), days: 7 * 13).state
        let benchmarks = state.weeks.filter { $0.plan.sessions.contains { $0.isBenchmark } }.map(\.plan.index)
        #expect(benchmarks == [2, 7, 12])
        let run = state.weeks.flatMap(\.plan.sessions).first { $0.isBenchmark }
        #expect(run?.kind == .easy)
        #expect(run?.notes.contains { $0.hasPrefix("Benchmark run") } == true)
    }

    /// HL-14 leaves room for the Q, so a 10K runner on 3 runs a week reaches the 10 km long run, and the Q then
    /// steps one rung at a time in weeks that hold volume (HL-3, HL-13).
    @Test func qualityStepsOnceTheWeekHolds() throws {
        let goal = GoalChoice(flavor: .event, distance: .tenK, eventDate: raceDay)
        let state = CoachFixtures.follow(CoachFixtures.start(CoachFixtures.regularIntake(goal)), days: 7 * 16).state
        let longest = state.weeks.compactMap { $0.plan.longRun?.meters }.max() ?? 0
        #expect(longest >= 9_999)

        var lastStep: Int?
        var lastVolume = 0.0
        var steps: [Int] = []
        for record in state.weeks.sorted(by: { $0.plan.index < $1.plan.index }) {
            let plan = record.plan
            guard let dose = plan.qualitySessions.first?.dose else { continue }
            if let previous = lastStep, dose.step > previous {
                #expect(dose.step == previous + 1)
                #expect(plan.plannedVolume <= lastVolume * 1.0001)
                steps.append(plan.index)
            }
            lastStep = dose.step
            lastVolume = plan.plannedVolume
        }
        #expect(lastStep == 4)
        #expect(!steps.isEmpty)
    }

    /// RC-4: an event plan whose first week has under 3 days left starts the week after.
    @Test func eventStartsNextWeekWhenFewDaysAreLeft() throws {
        let intake = CoachFixtures.regularIntake(GoalChoice(flavor: .event, distance: .tenK, eventDate: raceDay))
        let saturday = CoachEngine.startPlan(intake: intake, goal: intake.goal, level: .steady, runs: [], now: CoachFixtures.day(5), calendar: calendar).state
        #expect(saturday.startDate == CoachFixtures.day(7, hour: 0))
        let thursday = CoachEngine.startPlan(intake: intake, goal: intake.goal, level: .steady, runs: [], now: CoachFixtures.day(3), calendar: calendar).state
        #expect(thursday.startDate == CoachFixtures.day(0, hour: 0))
        #expect(try week(0, thursday).sessions.contains { $0.kind.isRun })
    }
}
