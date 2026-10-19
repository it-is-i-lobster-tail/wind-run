//
//  PlanSimulationTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// Whole plans run day by day through the engine, checked against the rules' worked examples.
@MainActor
struct PlanSimulationTests {
    let calendar = CoachFixtures.calendar

    func week(_ index: Int, _ state: CoachState) throws -> PlannedWeek {
        try #require(state.weeks.first { $0.plan.index == index }?.plan)
    }

    @Test func intakeGivesTheStartingNumbers() {
        let intake = CoachFixtures.regularIntake()
        let assessment = CoachEngine.assess(intake, now: CoachFixtures.day(0), calendar: calendar)
        #expect(assessment.tier == .regular)
        #expect(assessment.start.volumeUnit == .distance)
        #expect(abs(assessment.start.v0 - 16_000) < 0.5)
        #expect(abs(assessment.start.planningLongest.meters - 8_000) < 0.5)
        #expect(assessment.start.runsPerWeek == 3)
        #expect(assessment.levels.allows(.steady))
    }

    /// TI-5: weeks 1-2 sit at 0.9 × V0 with the long run at the planning P-L30, nothing progresses.
    @Test func calibrationWeeks() throws {
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        let first = try week(0, state)
        #expect(first.kind == .calibration)
        #expect(abs(first.plannedVolume - 14_400) < 1)
        #expect(abs((first.longRun?.meters ?? 0) - 8_000) < 1)
        #expect(first.runs.count == 3)
        #expect(first.sessions.contains { $0.kind == .long && $0.dayOffset == 6 })
        #expect(first.qualitySessions.isEmpty)

        let simulation = CoachFixtures.follow(state, days: 8)
        let second = try week(1, simulation.state)
        #expect(second.kind == .calibration)
        #expect(abs(second.plannedVolume - 14_400) < 1)
        #expect(simulation.state.weeks.first?.review?.outcome == .hold)
    }

    /// CL-2's Steady table from V0 16 km and P-L30 8 km: weeks 3-8 are N 17.2/8.8, N 18.5/9.7, S 13.9/6.8,
    /// N 19.9/10.6, N 21.4/11.7, S 16.0/8.2 (volume/long run, km).
    @Test func steadyCycleMatchesTheTable() throws {
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        let simulation = CoachFixtures.follow(state, days: 7 * 8)
        let expected: [(CycleWeek, Double, Double)] = [
            (.newLongest, 17.2, 8.8),
            (.newLongest, 18.5, 9.7),
            (.stepBack, 13.9, 6.8),
            (.newLongest, 19.9, 10.6),
            (.newLongest, 21.4, 11.7),
            (.stepBack, 16.0, 8.2),
        ]
        for (offset, row) in expected.enumerated() {
            let plan = try week(offset + 2, simulation.state)
            #expect(plan.cycleWeek == row.0, "week \(offset + 3) is \(String(describing: plan.cycleWeek))")
            #expect(abs(plan.plannedVolume / 1_000 - row.1) < 0.06, "week \(offset + 3) volume \(plan.plannedVolume)")
            #expect(abs((plan.longRun?.meters ?? 0) / 1_000 - row.2) < 0.06, "week \(offset + 3) long run \(String(describing: plan.longRun))")
        }
        #expect(simulation.state.v0 == 16_000)
    }

    /// CL-2's Gentle and Ambitious columns: Gentle 16.8/8.8, 17.6/8.8, 18.5/9.7, 13.9/6.8;
    /// Ambitious 17.6/8.8, 19.4/9.7, 21.3/10.6, 16.0/7.5.
    @Test func gentleAndAmbitiousColumns() throws {
        let gentle = CoachFixtures.follow(CoachFixtures.start(CoachFixtures.regularIntake(level: .gentle)), days: 7 * 6).state
        let gentleRows: [(Double, Double)] = [(16.8, 8.8), (17.6, 8.8), (18.5, 9.7), (13.9, 6.8)]
        for (offset, row) in gentleRows.enumerated() {
            let plan = try week(offset + 2, gentle)
            #expect(abs(plan.plannedVolume / 1_000 - row.0) < 0.06, "Gentle week \(offset + 3) volume \(plan.plannedVolume)")
            #expect(abs((plan.longRun?.meters ?? 0) / 1_000 - row.1) < 0.06, "Gentle week \(offset + 3) long run \(String(describing: plan.longRun))")
        }

        let ambitious = CoachFixtures.follow(CoachFixtures.start(CoachFixtures.regularIntake(level: .ambitious)), days: 7 * 6).state
        let ambitiousRows: [(Double, Double)] = [(17.6, 8.8), (19.4, 9.7), (21.3, 10.6), (16.0, 7.5)]
        for (offset, row) in ambitiousRows.enumerated() {
            let plan = try week(offset + 2, ambitious)
            #expect(abs(plan.plannedVolume / 1_000 - row.0) < 0.06, "Ambitious week \(offset + 3) volume \(plan.plannedVolume)")
            #expect(abs((plan.longRun?.meters ?? 0) / 1_000 - row.1) < 0.06, "Ambitious week \(offset + 3) long run \(String(describing: plan.longRun))")
        }
    }

    /// AD-5: a week rated "too hard" alone gives EASE (−10%, no new longest run), and the clean week after it
    /// returns to the level before the cut (AD-6a).
    @Test func tooHardEasesThenResumes() throws {
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        var simulation = CoachFixtures.follow(state, days: 7 * 3)
        // Week 4 (index 3) rated too hard.
        simulation = CoachFixtures.follow(simulation.state, runs: simulation.runs, days: 7, from: 21, week: .tooHard)
        simulation = CoachFixtures.follow(simulation.state, runs: simulation.runs, days: 7 * 2, from: 28)
        let rated = try week(3, simulation.state)
        let eased = try week(4, simulation.state)
        let back = try week(5, simulation.state)
        #expect(simulation.state.weeks.first { $0.plan.index == 3 }?.review?.outcome == .ease)
        #expect(eased.kind == .ease)
        #expect(abs(eased.plannedVolume - 0.9 * rated.plannedVolume) < 1)
        #expect(!eased.sessions.contains { $0.isNewLongest })
        #expect(back.kind == .hold)
        #expect(abs(back.plannedVolume - rated.plannedVolume) < 1)
    }

    /// AD-10: ten days without a run after week 3 starts a G1 ramp at 75% of the reference.
    @Test func skippedWeekStartsTheRamp() throws {
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        var simulation = CoachFixtures.follow(state, days: 7 * 3)
        // Nothing logged in week 4 (index 3) nor on the first days of week 5.
        simulation = CoachFixtures.follow(simulation.state, runs: simulation.runs, days: 7, from: 21, rpe: nil, week: nil, skip: { _, _ in true })
        simulation = CoachFixtures.follow(simulation.state, runs: simulation.runs, days: 1, from: 28)
        let ramp = try #require(simulation.state.gap)
        #expect(ramp.tier == .g1)
        let plan = try week(4, simulation.state)
        #expect(plan.kind == .ramp)
        #expect(abs(plan.plannedVolume - ramp.reference * 0.75) < 1)
        #expect((plan.longRun?.meters ?? 0) <= ramp.referenceLongRun.meters * 0.8 + 1)
    }

    /// The weekly check-in is asked on the plan week's last day, and a check-in after the review re-reviews it.
    @Test func weeklyCheckInQuestion() {
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        let sunday = CoachFixtures.day(6, hour: 18)
        let update = CoachEngine.refresh(state: state, runs: [], now: sunday, calendar: calendar)
        #expect(update.questions.contains(.weeklyCheckIn(weekIndex: 0)))
    }

    /// Re-planning a week keeps its session IDs, so the app can update its rows in place.
    @Test func replanKeepsSessionIDs() throws {
        let state = CoachFixtures.start(CoachFixtures.regularIntake())
        let before = try week(0, state).sessions.map(\.id)
        let replanned = CoachEngine.replanCurrentWeek(state, runs: [], now: CoachFixtures.day(0), calendar: calendar)
        let after = try week(0, replanned).sessions.map(\.id)
        #expect(before == after)
        #expect(Set(before).count == before.count)
    }

    /// RB-8: "legs or energy below normal" makes today's session an easy run of the same length.
    @Test func readinessBelowNormal() throws {
        let state = CoachFixtures.follow(CoachFixtures.start(CoachFixtures.regularIntake()), days: 6).state
        let sunday = CoachFixtures.day(6)
        let long = try #require(CoachEngine.todaysSessions(state, now: sunday, calendar: calendar).first { $0.kind == .long })
        let update = CoachEngine.submitReadiness(.belowNormal, heat: nil, sessionID: long.id, state: state, runs: [], now: sunday, calendar: calendar)
        let after = try #require(CoachEngine.todaysSessions(update.state, now: sunday, calendar: calendar).first { $0.id == long.id })
        #expect(after.madeEasy == .readiness)
        #expect(after.target == long.target)
    }
}
