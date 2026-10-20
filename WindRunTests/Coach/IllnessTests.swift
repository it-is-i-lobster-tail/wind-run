//
//  IllnessTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// Illness and heat illness against the rules' examples: the sick week's return stages, the head cold, relapses,
/// the 2 easy runs after a heat illness and the race-day rule (AD-12, AD-16, HL-19).
@MainActor
struct IllnessTests {
    let calendar = CoachFixtures.calendar

    /// A runner 4 weeks into a 10K plan with runs on Tuesday, Thursday and Sunday, on the Monday of week 4.
    func runningPlan() -> CoachFixtures.Simulation {
        let simulation = CoachFixtures.follow(CoachFixtures.start(CoachFixtures.regularIntake(GoalChoice(flavor: .speedWork, distance: .tenK))), days: 28)
        let monday = CoachFixtures.day(28)
        return CoachFixtures.Simulation(state: CoachEngine.refresh(state: simulation.state, runs: simulation.runs, now: monday, calendar: calendar).state, runs: simulation.runs)
    }

    /// Saves a run that does today's first planned run exactly.
    func runToday(_ simulation: inout CoachFixtures.Simulation, at time: Date) -> LoggedRun? {
        guard let session = CoachEngine.todaysSessions(simulation.state, now: time, calendar: calendar).first(where: { $0.kind.isRun && $0.status.isPlanned }) else {
            return nil
        }
        let run = CoachFixtures.run(for: session, on: time, pace: simulation.state.paces.easyPace ?? 378, rpe: 2)
        simulation.runs.append(run)
        simulation.state = CoachEngine.logRun(run, state: simulation.state, runs: simulation.runs, now: time.addingTimeInterval(run.movingSeconds + 600), calendar: calendar).0.state
        return run
    }

    func week(_ simulation: CoachFixtures.Simulation, at time: Date) -> PlannedWeek? {
        CoachEngine.currentWeek(simulation.state, now: time, calendar: calendar)
    }

    /// The runs still to do this week.
    func plannedRuns(_ simulation: CoachFixtures.Simulation, at time: Date) -> [PlannedSession] {
        let today = (calendar.dateComponents([.day], from: simulation.state.startDate, to: time).day ?? 0) % 7
        return (week(simulation, at: time)?.runs ?? []).filter { $0.status.isPlanned && $0.dayOffset >= today }
    }

    /// The owner's sick week on the plan (AD-12): a fever on day 29 (a Tuesday), "Ready" on day 36, the first run that
    /// evening, "Still feeling normal" on day 37 and a second easy run on day 38, stopping once `stage` is reached.
    func sickWeek(until stage: IllnessStage) -> (simulation: CoachFixtures.Simulation, episodeID: UUID) {
        var simulation = runningPlan()
        let sick = CoachEngine.reportIllness(kind: .feverOrBelowNeck, state: simulation.state, runs: simulation.runs, now: CoachFixtures.day(29, hour: 8), calendar: calendar)
        let id = sick.state.illnesses[0].id
        simulation = CoachFixtures.follow(sick.state, runs: simulation.runs, days: 7, from: 29)
        if stage <= .rest { return (simulation, id) }
        let ready = CoachFixtures.day(36, hour: 8)
        simulation.state = CoachEngine.refresh(state: simulation.state, runs: simulation.runs, now: ready, calendar: calendar).state
        simulation.state = CoachEngine.answerIllness(.ready(true), episodeID: id, state: simulation.state, runs: simulation.runs, now: ready, calendar: calendar).state
        _ = runToday(&simulation, at: CoachFixtures.day(36, hour: 17))
        if stage <= .firstRun { return (simulation, id) }
        let check = CoachFixtures.day(37, hour: 8)
        simulation.state = CoachEngine.refresh(state: simulation.state, runs: simulation.runs, now: check, calendar: calendar).state
        simulation.state = CoachEngine.answerIllness(.stillNormal(true), episodeID: id, state: simulation.state, runs: simulation.runs, now: check, calendar: calendar).state
        if stage <= .easy { return (simulation, id) }
        simulation.state = CoachEngine.refresh(state: simulation.state, runs: simulation.runs, now: CoachFixtures.day(38, hour: 8), calendar: calendar).state
        _ = runToday(&simulation, at: CoachFixtures.day(38, hour: 17))
        return (simulation, id)
    }

    // MARK: The sick week (AD-12)

    /// AD-12's owner example: a fever pauses the plan; "Ready" after 2 normal days brings one easy 10-20 min run and
    /// the next-day check; then easy runs only; 4 symptom-free days and 2 easy runs start the G1 ramp, which brings
    /// no new longest run until 7 days after the first run; the episode ends with the ramp.
    @Test func sickWeekFollowsTheStages() {
        var simulation = runningPlan()
        let sickAt = CoachFixtures.day(29, hour: 8)
        let sick = CoachEngine.reportIllness(kind: .feverOrBelowNeck, state: simulation.state, runs: simulation.runs, now: sickAt, calendar: calendar)
        let id = sick.state.illnesses[0].id
        let pause = "No running for now, because you're ill. Your plan is paused, not lost. Tap 'Ready' when you want to start back. If it drags on or keeps coming back, it's worth seeing a doctor."
        #expect(sick.state.status == .paused(reason: .illness, since: sickAt))
        #expect(sick.notes.map(\.text).contains(pause))
        #expect(sick.questions.isEmpty)
        #expect(IllnessCoach.outcome(sick.state)! == (.pause, .illness))
        #expect(IllnessCoach.setsWayBack(sick.state))
        let paused = CoachEngine.currentWeek(sick.state, now: sickAt, calendar: calendar)!
        #expect(paused.kind == .paused)
        #expect(paused.runs.isEmpty)

        // Days 1-7: still ill or not yet back to normal for 2 days, so nothing runs and the next week stays paused.
        simulation = CoachFixtures.follow(sick.state, runs: simulation.runs, days: 7, from: 29)
        let ready = CoachFixtures.day(36, hour: 8)
        simulation.state = CoachEngine.refresh(state: simulation.state, runs: simulation.runs, now: ready, calendar: calendar).state
        #expect(week(simulation, at: ready)?.kind == .paused)
        #expect(simulation.state.weeks.first { $0.plan.index == 4 }?.review?.outcome == .pause)

        // Day 8: "Ready", but not yet 2 full days back to normal.
        let notYet = CoachEngine.answerIllness(.ready(false), episodeID: id, state: simulation.state, runs: simulation.runs, now: ready, calendar: calendar)
        #expect(notYet.notes.map(\.text).contains("No rush. Tap 'Ready' again once you've felt normal for 2 full days."))
        #expect(notYet.state.activeIllness?.stage == .rest)
        #expect(notYet.state.status.isPaused)

        // "Ready" with 2 normal days: stage 2, one easy run of half the usual 21-min easy run.
        let first = CoachEngine.answerIllness(.ready(true), episodeID: id, state: simulation.state, runs: simulation.runs, now: ready, calendar: calendar)
        simulation.state = first.state
        #expect(first.notes.map(\.text).contains("Glad you're feeling better. We'll start with an easy 10-20 minutes."))
        #expect(first.notes.map(\.text).contains("One easy run of 11 minutes, because you're getting over being ill."))
        #expect(simulation.state.status == .active)
        #expect(simulation.state.activeIllness?.stage == .firstRun)
        #expect(simulation.state.activeIllness?.symptomFreeSince == CoachFixtures.day(34, hour: 0))
        let firstRuns = plannedRuns(simulation, at: ready)
        #expect(firstRuns.count == 1)
        #expect(firstRuns.allSatisfy { (600 ... 1_200).contains($0.target.seconds.rounded()) && !$0.isQuality })

        // The first run, then nothing more until the next-day check.
        let firstRun = runToday(&simulation, at: CoachFixtures.day(36, hour: 17))!
        #expect(simulation.state.activeIllness?.firstRunAt == firstRun.start)
        #expect(plannedRuns(simulation, at: CoachFixtures.day(36, hour: 20)).isEmpty)
        #expect(week(simulation, at: CoachFixtures.day(36, hour: 20))!.notes.map(\.text).contains("No more running until tomorrow's check, because your first run back comes before load rises."))
        #expect(!CoachEngine.pendingQuestions(simulation.state, runs: simulation.runs, now: CoachFixtures.day(36, hour: 22), calendar: calendar).contains(.stillNormal(episodeID: id)))
        let check = CoachFixtures.day(37, hour: 8)
        simulation.state = CoachEngine.refresh(state: simulation.state, runs: simulation.runs, now: check, calendar: calendar).state
        #expect(CoachEngine.pendingQuestions(simulation.state, runs: simulation.runs, now: check, calendar: calendar).contains(.stillNormal(episodeID: id)))

        // Day 9: still normal, so stage 3: easy runs only, no Q or long run, none longer than the usual easy run.
        simulation.state = CoachEngine.answerIllness(.stillNormal(true), episodeID: id, state: simulation.state, runs: simulation.runs, now: check, calendar: calendar).state
        let easy = simulation.state.activeIllness!
        #expect(easy.stage == .easy)
        #expect(simulation.state.gap == nil)
        // The ramp for stage 4: G1, 9 days from Sunday's long run to the first run.
        #expect(easy.ramp?.tier == .g1)
        #expect(easy.ramp?.daysOff == 9)
        #expect(easy.ramp?.share == 0.75)
        let easyWeek = week(simulation, at: check)!
        #expect(easyWeek.kind == .illnessReturn)
        #expect(easyWeek.notes.map(\.text).contains("Easy runs only for now, with no speed work or long run, because you're getting over being ill."))
        let easyRuns = plannedRuns(simulation, at: check)
        #expect(!easyRuns.isEmpty)
        #expect(easyRuns.allSatisfy { $0.kind == .easy && $0.target.seconds <= 1_290 })
        #expect(!IllnessCoach.questions(simulation.state, now: check, calendar: calendar).contains(.stillNormal(episodeID: id)))

        // Day 10: the second easy run, with 4 symptom-free days (days 6-9) behind it: stage 4, AD-10's G1 ramp.
        simulation.state = CoachEngine.refresh(state: simulation.state, runs: simulation.runs, now: CoachFixtures.day(38, hour: 8), calendar: calendar).state
        let second = runToday(&simulation, at: CoachFixtures.day(38, hour: 17))!
        let back = simulation.state.activeIllness!
        #expect(back.stage == .backToPlan)
        #expect(back.easyRunsSinceFirst == 2)
        #expect(simulation.state.gap == back.ramp)
        // P-L30 counts from stage 4, not from the short runs before it.
        #expect(simulation.state.gap?.startedAt == back.stageStartedAt)
        #expect(!IllnessCoach.setsWayBack(simulation.state))
        #expect(IllnessCoach.outcome(simulation.state) == nil)
        let evening = CoachFixtures.day(38, hour: 20)
        let waitWeek = week(simulation, at: evening)!
        // The long run on day 13 comes before day 15: no run longer than the second run, the longest since the first.
        // That week isn't a ramp week yet.
        #expect(waitWeek.kind == .illnessReturn)
        #expect(waitWeek.notes.map(\.text).contains("Back to your plan, easing in. Until a week after your first run back, no run is longer than your longest since then."))
        #expect(!waitWeek.notes.map(\.text).contains("A week off costs little fitness; we'll ease back in over two weeks."))
        let rest = plannedRuns(simulation, at: evening)
        #expect(rest.contains { $0.kind == .long })
        #expect(rest.allSatisfy { $0.target.meters <= second.meters + 0.5 && !$0.isNewLongest })

        // A run saved twice counts once.
        let again = CoachEngine.logRun(second, state: simulation.state, runs: simulation.runs, now: CoachFixtures.day(38, hour: 21), calendar: calendar).0.state
        #expect(again.activeIllness?.easyRunsSinceFirst == 2)
        #expect(again.activeIllness?.stage == .backToPlan)

        // The next week's long run falls after day 15, so the ramp alone shapes it. The week before wasn't a ramp
        // week, so the week-end step starts the ramp here, with P-L30 counted from this week (the engine's closeWeek
        // runs that step; it is called and the week planned again here to stand in for it).
        simulation = CoachFixtures.follow(simulation.state, runs: simulation.runs, days: 4, from: 39)
        let nextWeek = CoachFixtures.day(42)
        simulation.state = IllnessCoach.weekEnded(5, state: simulation.state, runs: simulation.runs, now: nextWeek, calendar: calendar).state
        simulation.state = WeekPlanner.planWeek(6, state: simulation.state, runs: simulation.runs, now: nextWeek, calendar: calendar)
        let ramp = simulation.state.gap!
        #expect(ramp.weeksDone == 0)
        #expect(ramp.startedAt == simulation.state.weekStart(6, calendar: calendar))
        #expect(simulation.state.activeIllness?.ramp == ramp)
        let firstRampWeek = week(simulation, at: nextWeek)!
        #expect(firstRampWeek.kind == .ramp)
        #expect(firstRampWeek.notes.map(\.text).contains("A week off costs little fitness; we'll ease back in over two weeks."))
        let context = WeekPlanner.makeContext(week: 6, state: simulation.state, runs: simulation.runs, now: nextWeek, calendar: calendar)
        #expect(IllnessCoach.weekTargets(context) == nil)
        // Its long run is G1's 80% of the reference long run, not 10% over the short runs before it. Here the other
        // runs' 20-minute floor (HL-6) holds the planned run lower.
        #expect(abs((WeekPlanner.weekTargets(context).0.longRun?.meters ?? 0) - 0.8 * ramp.referenceLongRun.meters) < 1)
        #expect(context.longest == .zero)
        #expect(firstRampWeek.longRun!.meters > 1.1 * second.meters)

        // The episode ends with its ramp.
        var ended = simulation.state
        ended.gap = nil
        ended = IllnessCoach.weekEnded(8, state: ended, runs: simulation.runs, now: CoachFixtures.day(56), calendar: calendar).state
        #expect(ended.activeIllness == nil)
        #expect(ended.illnesses[0].stage == .over)
        #expect(ended.illnesses[0].endedAt == CoachFixtures.day(56))
        #expect(ended.status == .active)
    }

    /// Stage 3 lasts until 4 symptom-free days are done, even with 2 easy runs. With the days done, the next run, answer
    /// or week end moves it on.
    @Test func easyStageWaitsForFourSymptomFreeDays() {
        var (simulation, id) = sickWeek(until: .firstRun)
        // A second short run on day 8, before the check: it counts, but stage 2 waits for "Still feeling normal".
        let extra = LoggedRun(start: CoachFixtures.day(36, hour: 19), movingSeconds: 600, meters: 1_600)
        simulation.runs.append(extra)
        simulation.state = CoachEngine.logRun(extra, state: simulation.state, runs: simulation.runs, now: CoachFixtures.day(36, hour: 20), calendar: calendar).0.state
        #expect(simulation.state.activeIllness?.stage == .firstRun)
        #expect(simulation.state.activeIllness?.easyRunsSinceFirst == 2)
        // Day 9: 2 easy runs, but only 3 symptom-free days (days 6-8): stage 3.
        let check = CoachFixtures.day(37, hour: 8)
        simulation.state = CoachEngine.answerIllness(.stillNormal(true), episodeID: id, state: simulation.state, runs: simulation.runs, now: check, calendar: calendar).state
        #expect(simulation.state.activeIllness?.stage == .easy)
        // On day 10 the week-end step moves it on.
        let moved = IllnessCoach.weekEnded(5, state: simulation.state, runs: simulation.runs, now: CoachFixtures.day(38, hour: 8), calendar: calendar).state
        #expect(moved.activeIllness?.stage == .backToPlan)
        #expect(moved.gap == moved.activeIllness?.ramp)
        #expect(moved.gap?.startedAt == CoachFixtures.day(38, hour: 8))
    }

    /// "Feeling ill again" goes back one stage, which starts over (AD-12).
    @Test func relapseGoesBackOneStage() {
        let relapse = "Sorry you're feeling ill again. We'll go back one step and start it over."
        let later = CoachFixtures.day(39, hour: 8)

        // Stage 2 back to rest, also from a "no" at the next-day check.
        var (simulation, id) = sickWeek(until: .firstRun)
        let rest = CoachEngine.answerIllness(.stillNormal(false), episodeID: id, state: simulation.state, runs: simulation.runs, now: CoachFixtures.day(37, hour: 8), calendar: calendar)
        #expect(rest.notes.map(\.text).contains(relapse))
        #expect(rest.state.activeIllness?.stage == .rest)
        #expect(rest.state.activeIllness?.firstRunAt == nil)
        #expect(rest.state.activeIllness?.relapses == 1)
        #expect(rest.state.status.isPaused)

        // Stage 3 back to stage 2: a new first run, with symptom-free days counted again from tomorrow.
        (simulation, id) = sickWeek(until: .easy)
        let firstRun = CoachEngine.answerIllness(.feelIllAgain, episodeID: id, state: simulation.state, runs: simulation.runs, now: later, calendar: calendar)
        #expect(firstRun.notes.map(\.text).contains(relapse))
        let episode = firstRun.state.activeIllness!
        #expect(episode.stage == .firstRun)
        #expect(episode.firstRunAt == nil)
        #expect(episode.ramp == nil)
        #expect(episode.easyRunsSinceFirst == 0)
        #expect(episode.symptomFreeSince == CoachFixtures.day(40, hour: 0))
        #expect(firstRun.state.status == .active)

        // Stage 4 back to stage 3, through a new illness report; its ramp stops until stage 3 is done again.
        (simulation, id) = sickWeek(until: .backToPlan)
        #expect(simulation.state.activeIllness?.stage == .backToPlan)
        let easy = CoachEngine.reportIllness(kind: .headCold, state: simulation.state, runs: simulation.runs, now: later, calendar: calendar)
        #expect(easy.notes.map(\.text).contains(relapse))
        #expect(easy.state.illnesses.count == 1)
        #expect(easy.state.activeIllness?.stage == .easy)
        #expect(easy.state.activeIllness?.kind == .feverOrBelowNeck)
        #expect(easy.state.gap == nil)
        #expect(easy.state.activeIllness?.ramp != nil)
        #expect(CoachEngine.currentWeek(easy.state, now: later, calendar: calendar)?.kind == .illnessReturn)
    }

    /// A fever or anything below the neck reported after the first run back means no running again, at any stage
    /// (HL-19), while "just a head cold" goes back one stage.
    @Test func feverAgainMeansRestAgain() {
        let later = CoachFixtures.day(39, hour: 8)
        for stage in [IllnessStage.firstRun, .easy, .backToPlan] {
            let (simulation, _) = sickWeek(until: stage)
            #expect(simulation.state.activeIllness?.stage == stage)
            let again = CoachEngine.reportIllness(kind: .feverOrBelowNeck, state: simulation.state, runs: simulation.runs, now: later, calendar: calendar)
            #expect(again.notes.map(\.text).contains("Sorry you're feeling ill again. With a fever or anything below the neck, no running for now. Tap 'Ready' once you've felt normal for 2 full days."))
            #expect(again.state.illnesses.count == 1)
            let episode = again.state.activeIllness!
            #expect(episode.stage == .rest)
            #expect(episode.relapses == 1)
            #expect(episode.firstRunAt == nil && episode.ramp == nil && episode.symptomFreeSince == nil)
            #expect(again.state.gap == nil)
            #expect(again.state.status.isPaused)
            #expect(plannedRuns(CoachFixtures.Simulation(state: again.state, runs: simulation.runs), at: later).isEmpty)
        }
        let (simulation, _) = sickWeek(until: .easy)
        let cold = CoachEngine.reportIllness(kind: .headCold, state: simulation.state, runs: simulation.runs, now: later, calendar: calendar)
        #expect(cold.state.activeIllness?.stage == .firstRun)
        #expect(!cold.state.status.isPaused)
    }

    // MARK: Head cold (AD-12)

    /// A head cold is an EASE week: easy runs no longer than usual, no Q or long-run step. "Has it gone?" comes
    /// every 3 days; "Gone" brings the plan back and "Now a fever" stops running.
    @Test func headColdEasesTheWeekUntilItGoes() {
        var simulation = runningPlan()
        // The planned step-back week is already lighter than an EASE week, so it stays, without its Q.
        let early = CoachFixtures.day(29, hour: 8)
        let stepBack = CoachEngine.reportIllness(kind: .headCold, state: simulation.state, runs: simulation.runs, now: early, calendar: calendar)
        let lighter = CoachEngine.currentWeek(stepBack.state, now: early, calendar: calendar)!
        #expect(lighter.kind == .stepBack)
        #expect(lighter.qualitySessions.isEmpty)

        // The next loading week, with its new longest run, becomes an EASE week 10% lighter.
        simulation = CoachFixtures.follow(simulation.state, runs: simulation.runs, days: 8, from: 28)
        let own = simulation.state.weeks.first { $0.plan.index == 5 }!.plan
        #expect(own.kind == .loading)
        #expect(own.runs.contains { $0.isNewLongest })
        let coldAt = CoachFixtures.day(36, hour: 8)
        let cold = CoachEngine.reportIllness(kind: .headCold, state: simulation.state, runs: simulation.runs, now: coldAt, calendar: calendar)
        let id = cold.state.illnesses[0].id
        #expect(cold.state.status == .active)
        #expect(IllnessCoach.outcome(cold.state)! == (.ease, .headCold))
        #expect(!IllnessCoach.setsWayBack(cold.state))
        let week = CoachEngine.currentWeek(cold.state, now: coldAt, calendar: calendar)!
        #expect(week.kind == .ease)
        #expect(week.plannedVolume <= 0.9 * own.plannedVolume + 0.5)
        #expect(week.qualitySessions.isEmpty)
        #expect(week.runs.allSatisfy { !$0.isNewLongest && $0.target.meters <= 9_680.5 })
        #expect(week.notes.map(\.text).contains("Easy runs only while your cold lasts, with no speed work and nothing longer than usual. Stop if it feels worse."))
        #expect(!week.notes.contains { $0.text.contains("your new longest") })

        // "Has it gone?" after 3 days; "Still there" asks again 3 days later.
        #expect(!IllnessCoach.questions(cold.state, now: CoachFixtures.day(38, hour: 8), calendar: calendar).contains(.illnessGone(episodeID: id)))
        let due = CoachFixtures.day(39, hour: 8)
        #expect(CoachEngine.pendingQuestions(cold.state, runs: simulation.runs, now: due, calendar: calendar).contains(.illnessGone(episodeID: id)))
        let still = CoachEngine.answerIllness(.headCold(.stillThere), episodeID: id, state: cold.state, runs: simulation.runs, now: due, calendar: calendar)
        #expect(still.state.activeIllness?.nextCheck == CoachFixtures.day(42, hour: 8))
        #expect(!IllnessCoach.questions(still.state, now: due, calendar: calendar).contains(.illnessGone(episodeID: id)))

        // "Gone": the usual plan.
        let goneAt = CoachFixtures.day(42, hour: 8)
        let gone = CoachEngine.answerIllness(.headCold(.gone), episodeID: id, state: still.state, runs: simulation.runs, now: goneAt, calendar: calendar)
        #expect(gone.notes.map(\.text).contains("Good to hear. Your usual plan is back."))
        #expect(gone.state.activeIllness == nil)
        #expect(gone.state.illnesses[0].endedAt == goneAt)
        #expect(IllnessCoach.outcome(gone.state) == nil)

        // "Now a fever or below the neck": the no-running rules.
        let fever = CoachEngine.answerIllness(.headCold(.nowFever), episodeID: id, state: still.state, runs: simulation.runs, now: due, calendar: calendar)
        #expect(fever.state.activeIllness?.stage == .rest)
        #expect(fever.state.activeIllness?.kind == .feverOrBelowNeck)
        #expect(fever.state.status == .paused(reason: .illness, since: due))
        #expect(CoachEngine.currentWeek(fever.state, now: due, calendar: calendar)?.kind == .paused)
    }

    /// Until the one question is answered, head-cold rules apply (AD-17); a fever answer stops running, and saying
    /// it again while ill adds to the same episode.
    @Test func unansweredKindUsesHeadColdRules() {
        let simulation = runningPlan()
        let now = CoachFixtures.day(29, hour: 8)
        let ill = CoachEngine.reportIllness(kind: nil, state: simulation.state, runs: simulation.runs, now: now, calendar: calendar)
        let id = ill.state.illnesses[0].id
        #expect(ill.questions.contains(.illnessKind(episodeID: id)))
        #expect(IllnessCoach.questions(ill.state, now: now, calendar: calendar).contains(.illnessKind(episodeID: id)))
        #expect(ill.state.activeIllness?.stage == .headCold)
        #expect(IllnessCoach.outcome(ill.state)! == (.ease, .headCold))

        let fever = CoachEngine.answerIllness(.kind(.feverOrBelowNeck), episodeID: id, state: ill.state, runs: simulation.runs, now: now, calendar: calendar)
        #expect(fever.state.activeIllness?.stage == .rest)
        #expect(fever.state.status.isPaused)
        #expect(!IllnessCoach.questions(fever.state, now: now, calendar: calendar).contains(.illnessKind(episodeID: id)))
        // A later answer doesn't change it back.
        let late = CoachEngine.answerIllness(.kind(.headCold), episodeID: id, state: fever.state, runs: simulation.runs, now: now, calendar: calendar)
        #expect(late.state.activeIllness?.kind == .feverOrBelowNeck)

        // A head cold, then a fever reported the next day: the same episode, now resting.
        let cold = CoachEngine.reportIllness(kind: .headCold, state: simulation.state, runs: simulation.runs, now: now, calendar: calendar)
        let worse = CoachEngine.reportIllness(kind: .feverOrBelowNeck, bedBound: true, state: cold.state, runs: simulation.runs, now: CoachFixtures.day(30, hour: 8), calendar: calendar)
        #expect(worse.state.illnesses.count == 1)
        #expect(worse.state.activeIllness?.stage == .rest)
        #expect(worse.state.activeIllness?.bedBound == true)
        #expect(worse.state.activeIllness?.nextCheck == nil)
    }

    /// With a Mild injury open, a fever still stops running (HL-19); after "Ready" the illness's first run sets the
    /// week, inside the Mild report's limits.
    @Test func feverPausesAMildInjuryWeek() {
        let simulation = runningPlan()
        let now = CoachFixtures.day(29, hour: 8)
        let mild = CoachEngine.reportInjury(level: .mild, area: .shin, origin: .planScreen, runID: nil, state: simulation.state, runs: simulation.runs, now: now, calendar: calendar)
        let feverAt = now.addingTimeInterval(3_600)
        let fever = CoachEngine.reportIllness(kind: .feverOrBelowNeck, state: mild.state, runs: simulation.runs, now: feverAt, calendar: calendar)
        #expect(fever.state.status == .paused(reason: .illness, since: feverAt))
        #expect(CoachEngine.currentWeek(fever.state, now: feverAt, calendar: calendar)?.kind == .paused)

        let readyAt = CoachFixtures.day(30, hour: 8)
        let ready = CoachEngine.answerIllness(.ready(true), episodeID: fever.state.illnesses[0].id, state: fever.state, runs: simulation.runs, now: readyAt, calendar: calendar)
        #expect(ready.state.status == .active)
        let context = WeekPlanner.makeContext(week: 4, state: ready.state, runs: simulation.runs, now: readyAt, calendar: calendar)
        let week = WeekPlanner.weekTargets(context).0
        #expect(week.kind == .illnessReturn)
        #expect(week.runs == 1)
        #expect(week.quality.isEmpty)
        #expect(week.volume <= ready.state.injuries[0].heldVolume)
    }

    // MARK: Heat illness (AD-16)

    /// "Felt unwell in the heat": no running until a full day back to normal, then 2 easy runs of 30 min or less
    /// somewhere cool; each run counts once. A second heat illness adds the doctor line.
    @Test func heatIllnessPausesThenTwoShortRuns() {
        var simulation = runningPlan()
        let hot = CoachFixtures.day(29, hour: 8)
        let heat = CoachEngine.reportHeatIllness(state: simulation.state, runs: simulation.runs, now: hot, calendar: calendar)
        let line = "That sounds like the heat got to you. No running until you've felt normal for a full day, then two short easy runs somewhere cool."
        #expect(heat.notes.map(\.text).contains(line))
        #expect(heat.state.status == .paused(reason: .heat, since: hot))
        #expect(IllnessCoach.outcome(heat.state)! == (.pause, .heatIllness))
        #expect(heat.state.heat.permanentlyHighRisk)
        #expect(heat.state.heat.easyRunsLeft == 2)

        // Back after a normal day: the week's runs are easy and 30 min or less, with no Q or long run.
        let back = CoachFixtures.day(30, hour: 8)
        simulation.state = CoachEngine.resume(state: heat.state, runs: simulation.runs, now: back, calendar: calendar).state
        #expect(simulation.state.status == .active)
        let cool = week(simulation, at: back)!
        #expect(cool.notes.map(\.text).contains("Easy runs of 30 minutes or less, somewhere cool or indoors, because the heat got to you. Your usual runs come back after two of them."))
        let shortRuns = plannedRuns(simulation, at: back)
        #expect(!shortRuns.isEmpty)
        #expect(shortRuns.allSatisfy { $0.kind == .easy && $0.target.seconds <= 1_800.5 })

        // Thursday's run counts once, however often it is saved.
        let thursday = CoachFixtures.day(31, hour: 17)
        simulation.state = CoachEngine.refresh(state: simulation.state, runs: simulation.runs, now: CoachFixtures.day(31, hour: 7), calendar: calendar).state
        let run = runToday(&simulation, at: thursday)!
        #expect(simulation.state.heat.easyRunsLeft == 1)
        simulation.state = CoachEngine.logRun(run, state: simulation.state, runs: simulation.runs, now: thursday.addingTimeInterval(7_200), calendar: calendar).0.state
        #expect(simulation.state.heat.easyRunsLeft == 1)
        #expect(week(simulation, at: thursday.addingTimeInterval(7_200))!.notes.map(\.text).contains("Easy runs of 30 minutes or less, somewhere cool or indoors, because the heat got to you. Your usual runs come back after one more of them."))

        // Sunday's run is the second: the plan's own runs come back.
        simulation.state = CoachEngine.refresh(state: simulation.state, runs: simulation.runs, now: CoachFixtures.day(34, hour: 7), calendar: calendar).state
        _ = runToday(&simulation, at: CoachFixtures.day(34, hour: 9))
        #expect(simulation.state.heat.easyRunsLeft == 0)
        let monday = CoachFixtures.day(35, hour: 8)
        simulation.state = CoachEngine.refresh(state: simulation.state, runs: simulation.runs, now: monday, calendar: calendar).state
        #expect(!week(simulation, at: monday)!.notes.map(\.text).contains { $0.hasPrefix("Easy runs of 30 minutes or less") })

        // A second heat illness.
        let again = CoachEngine.reportHeatIllness(state: simulation.state, runs: simulation.runs, now: CoachFixtures.day(40, hour: 8), calendar: calendar)
        #expect(again.notes.map(\.text).contains(line + " If this keeps happening, please talk to a doctor."))
    }

    /// A heat illness while the plan is paused for an illness keeps that pause; the 2 short runs count once running
    /// is back.
    @Test func heatIllnessDuringAnIllnessPause() {
        let (simulation, id) = sickWeek(until: .rest)
        let hot = CoachFixtures.day(35, hour: 8)
        let heat = IllnessCoach.reportHeatIllness(state: simulation.state, now: hot, calendar: calendar)
        #expect(heat.state.status == .paused(reason: .illness, since: CoachFixtures.day(29, hour: 8)))
        #expect(heat.state.heat.easyRunsLeft == 2)
        let paused = LoggedRun(start: CoachFixtures.day(35, hour: 9), movingSeconds: 1_200, meters: 3_200)
        #expect(IllnessCoach.runLogged(paused, state: heat.state, now: CoachFixtures.day(35, hour: 10), calendar: calendar).state.heat.easyRunsLeft == 2)

        // "Ready": the first run back is also the first of the two.
        var state = IllnessCoach.answer(.ready(true), episodeID: id, state: heat.state, runs: simulation.runs, now: CoachFixtures.day(36, hour: 8), calendar: calendar).state
        let first = LoggedRun(start: CoachFixtures.day(36, hour: 9), movingSeconds: 900, meters: 2_400)
        state = IllnessCoach.runLogged(first, state: state, now: CoachFixtures.day(36, hour: 10), calendar: calendar).state
        #expect(state.heat.easyRunsLeft == 1)
        #expect(state.activeIllness?.firstRunAt == first.start)
    }

    // MARK: Rules other modules read (AD-10, HL-19, AD-16)

    /// HL-19: a fever or below-the-neck illness now or within 48 h before the start means don't start.
    @Test func raceStartWaitsTwoDaysAfterSymptoms() {
        var state = CoachFixtures.start(CoachFixtures.regularIntake())
        var fever = IllnessEpisode(reportedAt: CoachFixtures.day(10), kind: .feverOrBelowNeck)
        state.illnesses = [fever]
        #expect(IllnessCoach.raceStartBlocked(state, raceStart: CoachFixtures.day(20)))
        #expect(!IllnessCoach.raceStartBlocked(state, raceStart: CoachFixtures.day(9)))

        // Back to normal from the start of day 14: a start 47 h later is too soon, one 49 h later is not.
        fever.stage = .easy
        fever.symptomFreeSince = CoachFixtures.day(14, hour: 0)
        state.illnesses = [fever]
        #expect(IllnessCoach.raceStartBlocked(state, raceStart: CoachFixtures.day(15, hour: 23)))
        #expect(!IllnessCoach.raceStartBlocked(state, raceStart: CoachFixtures.day(16, hour: 1)))

        // A head cold never blocks the start.
        state.illnesses = [IllnessEpisode(reportedAt: CoachFixtures.day(19), kind: .headCold)]
        #expect(!IllnessCoach.raceStartBlocked(state, raceStart: CoachFixtures.day(20)))
    }

    /// The illness sets the way back while it rests, takes its first run or runs easy (AD-12 stage 4 replaces the
    /// gap's own ramp), and AD-5's illness rows.
    @Test func wayBackAndOutcomes() {
        var state = CoachFixtures.start(CoachFixtures.regularIntake())
        #expect(!IllnessCoach.setsWayBack(state))
        #expect(IllnessCoach.outcome(state) == nil)
        var episode = IllnessEpisode(reportedAt: CoachFixtures.day(3), kind: .feverOrBelowNeck)
        for (stage, sets) in [(IllnessStage.rest, true), (.firstRun, true), (.easy, true), (.backToPlan, false), (.headCold, false)] {
            episode.stage = stage
            state.illnesses = [episode]
            #expect(IllnessCoach.setsWayBack(state) == sets)
        }
        episode.stage = .easy
        state.illnesses = [episode]
        #expect(IllnessCoach.outcome(state) == nil)
        episode.endedAt = CoachFixtures.day(10)
        episode.stage = .over
        state.illnesses = [episode]
        #expect(!IllnessCoach.setsWayBack(state))
    }

    /// AD-16: an illness report makes the runner high-risk for heat for 10 days; a heat illness, from then on.
    @Test func illnessRaisesHeatRiskForTenDays() {
        let simulation = runningPlan()
        let now = CoachFixtures.day(29, hour: 8)
        let ill = IllnessCoach.report(kind: .headCold, bedBound: false, state: simulation.state, runs: simulation.runs, now: now, calendar: calendar)
        #expect(ill.state.heat.highRiskUntil == CoachFixtures.day(39, hour: 8))
        #expect(ill.state.heat.isHighRisk(on: CoachFixtures.day(38)))
        #expect(!ill.state.heat.isHighRisk(on: CoachFixtures.day(40)))
        // A later report never shortens it.
        var longer = ill.state
        longer.heat.highRiskUntil = CoachFixtures.day(60)
        #expect(IllnessCoach.report(kind: .headCold, bedBound: false, state: longer, runs: simulation.runs, now: now, calendar: calendar).state.heat.highRiskUntil == CoachFixtures.day(60))
    }
}
