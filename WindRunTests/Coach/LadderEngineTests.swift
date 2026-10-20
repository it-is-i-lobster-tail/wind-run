//
//  LadderEngineTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// The walk stage and the ladder through the engine's own weeks: the layout, HL-2 in running minutes and AD-18's
/// restart questions (BD-2a, AD-18). Needs the engine hooks that hand ladder weeks to `LadderCoach`.
@MainActor
struct LadderEngineTests {
    let calendar = CoachFixtures.calendar

    /// The longest non-stop running a week's sessions plan.
    func plannedSegment(_ sessions: [PlannedSession]) -> Double {
        let segments = sessions.flatMap(\.blocks).flatMap(\.steps).compactMap { step -> Double? in
            guard step.kind == .work, !step.walk, case .time(let seconds) = step.goal else { return nil }
            return seconds
        }
        return segments.max() ?? sessions.map { $0.target.amount(in: .time) }.max() ?? 0
    }

    /// Dana's worked example with every run following the engine's own session (BD-2a, BD-2b, TI-6).
    @Test func danaFollowsTheEnginesSessions() throws {
        var state = CoachFixtures.start(CoachFixtures.danaIntake())
        var runs: [LoggedRun] = []
        for offset in 0 ..< 7 * 13 + 1 {
            let morning = CoachFixtures.day(offset, from: state.startDate)
            state = CoachEngine.refresh(state: state, runs: runs, now: morning, calendar: calendar).state
            let weekIndex = state.weekIndex(on: morning, calendar: calendar)
            let weekDay = (calendar.dateComponents([.day], from: state.startDate, to: morning).day ?? 0) % 7
            for session in CoachEngine.todaysSessions(state, now: morning, calendar: calendar) where session.kind.isRun && session.status.isPlanned {
                let rpe = (weekIndex == 4 && weekDay == 3) ? 6 : ((weekIndex == 12 && weekDay == 1) ? 5 : 3)
                let run = CoachFixtures.ladderRun(for: session, sessionID: session.id, on: morning, rpe: rpe)
                runs.append(run)
                state = CoachEngine.logRun(run, state: state, runs: runs, now: morning.addingTimeInterval(run.movingSeconds + 3_600), calendar: calendar).0.state
            }
            if weekDay == 6 {
                let evening = CoachFixtures.day(offset, hour: 20, from: state.startDate)
                let checkIn = WeeklyCheckIn(answeredAt: evening, week: .aboutRight, legs: .same, energy: .same, lifeStress: .same, motivation: .same, ill: false)
                state = CoachEngine.submitWeeklyCheckIn(checkIn, week: weekIndex, state: state, runs: runs, now: evening, calendar: calendar).state
            }
        }
        let steps: [Double] = [1, 2, 3, 4.5, 6, 6, 8, 10, 12, 15, 20, 25, 30]
        let running: [Double] = [24, 33, 36, 43.5, 51, 58.5, 66, 66, 78, 85.5, 85.5, 85.5, 90]
        for index in steps.indices {
            let week = try #require(state.weeks.first { $0.plan.index == index }?.plan)
            #expect(week.kind == .ladder, "week \(index + 1) is \(week.kind)")
            let planned = week.sessions.filter(\.kind.isRun)
            #expect(planned.count == 3, "week \(index + 1) plans \(planned.count) runs")
            #expect(plannedSegment(planned) == steps[index] * 60, "week \(index + 1) plans \(plannedSegment(planned)) s non-stop")
            #expect(abs(week.plannedVolume - running[index] * 60) < 0.5, "week \(index + 1) plans \(week.plannedVolume / 60) min")
            let sum = planned.reduce(0) { $0 + LadderCoach.plannedRunning($1) }
            #expect(abs(sum - running[index] * 60) < 0.5, "week \(index + 1) holds \(sum / 60) min of running")
        }
        // The weekly review says what the step rule decided (AD-18).
        #expect(state.weeks.first { $0.plan.index == 0 }?.review?.note.text == "Good week. Next week: 2 minutes of running at a time.")
        #expect(state.weeks.first { $0.plan.index == 4 }?.review?.note.text == "Same step next week, because one session felt hard. Nothing to make up.")
        let ladder = try #require(state.ladder)
        #expect(ladder.form == .done)
        #expect(ladder.stepsTaken == 11)
        #expect(state.v0 == 5_400)
        let next = try #require(state.weeks.first { $0.plan.index == 13 }?.plan)
        #expect(next.kind == .loading)
        #expect(next.cycleWeek == .newLongest)
    }

    /// AD-18: back after more than 28 days, the runner picks where to restart and the week is planned there.
    @Test func restartWhere() throws {
        let simulation = CoachFixtures.followLadder(CoachFixtures.start(CoachFixtures.danaIntake()), days: 28)
        let runs = simulation.runs
        let back = CoachFixtures.day(28 + 35, from: simulation.state.startDate)
        let state = CoachEngine.refresh(state: simulation.state, runs: runs, now: back, calendar: calendar).state
        #expect(CoachEngine.pendingQuestions(state, runs: runs, now: back, calendar: calendar).contains(.ladderRestartWhere))
        let options = LadderCoach.restartOptions(state)
        let prompt = CoachEngine.prompt(for: .ladderRestartWhere, state: state, calendar: calendar)
        #expect(prompt.choices.map(\.label) == ["1 min", "2 min", "3 min", "4.5 min", "6 min"])
        #expect(options.count == prompt.choices.count)

        let pick = try #require(options.first)
        let update = CoachEngine.answer(.ladderRestartAt(pick), state: state, runs: runs, now: back, calendar: calendar).0
        #expect(update.state.ladder?.position == pick)
        let index = update.state.weekIndex(on: back, calendar: calendar)
        let week = try #require(update.state.weeks.first { $0.plan.index == index }?.plan)
        #expect(plannedSegment(week.sessions) == pick.step.runSeconds)
        #expect(!CoachEngine.pendingQuestions(update.state, runs: runs, now: back, calendar: calendar).contains(.ladderRestartWhere))
    }

    /// AD-18: idle 2 weeks: "Ready to go again?" Declining keeps the step; accepting applies the gap row.
    @Test func idleRestart() throws {
        let simulation = CoachFixtures.followLadder(CoachFixtures.start(CoachFixtures.danaIntake()), days: 28)
        let runs = simulation.runs
        let idle = CoachFixtures.day(27 + 15, from: simulation.state.startDate)
        let state = CoachEngine.refresh(state: simulation.state, runs: runs, now: idle, calendar: calendar).state
        #expect(CoachEngine.pendingQuestions(state, runs: runs, now: idle, calendar: calendar).contains(.ladderIdleRestart))

        let declined = CoachEngine.answer(.ladderEasierRestart(false), state: state, runs: runs, now: idle, calendar: calendar).0
        #expect(declined.state.ladder?.stepIndex == 8)
        #expect(!CoachEngine.pendingQuestions(declined.state, runs: runs, now: idle, calendar: calendar).contains(.ladderIdleRestart))

        let accepted = CoachEngine.answer(.ladderEasierRestart(true), state: state, runs: runs, now: idle, calendar: calendar).0
        #expect(accepted.state.ladder?.stepIndex == 6)
        #expect(!CoachEngine.pendingQuestions(accepted.state, runs: runs, now: idle, calendar: calendar).contains(.ladderIdleRestart))
    }
}
