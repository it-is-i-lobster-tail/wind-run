//
//  EventEngineTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// Race reviews, tests and goals through the engine's own calls: a planned test's result (PZ-3), the questions a
/// finished plan still asks (EV-9), recovery by the distance run, and keeping a distance (BD-1g).
@MainActor
struct EventEngineTests {
    let calendar = CoachFixtures.calendar
    /// Sunday 1 March 2026.
    let raceDay = 55

    func tenK(target: Double? = nil) -> CoachState {
        CoachFixtures.start(CoachFixtures.regularIntake(GoalChoice(flavor: .event, distance: .tenK, targetSeconds: target, eventDate: CoachFixtures.day(raceDay))))
    }

    /// PZ-3: the work step of a planned 12-minute test becomes the anchor; a run without its steps sets nothing,
    /// since the warm-up and cool-down can't be told apart from the test.
    @Test func aPlannedTestsWorkStepBecomesTheAnchor() throws {
        var state = tenK(target: 55 * 60)
        let position = try #require(state.weeks.indices.last)
        let context = WeekPlanner.makeContext(week: state.weeks[position].plan.index, state: state, runs: [], now: CoachFixtures.day(0), calendar: calendar)
        let test = Scheduler.testSession(controlled: false, day: 6, context: context)
        state.weeks[position].plan.sessions.removeAll { $0.dayOffset == 6 }
        state.weeks[position].plan.sessions.append(test)
        let day = state.date(of: test, in: state.weeks[position].plan, calendar: calendar)
        let steps = [
            LoggedStep(isWork: false, meters: 2_000, seconds: 900),
            LoggedStep(isWork: true, meters: 2_600, seconds: 720),
            LoggedStep(isWork: false, meters: 1_300, seconds: 600),
        ]
        let run = LoggedRun(start: day.addingTimeInterval(9 * 3_600), movingSeconds: 2_220, meters: 5_900, plannedSessionID: test.id, steps: steps)
        let (update, review) = CoachEngine.logRun(run, state: state, runs: [run], now: run.end.addingTimeInterval(600), calendar: calendar)
        #expect(review.match == .planned(sessionID: test.id))
        let anchor = try #require(update.state.paces.anchor)
        #expect(anchor.meters == 2_600)
        #expect(anchor.seconds == 720)
        #expect(anchor.source == .appTest)
        #expect(update.notes.contains { $0.topic == .pace && $0.text.hasPrefix("Your test equals") })

        var plain = run
        plain.steps = nil
        let (unrecorded, _) = CoachEngine.logRun(plain, state: state, runs: [plain], now: plain.end.addingTimeInterval(600), calendar: calendar)
        #expect(unrecorded.state.paces.anchor == state.paces.anchor)
    }

    /// EV-9: a finished plan plans nothing more, but still asks "What next?".
    @Test func aFinishedPlanAsksWhatNext() {
        var state = CoachFixtures.start(CoachFixtures.regularIntake())
        state.status = .complete(on: CoachFixtures.day(10))
        let update = CoachEngine.refresh(state: state, runs: [], now: CoachFixtures.day(12), calendar: calendar)
        #expect(update.questions == [.nextGoal])
        #expect(update.state.weeks == state.weeks)
    }

    /// EV-9: a race not finished recovers by the distance run: 8 km of a marathon takes the 10K row, with no
    /// 30-minute cap in its first week.
    @Test func aRaceNotFinishedRecoversByTheDistanceRun() throws {
        var state = tenK()
        state.goal.distance = .marathon
        let event = try #require(state.event)
        let week = state.weekIndex(on: CoachFixtures.day(raceDay), calendar: calendar) + 1
        func targets(_ state: CoachState) -> WeekTargets {
            let context = WeekPlanner.makeContext(week: week, state: state, runs: [], now: CoachFixtures.day(raceDay + 1), calendar: calendar)
            return WeekPlanner.raceRecoveryTargets(context, event: event)
        }
        let finished = targets(state)
        #expect(finished.sessionCap?.seconds == 1_800.0)
        state.eventReview.outcome = .didNotFinish
        state.eventReview.distanceRun = 8_000
        let stopped = targets(state)
        #expect(stopped.sessionCap == nil)
        #expect(abs(stopped.volume - finished.volume * 0.6 / 0.3) < 1)
    }

    /// HL-19 (EF-5): a fever or below-the-neck illness within 48 h of race day takes the race out of the plan and
    /// says why; one that cleared earlier leaves it in.
    @Test func aFeverJustBeforeTheRaceMeansDontStart() throws {
        let state = tenK()
        let raceWeek = state.weekIndex(on: CoachFixtures.day(raceDay), calendar: calendar)
        let monday = state.weekStart(raceWeek, calendar: calendar)
        func planned(symptomFreeFrom day: Int) -> PlannedWeek? {
            var sick = state
            var fever = IllnessEpisode(reportedAt: CoachFixtures.day(day - 3), kind: .feverOrBelowNeck)
            fever.stage = .over
            fever.symptomFreeSince = CoachFixtures.day(day)
            fever.endedAt = CoachFixtures.day(day)
            sick.illnesses = [fever]
            return WeekPlanner.planWeek(raceWeek, state: sick, runs: [], now: monday, calendar: calendar).weeks.first { $0.plan.index == raceWeek }?.plan
        }
        let blocked = try #require(planned(symptomFreeFrom: raceDay - 1))
        #expect(!blocked.sessions.contains { $0.kind == .race })
        #expect(blocked.notes.contains { $0.text.hasPrefix("With a fever or an illness below the neck this close to race day, please don't start.") })
        let clear = try #require(planned(symptomFreeFrom: raceDay - 3))
        #expect(clear.sessions.contains { $0.kind == .race })
    }

    /// BD-1g: "Keep this distance" holds the weeks where they are: no week above the last building week, no new
    /// longest run, and the lighter weeks still come.
    @Test func keepingTheDistanceAddsNoMore() throws {
        let start = CoachFixtures.start(CoachFixtures.regularIntake())
        let before = CoachFixtures.follow(start, days: 7 * 5)
        let now = CoachFixtures.day(7 * 5, hour: 7, from: start.startDate)
        let (answered, _) = CoachEngine.answer(.nextGoal(.maintain), state: before.state, runs: before.runs, now: now, calendar: calendar)
        #expect(answered.state.goal.maintain)
        let after = CoachFixtures.follow(answered.state, runs: before.runs, days: 7 * 7, from: 7 * 5)
        let built = before.state.weeks.filter { $0.plan.kind == .loading || $0.plan.kind == .hold }
        let top = try #require(built.map(\.plan.plannedVolume).max())
        let kept = after.state.weeks.filter { $0.plan.index >= 6 }.map(\.plan)
        #expect(kept.count >= 6)
        #expect(kept.contains { $0.kind == .maintain })
        #expect(kept.contains { $0.kind == .stepBack })
        for week in kept {
            #expect(week.plannedVolume <= top * 1.0001, "week \(week.index)")
            #expect(week.sessions.allSatisfy { !$0.isNewLongest }, "week \(week.index)")
        }
    }
}
