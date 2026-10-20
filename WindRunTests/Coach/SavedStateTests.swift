//
//  SavedStateTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// The app stores the coach's whole state as JSON after every call, so every state the engine leaves must encode
/// (JSONEncoder refuses NaN and infinity) and decode back to itself.
@MainActor
struct SavedStateTests {
    let calendar = CoachFixtures.calendar

    func expectRoundTrip(_ state: CoachState, _ label: String) throws {
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(CoachState.self, from: data)
        #expect(decoded == state, "\(label)")
    }

    /// A 10K plan followed through race day and its recovery, then "Keep this distance".
    @Test func anEventPlanAndWhatComesAfter() throws {
        let goal = GoalChoice(flavor: .event, distance: .tenK, targetSeconds: 55 * 60, eventDate: CoachFixtures.day(55))
        let raced = CoachFixtures.follow(CoachFixtures.start(CoachFixtures.regularIntake(goal)), days: 7 * 10)
        #expect(raced.state.weeks.contains { $0.plan.kind == .raceRecovery })
        try expectRoundTrip(raced.state, "after the race")
        let now = CoachFixtures.day(7 * 10, hour: 7)
        let (kept, _) = CoachEngine.answer(.nextGoal(.maintain), state: raced.state, runs: raced.runs, now: now, calendar: calendar)
        let maintained = CoachFixtures.follow(kept.state, runs: raced.runs, days: 14, from: 7 * 10)
        try expectRoundTrip(maintained.state, "keeping the distance")
    }

    /// The sick week to the end of its ramp, a Severe injury's return and the run-walk ladder.
    @Test func illnessInjuryAndTheLadder() throws {
        let (sick, _) = IllnessTests().sickWeek(until: .backToPlan)
        try expectRoundTrip(sick.state, "the sick week")

        let plan = InjuryTests().runningPlan()
        let severe = CoachEngine.reportInjury(level: .severe, area: .knee, origin: .planScreen, runID: nil, state: plan.state, runs: plan.runs, now: CoachFixtures.day(29, hour: 9), calendar: calendar)
        try expectRoundTrip(severe.state, "a Severe pause")
        let ready = CoachEngine.resume(state: severe.state, runs: plan.runs, now: CoachFixtures.day(43, hour: 9), calendar: calendar)
        let returning = CoachFixtures.follow(ready.state, runs: plan.runs, days: 21, from: 43)
        #expect(returning.state.weeks.contains { $0.plan.kind == .injuryReturn })
        try expectRoundTrip(returning.state, "the return")

        let ladder = CoachFixtures.followLadder(CoachFixtures.start(CoachFixtures.danaIntake()), days: 7 * 6)
        #expect(ladder.state.ladder?.history.isEmpty == false)
        try expectRoundTrip(ladder.state, "the ladder")
    }
}
