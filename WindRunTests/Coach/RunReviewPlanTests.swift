//
//  RunReviewPlanTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// What run reviews change in the weeks after: FB-4g's next session of a type, FB-4a's held long-run step, FB-4a and
/// FB-4f's tempo split into reps, FB-4d's longer recoveries, FB-4c's walk breaks and AD-6c's easy week after a
/// benchmark drop.
@MainActor
struct RunReviewPlanTests {
    let calendar = CoachFixtures.calendar

    /// A plan whose threshold dose is the ladder's third rung, with a threshold session judged `outcome` on day 3.
    func judged(_ outcome: SessionOutcome, fewerReps: Bool = false) -> CoachState {
        var state = CoachFixtures.start(CoachFixtures.regularIntake())
        state.quality.setDose(QualityPlanner.dose(.threshold, step: 2, age: state.assessment.age, runsPerWeek: 3))
        state.runReview.judgements = [SessionJudgement(
            runID: UUID(),
            sessionID: UUID(),
            date: CoachFixtures.day(3),
            weekIndex: 0,
            type: .threshold,
            outcome: outcome,
            downTrigger: fewerReps,
            fewerReps: fewerReps,
            easierThanTarget: false,
            slow: false,
            faded: false,
            conditions: false
        )]
        return state
    }

    func context(_ state: CoachState, week: Int = 1) -> PlanningContext {
        WeekPlanner.makeContext(week: week, state: state, runs: [], now: CoachFixtures.day(7 * week), calendar: calendar)
    }

    /// Week 1's targets with the threshold dose one step up, as a hold week plans it, then shaped by run reviews.
    func shaped(_ state: CoachState) throws -> QualityDose {
        let current = try #require(state.quality.dose(for: .threshold))
        var targets = WeekTargets(kind: .hold, volume: 18_000, runs: 3, quality: [QualityPlanner.stepped(current, age: state.assessment.age, runsPerWeek: 3)])
        RunReviewer.shape(&targets, context: context(state))
        return try #require(targets.quality.first)
    }

    // MARK: FB-4g

    @Test func afterFailedTheNextSessionIsAQuarterLess() throws {
        let state = judged(.failed)
        let current = try #require(state.quality.dose(for: .threshold))
        let next = try shaped(state)
        #expect(next.type == .threshold)
        #expect(next.workSeconds <= current.workSeconds * 0.75 + 0.5)
        #expect(next.step < current.step)
    }

    @Test func afterStruggledTheSameSessionComesAgain() throws {
        let state = judged(.struggled)
        #expect(try shaped(state) == state.quality.dose(for: .threshold))
        // PZ-7's down trigger with no pace target: a third fewer reps.
        let fewer = judged(.struggled, fewerReps: true)
        let current = try #require(fewer.quality.dose(for: .threshold))
        #expect(try shaped(fewer).workSeconds <= current.workSeconds * 2 / 3 + 0.5)
    }

    @Test func goodSessionsStepOn() throws {
        for outcome in [SessionOutcome.completed, .evenAndOnTarget] {
            #expect(try shaped(judged(outcome)).step == 3)
        }
    }

    /// The outcome is for the next session of the type only: one planned after it uses it up.
    @Test func theOutcomeIsUsedOnce() throws {
        var state = judged(.failed)
        let dose = QualityPlanner.dose(.threshold, step: 1, age: state.assessment.age, runsPerWeek: 3)
        state.weeks[0].plan.sessions.append(PlannedSession(dayOffset: 5, kind: .threshold, effort: .threshold, target: Load(meters: 8_000, seconds: 2_700), dose: dose))
        #expect(try shaped(state).step == 3)
    }

    // MARK: FB-4a, FB-4f, FB-4d, FB-4c

    @Test func aFadingTempoIsSplitIntoFiveMinuteReps() throws {
        var state = CoachFixtures.start(CoachFixtures.regularIntake())
        state.runReview.advice = [PacingAdvice(kind: .splitIntoReps, runID: UUID(), date: CoachFixtures.day(3), sessionKinds: [.threshold, .racePace])]
        let context = context(state)
        let tempo = QualityDose(type: .threshold, step: 5, reps: 1, repSeconds: 1_200, recoverySeconds: 0, continuous: true)
        var sessions = [Scheduler.qualitySession(tempo, day: 2, context: context, unit: context.unit)]
        _ = RunReviewer.finish(&sessions, context: context)
        let session = try #require(sessions.first)
        let dose = try #require(session.dose)
        #expect(dose.reps == 4)
        #expect(dose.repSeconds == 300)
        #expect(dose.recoverySeconds == 60)
        #expect(!dose.continuous)
        #expect(session.kind == .threshold)
        #expect(session.dayOffset == 2)
        #expect(session.blocks.contains { $0.repeats == 4 })
    }

    @Test func aTempoAlreadyInRepsRunsThreePercentEasier() throws {
        var state = CoachFixtures.start(CoachFixtures.regularIntake())
        state.paces.threshold = 300
        state.runReview.advice = [PacingAdvice(kind: .tempoAsReps, runID: UUID(), date: CoachFixtures.day(3), sessionKinds: [.threshold])]
        let context = context(state)
        let reps = QualityDose(type: .threshold, step: 2, reps: 4, repSeconds: 300, recoverySeconds: 60)
        let planned = Scheduler.qualitySession(reps, day: 2, context: context, unit: context.unit)
        var sessions = [planned]
        _ = RunReviewer.finish(&sessions, context: context)
        let before = try #require(planned.blocks.flatMap(\.steps).first { $0.kind == .work }?.pace)
        let after = try #require(sessions.first?.blocks.flatMap(\.steps).first { $0.kind == .work }?.pace)
        #expect(abs(after.fast - before.fast * 1.03) < 1e-6)
        #expect(sessions.first?.dose == reps)
    }

    @Test func repsStillDriftingGetLongerRecoveries() throws {
        var state = CoachFixtures.start(CoachFixtures.regularIntake())
        state.runReview.advice = [PacingAdvice(kind: .lengthenRecoveries, runID: UUID(), date: CoachFixtures.day(3), sessionKinds: [.intervals], qualityType: .vo2max)]
        let context = context(state)
        let reps = QualityDose(type: .vo2max, step: 1, reps: 4, repSeconds: 180, recoverySeconds: 120)
        var sessions = [Scheduler.qualitySession(reps, day: 2, context: context, unit: context.unit)]
        _ = RunReviewer.finish(&sessions, context: context)
        #expect(sessions.first?.dose?.recoverySeconds == 180)
        #expect(sessions.first?.dose?.reps == 4)
    }

    /// FB-4c: a yes to walk breaks gives the easy runs left a minute's walk after each easy kilometre.
    @Test func yesToWalkBreaksAddsThemToEasyRuns() throws {
        let start = CoachFixtures.start(CoachFixtures.regularIntake())
        let simulation = CoachFixtures.follow(start, days: 2)
        let now = CoachFixtures.day(2, hour: 12)
        let (update, _) = CoachEngine.answer(.runReview(.walkBreaks(true)), state: simulation.state, runs: simulation.runs, now: now, calendar: calendar)
        #expect(update.state.runReview.walkBreaks)
        let thursday = try #require(update.state.weeks[0].plan.sessions.first { $0.dayOffset == 3 })
        #expect(thursday.kind == .easy)
        #expect(thursday.blocks.flatMap(\.steps).contains { $0.walk && $0.goal == .time(seconds: 60) })
        // The long run keeps going without them.
        #expect(update.state.weeks[0].plan.sessions.first { $0.kind == .long }?.blocks.isEmpty == true)
    }

    // MARK: AD-6c

    /// A benchmark 12% slower at the same effort, after a tired morning, makes the next 7 days easy runs of 30 minutes
    /// at most: the rest of this week, and next week's first days.
    @Test func aBenchmarkDropEasesTheNextSevenDays() throws {
        // Easy runs of about 50 minutes, so the 30-minute cap shows.
        var intake = CoachFixtures.regularIntake()
        intake.lastFourWeeks = RecentRunning(runsPerWeek: 3, weeklyLow: .distance(meters: 30_000), weeklyHigh: .distance(meters: 33_000), longest: .distance(meters: 14_000))
        let start = CoachFixtures.start(intake)
        let simulation = CoachFixtures.follow(start, days: 8)
        var state = simulation.state
        var runs = simulation.runs
        let earlierIndex = try #require(state.weeks[0].plan.sessions.firstIndex { $0.dayOffset == 1 })
        state.weeks[0].plan.sessions[earlierIndex].benchmark = true
        guard case .done(let earlierID) = state.weeks[0].plan.sessions[earlierIndex].status else {
            Issue.record("Tuesday's run wasn't done")
            return
        }
        let earlier = try #require(runs.first { $0.id == earlierID })

        let week = try #require(state.weeks.firstIndex { $0.plan.index == 1 })
        let tuesday = try #require(state.weeks[week].plan.sessions.firstIndex { $0.dayOffset == 1 })
        state.weeks[week].plan.sessions[tuesday].benchmark = true
        state.morningChecks.append(MorningCheck(date: CoachFixtures.day(8, hour: 6), fatigue: 6, soreness: 4))
        let pace = earlier.movingSeconds / earlier.meters * 1_000 * 1.12
        let run = LoggedRun(
            start: CoachFixtures.day(8),
            movingSeconds: earlier.meters / 1_000 * pace,
            meters: earlier.meters,
            source: .gps,
            plannedSessionID: state.weeks[week].plan.sessions[tuesday].id,
            checkIn: RunCheckIn(answeredAt: CoachFixtures.day(8, hour: 9), rpe: earlier.rpe, talkTest: true, feel: .ok)
        )
        runs.append(run)
        let (update, _) = CoachEngine.logRun(run, state: state, runs: runs, now: CoachFixtures.day(8, hour: 10), calendar: calendar)
        state = update.state
        #expect(update.notes.contains(CoachNote(.plan, "Your check run was well off your usual at the same effort. Let's rest or run easy for a week.")))
        #expect(state.runReview.easyUntil == CoachFixtures.day(16, hour: 0))

        let rest = try #require(state.weeks.first { $0.plan.index == 1 }).plan.sessions.filter { $0.dayOffset > 1 && $0.kind.isRun }
        #expect(!rest.isEmpty)
        for session in rest {
            #expect(session.target.seconds <= RunReviewer.easyWeekRunSeconds + 1, "\(session.kind)")
            #expect(!session.isQuality && !session.isNewLongest && session.strides == 0)
        }
        #expect(rest.first { $0.kind == .long }?.madeEasy == .adaptation)

        // Next week: Tuesday is still inside the 7 days, Thursday and the long run aren't.
        let later = CoachFixtures.follow(state, runs: runs, days: 8, from: 9)
        let next = try #require(later.state.weeks.first { $0.plan.index == 2 }).plan
        let nextTuesday = try #require(next.sessions.first { $0.dayOffset == 1 })
        let nextThursday = try #require(next.sessions.first { $0.dayOffset == 3 })
        #expect(nextTuesday.target.seconds <= RunReviewer.easyWeekRunSeconds + 1)
        #expect(nextThursday.target.seconds > RunReviewer.easyWeekRunSeconds)
        #expect(next.sessions.first { $0.kind == .long }?.madeEasy == nil)
    }
}
