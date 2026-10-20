//
//  MatchingTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// AD-8: a run matches a planned run on the same day or one day either side, within ±25% of its duration.
@MainActor
struct MatchingTests {
    let calendar = CoachFixtures.calendar

    func plan() -> CoachState {
        CoachFixtures.start(CoachFixtures.regularIntake())
    }

    @Test func runMatchesThePlannedRun() throws {
        let state = plan()
        let tuesday = try #require(state.weeks[0].plan.sessions.first { $0.dayOffset == 1 })
        let run = LoggedRun(start: CoachFixtures.day(1), movingSeconds: tuesday.target.seconds * 1.2, meters: tuesday.target.meters * 1.2)
        #expect(RunReviewer.match(run, state: state, calendar: calendar) == .planned(sessionID: tuesday.id))
    }

    /// The owner's example: with Tuesday's run done, a Wednesday run as long as Thursday's is Thursday's run a day early.
    @Test func aRunADayEarlyStillMatches() throws {
        var state = plan()
        let tuesday = try #require(state.weeks[0].plan.sessions.first { $0.dayOffset == 1 })
        let first = CoachFixtures.run(for: tuesday, on: CoachFixtures.day(1), pace: 378)
        state = CoachEngine.logRun(first, state: state, runs: [first], now: CoachFixtures.day(1, hour: 9), calendar: calendar).0.state
        let thursday = try #require(state.weeks[0].plan.sessions.first { $0.dayOffset == 3 })
        let run = LoggedRun(start: CoachFixtures.day(2), movingSeconds: thursday.target.seconds, meters: thursday.target.meters)
        #expect(RunReviewer.match(run, state: state, calendar: calendar) == .planned(sessionID: thursday.id))
    }

    /// The owner's example: a 4 km run with a friend is more than 25% shorter than Thursday's run, so it is extra.
    @Test func muchShorterRunIsExtra() throws {
        let state = plan()
        let thursday = try #require(state.weeks[0].plan.sessions.first { $0.dayOffset == 3 })
        let run = LoggedRun(start: CoachFixtures.day(2), movingSeconds: thursday.target.seconds * 0.6, meters: thursday.target.meters * 0.6)
        #expect(RunReviewer.match(run, state: state, calendar: calendar) == .extra)
    }

    @Test func aRunStartedFromThePlanMatchesIt() throws {
        let state = plan()
        let sunday = try #require(state.weeks[0].plan.sessions.first { $0.kind == .long })
        let run = LoggedRun(start: CoachFixtures.day(5), movingSeconds: 600, meters: 2_000, plannedSessionID: sunday.id)
        #expect(RunReviewer.match(run, state: state, calendar: calendar) == .planned(sessionID: sunday.id))
    }

    @Test func aDeletedRunUnmatchesItsSession() throws {
        var state = plan()
        let tuesday = try #require(state.weeks[0].plan.sessions.first { $0.dayOffset == 1 })
        let run = CoachFixtures.run(for: tuesday, on: CoachFixtures.day(1), pace: 378)
        state = CoachEngine.logRun(run, state: state, runs: [run], now: CoachFixtures.day(1, hour: 9), calendar: calendar).0.state
        #expect(state.weeks[0].plan.sessions.first { $0.id == tuesday.id }?.status == .done(runID: run.id))
        state = CoachEngine.refresh(state: state, runs: [], now: CoachFixtures.day(1, hour: 10), calendar: calendar).state
        #expect(state.weeks[0].plan.sessions.first { $0.id == tuesday.id }?.status == .planned)
    }
}
