//
//  InjuryTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// Reporting an injury against the rules' examples: the three levels, the recovery plan and the Severe return, their
/// projections, the weekly checks and the 12-month memory (AD-13 to AD-14e, HL-15, HL-18, TI-3b, TI-3c).
@MainActor
struct InjuryTests {
    let calendar = CoachFixtures.calendar

    /// A plan with the worked examples' runner: a pre-injury week of 30 km over 4 runs and a 12 km long run.
    func examplePlan(level: InjuryLevel, ranThirtyMinutes: Bool = true) -> (state: CoachState, reportID: UUID) {
        var state = CoachFixtures.start(CoachFixtures.regularIntake())
        state.cycle.runsPerWeek = 4
        state.assessment.runsCap = 4
        state.paces.easy = PaceBand(fast: 360, slow: 360)
        let baseline = InjuryBaseline(
            volumeUnit: .distance,
            weekVolume: 30_000,
            longRun: Load(12_000, in: .distance, pace: 360),
            ranThirtyMinutesNonStop: ranThirtyMinutes
        )
        let report = InjuryReport(reportedAt: CoachFixtures.day(27, hour: 20), origin: .planScreen, level: level, area: .shin, baseline: baseline)
        state.injuries.append(report)
        return (state, report.id)
    }

    func kilometres(_ weeks: [RecoveryWeekPreview]) -> [Double] {
        weeks.map { ($0.volume / 100).rounded() / 10 }
    }

    func longRuns(_ weeks: [RecoveryWeekPreview]) -> [Double] {
        weeks.map { (($0.longRun?.meters ?? 0) / 10).rounded() / 100 }
    }

    // MARK: Projections (AD-14b, AD-14c)

    /// AD-14b's default example: 5 planned weeks become 8 under HL-1 and HL-2.
    @Test func defaultRecoveryPlanProjection() {
        let (state, id) = examplePlan(level: .intense)
        let weeks = InjuryCoach.previewRecovery(.standard, reportID: id, state: state)
        #expect(weeks.map(\.label) == ["Week 1: no running", "Week 2: 50%", "Week 3: 50%", "Week 4: 75%", "Week 5: 100%", "Week 6: 100%", "Week 7: 100%", "Week 8: 100%"])
        #expect(kilometres(weeks) == [0, 15, 15, 22.5, 27, 30, 30, 30])
        #expect(longRuns(weeks) == [0, 6, 6, 9, 9.9, 10.89, 11.98, 12])
        #expect(weeks.map(\.capped) == [false, false, false, false, true, true, true, false])
        let report = state.injuries[0]
        let projection = InjuryCoach.recoveryProjection(.standard, report: report, state: state)
        #expect(projection.plannedWeeks == 5)
        #expect(projection.addedWeeks == 3)
    }

    /// AD-14b's faster example: no week off, 1 week at 70%, then straight back to 100%.
    @Test func fasterRecoveryPlanProjection() {
        let (state, id) = examplePlan(level: .intense)
        let faster = RecoveryPlanSettings(restWeeks: 0, reducedShare: 0.7, reducedWeeks: 1, rampStep: nil)
        let weeks = InjuryCoach.previewRecovery(faster, reportID: id, state: state)
        #expect(weeks.map(\.label) == ["Week 1: 70%", "Week 2: 100%"])
        #expect(kilometres(weeks) == [21, 30])
        #expect(longRuns(weeks) == [8.4, 12])
    }

    /// AD-14c's example: a 3-week pause (G2) gives 2 return weeks at 50%, then HL-2 and the long run's 10% steps.
    @Test func severeReturnProjection() {
        var (state, id) = examplePlan(level: .severe)
        state.injuries[0].pauseStart = CoachFixtures.day(27, hour: 20)
        state.injuries[0].lastRunBeforePause = CoachFixtures.day(27, hour: 7)
        let ready = CoachFixtures.day(48)
        let settings = InjuryCoach.defaultReturn(reportID: id, state: state, now: ready, calendar: calendar)
        #expect(settings == ReturnSettings(weeks: 2, form: .jogging, share: 0.5, rampStep: 0.2))
        let weeks = InjuryCoach.previewReturn(settings, reportID: id, state: state, now: ready, calendar: calendar)
        #expect(kilometres(weeks) == [15, 15, 18, 21.6, 25.9, 30, 30, 30, 30, 30])
        #expect(longRuns(weeks) == [6, 6, 6.6, 7.2, 7.9, 8.6, 9.4, 10.3, 11.3, 12])
        #expect(weeks.first?.label == "Week 1: 50%")
        let report = state.injuries[0]
        let projection = InjuryCoach.returnProjection(settings, report: report, state: state, pauseDays: 21)
        #expect(projection.plannedWeeks == 5)
    }

    /// AD-14c's defaults by pause: 50% up to 4 weeks, else 30%; jogging only after a short pause and a 30-min long
    /// run; AD-10's step for the pause's tier.
    @Test func defaultReturnFollowsThePause() {
        var (state, id) = examplePlan(level: .severe)
        state.injuries[0].pauseStart = CoachFixtures.day(27, hour: 20)
        state.injuries[0].lastRunBeforePause = CoachFixtures.day(27, hour: 7)
        func settings(after days: Int) -> ReturnSettings {
            InjuryCoach.defaultReturn(reportID: id, state: state, now: CoachFixtures.day(27 + days), calendar: calendar)
        }
        #expect(settings(after: 5) == ReturnSettings(weeks: 2, form: .jogging, share: 0.5, rampStep: 0.25))
        #expect(settings(after: 12) == ReturnSettings(weeks: 2, form: .jogging, share: 0.5, rampStep: 0.25))
        #expect(settings(after: 28) == ReturnSettings(weeks: 2, form: .jogging, share: 0.5, rampStep: 0.2))
        #expect(settings(after: 40) == ReturnSettings(weeks: 2, form: .jogWalk, share: 0.3, rampStep: 0.15))
        #expect(settings(after: 70) == ReturnSettings(weeks: 2, form: .jogWalk, share: 0.3, rampStep: 0.1))
        state.injuries[0].baseline.ranThirtyMinutesNonStop = false
        #expect(settings(after: 12).form == .jogWalk)
        // A return the runner already set is kept.
        let own = ReturnSettings(weeks: 1, form: .jogging, share: 0.7, rampStep: nil)
        state.injuries[0].returnPlan = own
        #expect(settings(after: 40) == own)
    }

    /// Jog/walk weeks show running minutes: 2 min jogging and 2 walking, then 3 and 1, then 1-min walks while the
    /// jogging doubles (6, 12, 24 min) until the runs are continuous again (AD-14c). After a pause over 4 weeks the
    /// first return week has no W4max to compare with, so it runs at its share.
    @Test func jogWalkReturnCountsRunningMinutes() {
        var (state, id) = examplePlan(level: .severe)
        state.injuries[0].pauseStart = CoachFixtures.day(27, hour: 20)
        state.injuries[0].lastRunBeforePause = CoachFixtures.day(27, hour: 7)
        let ready = CoachFixtures.day(67)
        let settings = InjuryCoach.defaultReturn(reportID: id, state: state, now: ready, calendar: calendar)
        #expect(settings == ReturnSettings(weeks: 2, form: .jogWalk, share: 0.3, rampStep: 0.15))
        let weeks = InjuryCoach.previewReturn(settings, reportID: id, state: state, now: ready, calendar: calendar)
        #expect(weeks.prefix(5).allSatisfy { $0.volumeUnit == .time })
        #expect(weeks.dropFirst(5).allSatisfy { $0.volumeUnit == .distance })
        #expect(weeks.last?.share == 1)
        // 30% of the pre-injury week's running: 9 km at 6:00/km is 54 running minutes, in both return weeks.
        #expect(weeks.prefix(2).map { ($0.volume / 60).rounded() } == [54, 54])
        #expect(weeks.first?.capped == false)
        #expect(InjuryCoach.jogWalkPattern(.returnWeek(number: 0, share: 0.5), form: .jogWalk)! == (120, 120))
        #expect(InjuryCoach.jogWalkPattern(.returnWeek(number: 1, share: 0.5), form: .jogWalk)! == (180, 60))
        #expect(InjuryCoach.jogWalkPattern(.ramp(position: 2, share: 0.9), form: .jogWalk)! == (1_440, 60))
        #expect(InjuryCoach.jogWalkPattern(.ramp(position: 3, share: 1), form: .jogWalk) == nil)
    }

    /// The edit ranges: shares in steps of 10 from 10 to 90%, ramp steps in steps of 5 from 10 to 50 (AD-14b).
    @Test func settingsStayInsideTheirRanges() {
        let settings = RecoveryPlanSettings(restWeeks: -1, reducedShare: 0.94, reducedWeeks: 0, rampStep: 0.63).normalized
        #expect(settings.restWeeks == 0)
        #expect(settings.reducedShare == 0.9)
        #expect(settings.reducedWeeks == 1)
        #expect(settings.rampStep == 0.5)
        #expect(RecoveryPlanSettings(reducedShare: 0.04, rampStep: 0.12).normalized.reducedShare == 0.1)
        #expect(RecoveryPlanSettings(reducedShare: 0.7, rampStep: 0.12).normalized.rampStep == 0.1)
        #expect(ReturnSettings(weeks: 0, form: .jogging, share: 0.35, rampStep: 0.17).normalized == ReturnSettings(weeks: 1, form: .jogging, share: 0.4, rampStep: 0.15))
    }

    // MARK: Flows through the engine (AD-13a to AD-14c)

    /// Four weeks of a Speed Work plan, done as planned: the pre-injury week is about 16 km with a 9.7 km long run.
    func runningPlan(runDays: Set<Weekday>? = nil) -> CoachFixtures.Simulation {
        var intake = CoachFixtures.regularIntake(GoalChoice(flavor: .speedWork, distance: .tenK))
        if let runDays { intake.runDays = runDays }
        return CoachFixtures.follow(CoachFixtures.start(intake), days: 28)
    }

    /// Follows the plan from `first` for `days` days, answering every weekly injury check with `check`, and returns
    /// the notes each morning's refresh gave.
    func follow(_ simulation: CoachFixtures.Simulation, from first: Int, days: Int, check: RecoveryCheckAnswer = .better) -> (CoachFixtures.Simulation, [String]) {
        var simulation = simulation
        var notes: [String] = []
        for day in first ..< first + days {
            let morning = CoachFixtures.day(day)
            let refreshed = CoachEngine.refresh(state: simulation.state, runs: simulation.runs, now: morning, calendar: calendar)
            notes += refreshed.notes.map(\.text)
            simulation.state = refreshed.state
            simulation = CoachFixtures.follow(simulation.state, runs: simulation.runs, days: 1, from: day)
            let evening = CoachFixtures.day(day, hour: 21)
            for case .injuryCheck(let id) in CoachEngine.pendingQuestions(simulation.state, runs: simulation.runs, now: evening, calendar: calendar) {
                simulation.state = CoachEngine.answerInjury(.recoveryCheck(check), reportID: id, state: simulation.state, runs: simulation.runs, now: evening, calendar: calendar).state
            }
        }
        return (simulation, notes)
    }

    /// AD-13a: Mild holds the report week's level with every run easy; "Cleared" brings the follow-up a week later,
    /// and "Still clear" closes the report (AD-14a).
    @Test func mildHoldsThenClears() {
        let plan = runningPlan()
        let now = CoachFixtures.day(29, hour: 9)
        let mild = CoachEngine.reportInjury(level: .mild, area: .shin, origin: .planScreen, runID: nil, state: plan.state, runs: plan.runs, now: now, calendar: calendar)
        #expect(mild.notes.first?.text == "Got it. Until it clears, your runs are all easy, with no speed work or hills, and your distance stays where it is. I'll check in each week.")
        #expect(mild.notes.contains { $0.text == "Because of your shin, I'll suggest flat routes and leave out hills for now." })
        #expect(InjuryCoach.outcome(mild.state)! == (.hold, .mildInjury))
        let report = mild.state.injuries[0]
        let week = CoachEngine.currentWeek(mild.state, now: now, calendar: calendar)!
        #expect(week.plannedVolume <= report.heldVolume + 0.001)
        #expect(!week.sessions.contains { $0.isQuality })
        #expect(mild.state.status == .active)

        // The weekly check comes with the weekly check-in; "Cleared" holds one more week, then the follow-up.
        var simulation = CoachFixtures.follow(mild.state, runs: plan.runs, days: 5, from: 30, week: nil)
        let sunday = CoachFixtures.day(34, hour: 20)
        #expect(CoachEngine.pendingQuestions(simulation.state, runs: simulation.runs, now: sunday, calendar: calendar).contains(.injuryCheck(reportID: report.id)))
        let cleared = CoachEngine.answerInjury(.mildCheck(.cleared), reportID: report.id, state: simulation.state, runs: simulation.runs, now: sunday, calendar: calendar)
        #expect(cleared.notes.first?.text == "Great news. Your usual runs are back this week, and I'll check again in a week.")
        #expect(InjuryCoach.outcome(cleared.state)! == (.hold, .mildCleared))
        simulation = CoachFixtures.follow(cleared.state, runs: simulation.runs, days: 6, from: 35)
        #expect(!CoachEngine.pendingQuestions(simulation.state, runs: simulation.runs, now: CoachFixtures.day(40, hour: 20), calendar: calendar).contains(.mildFollowUp(reportID: report.id)))
        let followUpDay = CoachFixtures.day(41, hour: 20)
        #expect(CoachEngine.pendingQuestions(simulation.state, runs: simulation.runs, now: followUpDay, calendar: calendar).contains(.mildFollowUp(reportID: report.id)))
        let closed = CoachEngine.answerInjury(.followUp(.stillClear), reportID: report.id, state: simulation.state, runs: simulation.runs, now: followUpDay, calendar: calendar)
        #expect(closed.notes.first?.text == "Your shin injury is closed. I'll keep it in mind for a while.")
        #expect(closed.state.injuries[0].status.isClosed)
        #expect(InjuryCoach.outcome(closed.state) == nil)
        // A Mild report adds no risk points (TI-3b).
        #expect(!closed.state.assessment.risk.factors.contains(.recentInjury))
    }

    /// AD-5 HOLD after a planned step-back holds the level before it, so Mild keeps that level once the step-back
    /// week is over (AD-13a).
    @Test func mildDuringAStepBackHoldsThePreStepBackLevel() {
        var state = runningPlan().state
        let week = state.weeks[state.weeks.count - 1].plan
        state.weeks[state.weeks.count - 1].plan.kind = .stepBack
        state.weeks[state.weeks.count - 1].plan.plannedVolume = 0.75 * week.plannedVolume
        state.cycle.lastLoadingVolume = week.plannedVolume
        let held = InjuryCoach.heldLevel(state.weeks.last?.plan, state: state)
        #expect(held.volume == week.plannedVolume)
        #expect(held.longRun == state.cycle.lastLoadingLongRun)
        #expect(InjuryCoach.heldLevel(week, state: state).volume == week.plannedVolume)
    }

    /// AD-13b: Intense pauses until the medical question is answered; Yes starts the default recovery plan with its
    /// week off; No or Not sure makes the report Severe.
    @Test func intenseWaitsForTheMedicalQuestion() {
        let plan = runningPlan()
        let now = CoachFixtures.day(29, hour: 9)
        let intense = CoachEngine.reportInjury(level: .intense, area: .knee, origin: .planScreen, runID: nil, state: plan.state, runs: plan.runs, now: now, calendar: calendar)
        let id = intense.state.injuries[0].id
        #expect(intense.questions.contains(.medicalClearance(reportID: id)))
        #expect(intense.state.status.isPaused)
        #expect(InjuryCoach.outcome(intense.state)! == (.pause, .intenseNotCleared))
        let paused = CoachEngine.currentWeek(intense.state, now: now, calendar: calendar)!
        #expect(paused.kind == .paused)
        #expect(paused.notes.map(\.text) == ["No running for now, because you're not cleared to train yet. Your plan is paused until you answer the medical question."])
        #expect(CoachEngine.pendingQuestions(intense.state, runs: plan.runs, now: now, calendar: calendar).contains(.medicalClearance(reportID: id)))

        let yes = CoachEngine.answerInjury(.clearance(.yes), reportID: id, state: intense.state, runs: plan.runs, now: now, calendar: calendar)
        #expect(yes.questions.contains(.recoveryPlan(reportID: id)))
        #expect(yes.state.status == .active)
        #expect(InjuryCoach.outcome(yes.state)! == (.recoveryPlan, .intenseCleared))
        let rest = CoachEngine.currentWeek(yes.state, now: now, calendar: calendar)!
        #expect(rest.kind == .recovery)
        #expect(!rest.sessions.contains { $0.kind.isRun })
        #expect(InjuryCoach.recoveryOffer(yes.state.injuries[0], state: yes.state) == "Here's a recovery plan: 1 week off running, 2 weeks at half your usual distance, then 2 weeks building back. Change anything that doesn't suit you, and make it faster or slower whenever you like.")

        let notSure = CoachEngine.answerInjury(.clearance(.notSure), reportID: id, state: intense.state, runs: plan.runs, now: now, calendar: calendar)
        #expect(notSure.notes.first?.text == "Then let's pause your plan until you're ready.")
        #expect(notSure.state.injuries[0].level == .severe)
        #expect(notSure.state.injuries[0].mode == .paused)
        #expect(InjuryCoach.outcome(notSure.state)! == (.pause, .severeInjury))
    }

    /// AD-13c, AD-14c: Severe pauses the plan; a run logged during the pause and the weekly card ask "Ready to run
    /// again?"; Ready starts the return at AD-14c's defaults, whose first week HL-2 lets run at its share.
    @Test func severePausesUntilReady() {
        let plan = runningPlan()
        let now = CoachFixtures.day(29, hour: 9)
        let severe = CoachEngine.reportInjury(level: .severe, area: .calfAchilles, origin: .planScreen, runID: nil, state: plan.state, runs: plan.runs, now: now, calendar: calendar)
        let id = severe.state.injuries[0].id
        #expect(severe.notes.first?.text == "Your plan is paused until you're ready to come back. Rest up, and follow your doctor's or physio's advice if you're seeing one. Your goal and runs are saved.")
        #expect(severe.state.status.isPaused)
        #expect(CoachEngine.resumeQuestion(severe.state) == "Ready to run again?")
        #expect(CoachEngine.currentWeek(severe.state, now: now, calendar: calendar)?.notes.map(\.text) == ["No running for now, because you need a break from running for your injury. Your plan is paused until you're ready to come back; tap Ready whenever you are."])

        // The weekly card, and "Not yet".
        #expect(!InjuryCoach.questions(severe.state, now: CoachFixtures.day(35), calendar: calendar).contains(.readyToRun(reportID: id)))
        let cardDay = CoachFixtures.day(36, hour: 10)
        #expect(InjuryCoach.questions(severe.state, now: cardDay, calendar: calendar).contains(.readyToRun(reportID: id)))
        let notYet = CoachEngine.answerInjury(.ready(false), reportID: id, state: severe.state, runs: plan.runs, now: cardDay, calendar: calendar)
        #expect(notYet.notes.first?.text == "No rush. I'll ask again next week, or tap Ready whenever you are.")
        #expect(!InjuryCoach.questions(notYet.state, now: CoachFixtures.day(37), calendar: calendar).contains(.readyToRun(reportID: id)))

        // A run during the pause counts, restarts nothing, and asks again.
        let pauseRun = LoggedRun(start: CoachFixtures.day(38, hour: 7), movingSeconds: 1_200, meters: 3_000)
        let (logged, _) = CoachEngine.logRun(pauseRun, state: notYet.state, runs: plan.runs + [pauseRun], now: CoachFixtures.day(38, hour: 8), calendar: calendar)
        #expect(logged.notes.contains { $0.text == "I see you went for a run. Ready to run again?" })
        #expect(logged.questions.contains(.readyToRun(reportID: id)))
        #expect(logged.state.status.isPaused)

        // Ready after 23 days off: 2 weeks of easy jogging at 50%, then +20 points a week (G2).
        let readyDay = CoachFixtures.day(50, hour: 9)
        let runs = plan.runs + [pauseRun]
        let waiting = CoachEngine.refresh(state: logged.state, runs: runs, now: readyDay, calendar: calendar).state
        let ready = CoachEngine.resume(state: waiting, runs: runs, now: readyDay, calendar: calendar)
        #expect(ready.notes.first?.text == "Welcome back. For 2 weeks we'll do easy jogging at about 50% of your usual distance, then build back step by step. You can make it faster or slower any time.")
        #expect(ready.state.status == .active)
        #expect(ready.state.injuries[0].mode == .returning)
        let report = ready.state.injuries[0]
        #expect(InjuryCoach.returnSettings(report, calendar: calendar) == ReturnSettings(weeks: 2, form: .jogging, share: 0.5, rampStep: 0.2))
        let week = CoachEngine.currentWeek(ready.state, now: readyDay, calendar: calendar)!
        #expect(week.kind == .injuryReturn)
        #expect(!week.sessions.contains { $0.isQuality })

        // The first return week is a restart, the second isn't.
        let first = WeekPlanner.makeContext(week: week.index, state: ready.state, runs: runs, now: readyDay, calendar: calendar)
        #expect(InjuryCoach.restartVolume(first) == 0.5 * report.baseline.weekVolume)
        let second = WeekPlanner.makeContext(week: week.index + 1, state: ready.state, runs: runs, now: readyDay, calendar: calendar)
        #expect(InjuryCoach.restartVolume(second) == nil)
    }

    /// AD-14c after 41 days off (G3): W4max holds no running, so HL-2 alone would cap the first return week at
    /// 10 minutes; it runs at its 30% share instead, as AD-10's first ramp week does.
    @Test func aLongPauseRestartsAtItsShare() throws {
        let plan = runningPlan()
        let severe = CoachEngine.reportInjury(level: .severe, area: .calfAchilles, origin: .planScreen, runID: nil, state: plan.state, runs: plan.runs, now: CoachFixtures.day(29, hour: 9), calendar: calendar)
        let readyDay = CoachFixtures.day(70, hour: 9)
        let waiting = CoachEngine.refresh(state: severe.state, runs: plan.runs, now: readyDay, calendar: calendar).state
        let ready = CoachEngine.resume(state: waiting, runs: plan.runs, now: readyDay, calendar: calendar)
        let report = ready.state.injuries[0]
        #expect(InjuryCoach.returnSettings(report, calendar: calendar) == ReturnSettings(weeks: 2, form: .jogWalk, share: 0.3, rampStep: 0.15))
        let week = try #require(CoachEngine.currentWeek(ready.state, now: readyDay, calendar: calendar))
        #expect(week.kind == .injuryReturn)
        let context = WeekPlanner.makeContext(week: week.index, state: ready.state, runs: plan.runs, now: readyDay, calendar: calendar)
        #expect(context.w4max == 0)
        let restart = try #require(InjuryCoach.restartVolume(context))
        #expect(context.weekCap == restart)
        // Jog/walk sessions: 30% of the pre-injury running, with the walking on top.
        #expect(abs(week.plannedVolume - restart) < 1)
        #expect(week.plannedVolume >= 0.3 * report.baseline.weekVolume)
        #expect(abs(week.runs.reduce(0) { $0 + $1.target.meters } - week.plannedVolume) < 1)
    }

    /// AD-14b: the default recovery plan, done week by week, ends after the first week at 100% with the long run
    /// back, as its preview showed; the report closes, the injury window starts and the plan picks up from the
    /// pre-injury week (AD-14d, TI-3c). A late review applies the end again without repeating it.
    @Test func recoveryPlanEndsAtThePreInjuryWeek() {
        let plan = runningPlan()
        let now = CoachFixtures.day(28, hour: 9)
        let intense = CoachEngine.reportInjury(level: .intense, area: .shin, origin: .planScreen, runID: nil, state: plan.state, runs: plan.runs, now: now, calendar: calendar)
        let id = intense.state.injuries[0].id
        let yes = CoachEngine.answerInjury(.clearance(.yes), reportID: id, state: intense.state, runs: plan.runs, now: now, calendar: calendar)
        let preview = InjuryCoach.previewRecovery(.standard, reportID: id, state: yes.state)
        #expect(preview.count == 8)

        // Weeks 4 to 11 are the recovery plan; the morning of week 12 reviews week 11.
        let (beforeEnd, _) = follow(CoachFixtures.Simulation(state: yes.state, runs: plan.runs), from: 29, days: 55)
        let report = beforeEnd.state.injuries[0]
        #expect(report.mode == .recoveryPlan)
        #expect(report.firstRunBack != nil)
        let ending = CoachFixtures.day(84, hour: 6)
        #expect(InjuryCoach.outcome(beforeEnd.state)! == (.recoveryPlan, .intenseCleared))
        #expect(InjuryCoach.outcome(InjuryCoach.reviewState(beforeEnd.state, week: 11, runs: beforeEnd.runs, now: ending, calendar: calendar)) == nil)

        let closed = CoachEngine.closeWeek(11, state: beforeEnd.state, runs: beforeEnd.runs, now: ending, calendar: calendar)
        let after = closed.state.injuries[0]
        #expect(after.status.isClosed)
        #expect(after.closedWeek == 11)
        #expect(closed.notes.contains { $0.text == "Your shin injury is closed. I'll keep it in mind for a while." })
        #expect(closed.notes.contains { $0.text.hasPrefix("For the next ") && $0.text.hasSuffix("weeks I'll build a little more slowly. A recent injury makes another one more likely, so this protects your progress.") })
        #expect(closed.state.cycle.position == 0)
        #expect(closed.state.cycle.lastLoadingVolume == report.baseline.weekVolume)
        #expect(closed.state.quality.doses.isEmpty)
        #expect(InjuryCoach.injuryWindowActive(closed.state, now: ending, calendar: calendar))

        // The week end is recomputed, not repeated.
        let again = InjuryCoach.weekEnded(11, state: closed.state, runs: beforeEnd.runs, now: ending, calendar: calendar)
        #expect(again.state == closed.state)
        #expect(again.notes.isEmpty)
    }

    /// AD-13e: a report at the same area changes that report's level; Intense moved down to Mild ends the recovery
    /// plan at the current recovery week's level.
    @Test func levelChangesKeepTheReport() {
        let plan = runningPlan()
        let now = CoachFixtures.day(29, hour: 9)
        let mild = CoachEngine.reportInjury(level: .mild, area: .shin, origin: .planScreen, runID: nil, state: plan.state, runs: plan.runs, now: now, calendar: calendar)
        let intense = CoachEngine.reportInjury(level: .intense, area: .shin, origin: .planScreen, runID: nil, state: mild.state, runs: plan.runs, now: now, calendar: calendar)
        #expect(intense.state.injuries.count == 1)
        let id = intense.state.injuries[0].id
        #expect(intense.state.injuries[0].level == .intense)
        #expect(intense.state.injuries[0].everIntenseOrSevere)
        #expect(intense.questions.contains(.medicalClearance(reportID: id)))

        let yes = CoachEngine.answerInjury(.clearance(.yes), reportID: id, state: intense.state, runs: plan.runs, now: now, calendar: calendar)
        let later = CoachFixtures.day(37, hour: 9)
        let down = CoachEngine.answerInjury(.level(.mild), reportID: id, state: yes.state, runs: plan.runs, now: later, calendar: calendar)
        #expect(down.notes.first?.text == "Got it. Your recovery plan ends here, and your runs stay easy at this week's distance until your shin clears.")
        let report = down.state.injuries[0]
        #expect(report.mode == .mild)
        #expect(report.heldVolume == 0.5 * report.baseline.weekVolume)
        // The memory and its points stay (TI-3b).
        #expect(down.state.assessment.risk.factors.contains(.recentInjury))
    }

    /// AD-13a, AD-13b: "Worse" suggests Intense; taking it asks the medical question.
    @Test func worseSuggestsIntense() {
        let plan = runningPlan()
        let mild = CoachEngine.reportInjury(level: .mild, area: nil, origin: .planScreen, runID: nil, state: plan.state, runs: plan.runs, now: CoachFixtures.day(29, hour: 9), calendar: calendar)
        let id = mild.state.injuries[0].id
        let sunday = CoachFixtures.day(34, hour: 20)
        let worse = CoachEngine.answerInjury(.mildCheck(.worse), reportID: id, state: mild.state, runs: plan.runs, now: sunday, calendar: calendar)
        #expect(worse.questions.contains(.suggestIntense(reportID: id)))
        #expect(InjuryCoach.questions(worse.state, now: sunday, calendar: calendar).contains(.suggestIntense(reportID: id)))
        let switched = CoachEngine.answerInjury(.suggestion(.switchToIntense), reportID: id, state: worse.state, runs: plan.runs, now: sunday, calendar: calendar)
        #expect(switched.state.injuries[0].level == .intense)
        #expect(switched.questions.contains(.medicalClearance(reportID: id)))
        #expect(switched.state.injuries[0].pendingSuggestion == nil)
    }

    /// AD-13g: a third report at one area within 6 months suggests a physio, once.
    @Test func thirdReportAtOneAreaSuggestsAPhysio() {
        var state = runningPlan().state
        for day in [5, 15] {
            var old = InjuryReport(reportedAt: CoachFixtures.day(day), origin: .planScreen, level: .mild, area: .knee, baseline: InjuryBaseline(volumeUnit: .distance, weekVolume: 16_000, longRun: Load(meters: 8_000, seconds: 0)))
            old.status = .closed(on: CoachFixtures.day(day + 7))
            state.injuries.append(old)
        }
        let physio = "This has been hanging around. A physio can often help with injuries like this."
        let third = InjuryCoach.report(level: .mild, area: .knee, origin: .planScreen, runID: nil, state: state, runs: [], now: CoachFixtures.day(29, hour: 9), calendar: calendar)
        #expect(third.notes.contains { $0.text == physio })
        #expect(third.state.injuries.last?.physioSuggested == true)
        let elsewhere = InjuryCoach.report(level: .mild, area: .back, origin: .planScreen, runID: nil, state: state, runs: [], now: CoachFixtures.day(29, hour: 9), calendar: calendar)
        #expect(!elsewhere.notes.contains { $0.text == physio })
    }

    /// TI-3b, TI-4: an Intense report puts the runner in the row for a score of 2 or more for 12 months: Gentle
    /// only, at most 3 runs a week, at most 1 Q. When the memory ends the caps come back and the level can rise.
    @Test func injuryMemoryLimitsThePlanForAYear() {
        let plan = runningPlan(runDays: [.monday, .tuesday, .thursday, .saturday, .sunday])
        #expect(plan.state.level == .steady)
        #expect(plan.state.assessment.runsCap == 4)
        let now = CoachFixtures.day(29, hour: 9)
        let intense = CoachEngine.reportInjury(level: .intense, area: nil, origin: .planScreen, runID: nil, state: plan.state, runs: plan.runs, now: now, calendar: calendar)
        let state = intense.state
        #expect(state.assessment.risk.factors.contains(.recentInjury))
        #expect(state.assessment.risk.isHigh)
        #expect(state.level == .gentle)
        #expect(state.levelChanges.last == LevelChange(date: now, from: .steady, to: .gentle))
        #expect(intense.notes.contains { $0.text == "Your plan builds at Gentle for now, because a recent injury makes another one more likely." })
        #expect(state.assessment.runsCap == 3)
        #expect(state.assessment.qCap <= 1)
        #expect(state.assessment.levels == LevelOptions(preset: .gentle, ceiling: .gentle, lockedReason: "you reported an injury in the last year"))
        #expect(InjuryCoach.qualityWaits(state, now: now, calendar: calendar))
        // CL-4: raising stays inside the ceiling.
        #expect(CoachEngine.changeLevel(.steady, state: state, runs: plan.runs, now: now, calendar: calendar).state.level == .gentle)

        var later = state
        let yearOn = CoachFixtures.day(29 + 370)
        later.injuries[0].status = .closed(on: CoachFixtures.day(90))
        #expect(InjuryCoach.applyRiskMemory(&later, now: yearOn, calendar: calendar).isEmpty)
        #expect(!later.assessment.risk.factors.contains(.recentInjury))
        #expect(later.assessment.runsCap == 4)
        #expect(later.assessment.levels.ceiling == .ambitious)
        #expect(later.level == .gentle)
        #expect(!InjuryCoach.qualityWaits(later, now: yearOn, calendar: calendar))
    }

    /// The plan's status follows the reports and the illness episode (AD-5 PAUSE).
    @Test func statusFollowsTheReports() {
        var (state, _) = examplePlan(level: .severe)
        let now = CoachFixtures.day(28)
        InjuryCoach.syncPause(&state, now: now)
        #expect(state.status == .paused(reason: .injury, since: now))
        state.injuries[0].readyAt = CoachFixtures.day(40)
        state.fatigue.level = 2
        InjuryCoach.syncPause(&state, now: CoachFixtures.day(40))
        #expect(state.status == .paused(reason: .fatigue, since: now))
        state.fatigue.level = 0
        state.status = .paused(reason: .injury, since: now)
        InjuryCoach.syncPause(&state, now: CoachFixtures.day(40))
        #expect(state.status == .active)
        state.status = .complete(on: now)
        state.injuries[0].readyAt = nil
        InjuryCoach.syncPause(&state, now: CoachFixtures.day(41))
        #expect(state.status == .complete(on: now))
    }

    /// AD-13a, AD-13b, AD-14c, AD-18: the ladder holds its step while Mild, stops in a pause or the rest phase, and
    /// climbs back after; the strictest report wins.
    @Test func ladderRuleTakesTheStrictestReport() {
        var (state, _) = examplePlan(level: .intense)
        #expect(InjuryCoach.ladderRule(state, week: 4, calendar: calendar) == .paused)
        state.injuries[0].clearance = .yes
        state.injuries[0].recoveryStart = CoachFixtures.day(28)
        #expect(InjuryCoach.ladderRule(state, week: 4, calendar: calendar) == .paused)
        #expect(InjuryCoach.ladderRule(state, week: 5, calendar: calendar) == .climbBack(toStep: nil, walkMinutes: nil))
        let mild = InjuryReport(reportedAt: CoachFixtures.day(30), origin: .planScreen, level: .mild, area: .knee, baseline: state.injuries[0].baseline)
        state.injuries.append(mild)
        #expect(InjuryCoach.ladderRule(state, week: 5, calendar: calendar) == .holdStep)
        state.injuries[0].status = .closed(on: CoachFixtures.day(60))
        state.injuries[1].status = .closed(on: CoachFixtures.day(60))
        #expect(InjuryCoach.ladderRule(state, week: 9, calendar: calendar) == nil)
    }

    /// TI-3b's area order, AD-14e's cross-training swaps and FB-4n's cadence cue.
    @Test func areasCrossTrainingAndCadence() {
        var (state, _) = examplePlan(level: .intense)
        state.injuries.append(InjuryReport(reportedAt: CoachFixtures.day(30), origin: .planScreen, level: .mild, area: .knee, baseline: state.injuries[0].baseline))
        #expect(InjuryCoach.rememberedAreas(state, now: CoachFixtures.day(60), calendar: calendar) == [.knee, .shin])
        #expect(InjuryCoach.rememberedAreas(state, now: CoachFixtures.day(130), calendar: calendar) == [.shin])
        #expect(InjuryCoach.rememberedAreas(state, now: CoachFixtures.day(400), calendar: calendar).isEmpty)

        #expect(InjuryCoach.crossTrainingSwaps(state) == .anyRun)
        state.injuries[0].status = .closed(on: CoachFixtures.day(50))
        #expect(InjuryCoach.crossTrainingSwaps(state) == .oneRunAWeek)

        #expect(InjuryCoach.cadenceCueOffered(state))
        state.injuries[1].events.append(InjuryEvent(date: CoachFixtures.day(37), kind: .mildCheck(.worse), week: 4))
        #expect(!InjuryCoach.cadenceCueOffered(state))
        state.injuries[1].events.removeLast()
        state.injuries.append(InjuryReport(reportedAt: CoachFixtures.day(40), origin: .planScreen, level: .mild, area: .thighHamstring, baseline: state.injuries[0].baseline))
        #expect(!InjuryCoach.cadenceCueOffered(state))
    }

    /// A repeated ramp week holds the next week's share; the 65+ hold keeps each step for a second week (AD-14b,
    /// AD-10).
    @Test func rampSharesRepeatAndHold() {
        #expect(InjuryCoach.rampShare(0, from: 0.5, step: 0.25) == 0.75)
        #expect(InjuryCoach.rampShare(1, from: 0.5, step: 0.25) == 1)
        #expect(InjuryCoach.rampShare(1, from: 0.5, step: 0.25, holds: [0]) == 0.75)
        #expect(InjuryCoach.rampShare(2, from: 0.5, step: 0.25, holds: [0]) == 1)
        #expect(InjuryCoach.rampShare(1, from: 0.3, step: 0.2, twoWeekHold: true) == 0.5)
        #expect(InjuryCoach.rampShare(2, from: 0.3, step: 0.2, twoWeekHold: true) == 0.7)
        #expect(InjuryCoach.rampShare(2, from: 0.3, step: 0.2, drops: [0]) == 0.5)
        #expect(InjuryCoach.rampShare(0, from: 0.5, step: nil) == 1)
    }
}
