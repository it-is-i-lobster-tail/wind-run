//
//  LadderTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// The walk stage, the short run-walk and the run-walk ladder to 30 minutes (TI-2, TI-6, BD-2, AD-18), and
/// Dana's worked example followed week by week.
@MainActor
struct LadderTests {
    let calendar = CoachFixtures.calendar
    let baseline = InjuryBaseline(volumeUnit: .time, weekVolume: 0, longRun: .zero)

    /// How a session of a week ended by `endWeek` went.
    enum Done {
        case rated(Int)
        case unrated
        case missed
    }

    /// Dana's plan, moved to `stepIndex` on the run-walk sequence when given.
    func danaState(stepIndex: Int? = nil, firstStepIndex: Int? = nil, intake: CoachIntake? = nil) -> CoachState {
        var state = CoachFixtures.start(intake ?? CoachFixtures.danaIntake())
        if let stepIndex {
            state.ladder = LadderState(form: .runWalk, stepIndex: stepIndex, firstStepIndex: firstStepIndex)
        }
        return state
    }

    /// The planning context for plan week `week`, at 07:00 on its first day unless `now` says otherwise.
    func context(_ week: Int, _ state: CoachState, runs: [LoggedRun] = [], now: Date? = nil) -> PlanningContext {
        let start = state.weekStart(week, calendar: calendar)
        return WeekPlanner.makeContext(week: week, state: state, runs: runs, now: now ?? CoachFixtures.day(0, from: start), calendar: calendar)
    }

    /// Plan week `index` with its sessions on Tue, Thu and Sat gone as `done` says, each lasting `seconds` (8 minutes
    /// of them walking on run-walk), then the ladder's week-end step.
    func endWeek(
        _ index: Int,
        _ state: CoachState,
        runs: [LoggedRun] = [],
        _ done: [Done],
        feel: WeekFeel? = .aboutRight,
        seconds: Double = 1_200
    ) -> (update: CoachUpdate, runs: [LoggedRun]) {
        var state = state
        var runs = runs
        let start = state.weekStart(index, calendar: calendar)
        let walking = state.ladder?.form == .walkStage
        var sessions: [PlannedSession] = []
        for (position, outcome) in done.enumerated() {
            let offset = [1, 3, 5][position % 3]
            var session = PlannedSession(dayOffset: offset, kind: walking ? .walk : .runWalk, target: Load(meters: 0, seconds: seconds), leadsWith: .time)
            let date = CoachFixtures.day(offset, from: start)
            var rpe: Int?
            switch outcome {
            case .missed:
                session.status = .missed
                sessions.append(session)
                continue
            case .rated(let value):
                rpe = value
            case .unrated:
                break
            }
            let run = LoggedRun(
                start: date,
                movingSeconds: seconds,
                meters: 2_000,
                plannedSessionID: session.id,
                checkIn: rpe.map { RunCheckIn(answeredAt: date.addingTimeInterval(seconds + 1_800), rpe: $0, talkTest: $0 <= 3, feel: .ok) },
                walkingSeconds: walking ? seconds : 480
            )
            runs.append(run)
            session.status = .done(runID: run.id)
            sessions.append(session)
        }
        let plan = PlannedWeek(index: index, start: start, kind: .ladder, volumeUnit: .time, plannedVolume: 2_160, sessions: sessions)
        let checkIn = feel.map {
            WeeklyCheckIn(answeredAt: CoachFixtures.day(6, hour: 20, from: start), week: $0, legs: .same, energy: .same, lifeStress: .same, motivation: .same, ill: false)
        }
        state.weeks.removeAll { $0.plan.index == index }
        state.weeks.append(WeekRecord(plan: plan, checkIn: checkIn))
        state.weeks.sort { $0.plan.index < $1.plan.index }
        let update = LadderCoach.weekEnded(index, state: state, runs: runs, now: CoachFixtures.day(7, from: start), calendar: calendar)
        return (update, runs)
    }

    // MARK: Entry and the first weeks

    /// TI-2, BD-2d: Dana walks briskly and has run under a minute, so she starts on the 1-minute step (NHS week 1)
    /// with no calibration, planned in running minutes. A BMI of 30 or more makes it the short run-walk, and no
    /// brisk 30-minute walk the walk stage.
    @Test func danaStartsOnTheOneMinuteStep() {
        let intake = CoachFixtures.danaIntake()
        let assessment = CoachEngine.assess(intake, now: CoachFixtures.day(0), calendar: calendar)
        #expect(assessment.tier == .starter)
        #expect(assessment.risk.points == 1)
        #expect(assessment.starterEntry == .ladder(step: RunWalkStep.ladderStart))
        #expect(assessment.start.volumeUnit == .time)
        #expect(!assessment.start.calibrates)

        var heavier = intake
        heavier.weightKilograms = 90
        #expect(CoachEngine.assess(heavier, now: CoachFixtures.day(0), calendar: calendar).starterEntry == .shortRunWalk)
        var walker = intake
        walker.walksBriskly30 = false
        #expect(CoachEngine.assess(walker, now: CoachFixtures.day(0), calendar: calendar).starterEntry == .walkStage(minutes: 10))

        #expect(LadderCoach.initialState(for: .walkStage(minutes: 10)).position == LadderPosition(form: .walkStage, stepIndex: 0, walkMinutes: 10))
        #expect(LadderCoach.initialState(for: .shortRunWalk).step == RunWalkStep.sequence[0])
        #expect(LadderCoach.initialState(for: .ladder(step: 12)).step.runSeconds == 900)
    }

    /// TI-2c, BD-2a: NHS week 1 is 8 one-minute runs, each but the last followed by an open walk break, on Tue,
    /// Thu and Sat. The week's volume is its running minutes, so HL-2 compares like with like.
    @Test func nhsWeekOne() throws {
        let state = CoachFixtures.start(CoachFixtures.danaIntake())
        let context = self.context(0, state)
        let week = try #require(LadderCoach.week(context))
        let layout = LadderCoach.layout(week, extras: [], context: context)
        #expect(layout.sessions.map(\.dayOffset) == [1, 3, 5])
        let run = SessionStep(kind: .work, goal: .time(seconds: 60), effort: .easy)
        let walk = SessionStep(kind: .recovery, goal: .open, effort: .easy, walk: true)
        for session in layout.sessions {
            #expect(session.kind == .runWalk)
            #expect(session.blocks == [SessionBlock(repeats: 7, steps: [run, walk]), SessionBlock(steps: [run])])
            #expect(LadderCoach.plannedRunning(session) == 480)
            #expect(session.target.seconds == 1_110)
        }
        #expect(layout.plannedVolume == 1_440)

        let targets = try #require(LadderCoach.weekTargets(context))
        #expect(targets.kind == .ladder)
        #expect(targets.volume == 1_440)
        #expect(targets.runs == 3)
        #expect(targets.form == .runWalk(runSeconds: 60, walkSeconds: nil))
        #expect(targets.notes.contains(CoachNote(.plan, "Slow enough to talk. Don't sprint the run parts.")))
        #expect(!targets.notes.contains { $0.topic == .limit })
    }

    /// TI-2b: the short run-walk repeats 15 s of running and 45 s of walking for 20 minutes.
    @Test func shortRunWalkSessions() throws {
        var intake = CoachFixtures.danaIntake()
        intake.weightKilograms = 90
        let state = CoachFixtures.start(intake)
        #expect(state.ladder?.position == LadderPosition(form: .runWalk, stepIndex: 0, walkMinutes: 0))
        let context = self.context(0, state)
        let week = try #require(LadderCoach.week(context))
        let layout = LadderCoach.layout(week, extras: [], context: context)
        let run = SessionStep(kind: .work, goal: .time(seconds: 15), effort: .easy)
        let walk = SessionStep(kind: .recovery, goal: .time(seconds: 45), effort: .easy, walk: true)
        #expect(layout.sessions.count == 3)
        for session in layout.sessions {
            #expect(session.blocks == [SessionBlock(repeats: 20, steps: [run, walk])])
            #expect(LadderCoach.plannedRunning(session) == 300)
            #expect(session.target.seconds == 1_200)
        }
        #expect(layout.plannedVolume == 900)
    }

    /// BD-2a: when a week's running would pass HL-2 (W4max + 10 min under 60 min a week), repeats are trimmed, never
    /// the segment. A 15-minute entrant who runs 45 minutes a week gets 54 minutes: 15 minutes and 3 more a session.
    @Test func weeklyCapTrimsRepeatsNotTheSegment() throws {
        var intake = CoachFixtures.danaIntake()
        intake.longestNonStop = .fifteenToTwentyNine
        intake.history = .underThreeMonths
        intake.lastFourWeeks = RecentRunning(runsPerWeek: 3, weeklyLow: .time(seconds: 2_700))
        let state = CoachFixtures.start(intake)
        #expect(state.ladder?.stepIndex == 12)
        let context = self.context(0, state)
        #expect(context.weekCap == 3_300)
        let week = try #require(LadderCoach.week(context))
        let layout = LadderCoach.layout(week, extras: [], context: context)
        #expect(layout.sessions.count == 3)
        for session in layout.sessions {
            #expect(session.blocks.first?.steps.first?.goal == .time(seconds: 900))
            #expect(LadderCoach.plannedRunning(session) == 1_080)
        }
        #expect(layout.plannedVolume == 3_240)
        #expect(layout.notes.contains(CoachNote(.limit, "This week holds 54 min of running, as much as your recent weeks allow, so your sessions have fewer repeats. Each run segment stays the same.")))
    }

    /// BD-2e: BMI ≥30 runs about 3 km in the first week (3 × 1 km), adds ≤10% a week by time to week 4 on the same
    /// step, then climbs at 2 weeks a step. A step whose segment doesn't fit 1 km gives way to one that does.
    @Test func bmiFirstWeeks() throws {
        var intake = CoachFixtures.danaIntake()
        intake.weightKilograms = 90
        let state = danaState(stepIndex: RunWalkStep.ladderStart, intake: intake)
        #expect(LadderCoach.bmiRule(state))
        let context = self.context(0, state)
        let week = try #require(LadderCoach.week(context))
        #expect(week.limit == .firstWeeks(week: 0))
        let layout = LadderCoach.layout(week, extras: [], context: context)
        #expect(layout.sessions.map(LadderCoach.plannedRunning) == [450, 450, 450])
        #expect(layout.plannedVolume == 1_350)
        #expect(layout.notes.contains(CoachNote(.limit, "Your first week keeps each session to about 1 km of running, about 3 km in all.")))

        // A 15-minute entrant starts at 6 minutes, the longest step inside 1 km at 7:30/km, and holds it 4 weeks.
        intake.longestNonStop = .fifteenToTwentyNine
        var entrant = CoachFixtures.start(intake)
        #expect(entrant.ladder?.stepIndex == 12)
        let first = try #require(LadderCoach.week(self.context(0, entrant)))
        #expect(first.position.stepIndex == 8)
        #expect(first.restart.reason == .firstWeeks)
        var (update, runs) = endWeek(0, entrant, [.rated(3), .rated(3), .rated(3)])
        entrant = update.state
        #expect(entrant.ladder?.stepIndex == 8)
        #expect(entrant.ladder?.firstStepIndex == 8)
        #expect(update.notes == [CoachNote(.outcome, "Good week. Your first four weeks stay at this step while your running time builds.")])
        let second = try #require(LadderCoach.week(self.context(1, entrant, runs: runs)))
        #expect(second.limit == .firstWeeks(week: 1))
        #expect(abs((second.runningCap ?? 0) - 2_376) < 0.5)
        for index in 1 ... 2 {
            (update, runs) = endWeek(index, entrant, runs: runs, [.rated(3), .rated(3), .rated(3)])
            entrant = update.state
            #expect(entrant.ladder?.stepIndex == 8, "week \(index + 1)")
        }
        (update, runs) = endWeek(3, entrant, runs: runs, [.rated(3), .rated(3), .rated(3)])
        #expect(update.state.ladder?.stepIndex == 9)
    }

    /// TI-2a, TI-6: walks start at the length the runner manages and grow 5 minutes a week; 30 brisk minutes on
    /// 3 days start the short run-walk.
    @Test func walkStage() throws {
        var intake = CoachFixtures.danaIntake()
        intake.walksBriskly30 = false
        var state = CoachFixtures.start(intake)
        #expect(state.ladder?.position == LadderPosition(form: .walkStage, stepIndex: 0, walkMinutes: 10))
        state = LadderCoach.setFirstWalk(minutes: 12, state: state)
        #expect(state.ladder?.walkMinutes == 12)
        #expect(state.ladder?.firstWalkMinutes == 12)

        let context = self.context(0, state)
        let week = try #require(LadderCoach.week(context))
        let layout = LadderCoach.layout(week, extras: [], context: context)
        #expect(layout.sessions.map(\.kind) == [.walk, .walk, .walk])
        #expect(layout.sessions.map(\.dayOffset) == [1, 3, 5])
        #expect(layout.sessions.allSatisfy { $0.target.seconds == 720 })
        #expect(layout.plannedVolume == 0)
        let targets = try #require(LadderCoach.weekTargets(context))
        #expect(targets.form == .walk)
        #expect(targets.volume == 0)
        #expect(targets.runs == 3)

        var (update, runs) = endWeek(0, state, [.unrated, .unrated, .missed], seconds: 720)
        #expect(update.state.ladder?.walkMinutes == 17)
        #expect(update.notes == [CoachNote(.outcome, "Good week. Next week your walks are 17 minutes.")])

        state = update.state
        state.ladder?.walkMinutes = 30
        (update, runs) = endWeek(1, state, runs: runs, [.unrated, .unrated, .unrated], seconds: 1_800)
        let ladder = try #require(update.state.ladder)
        #expect(ladder.position == LadderPosition(form: .runWalk, stepIndex: 0, walkMinutes: 30))
        #expect(ladder.firstStepIndex == 0)
        #expect(ladder.history.last?.reason == .startRunWalk)
        #expect(update.notes == [CoachNote(.milestone, "You walked briskly for 30 minutes on 3 days. Next week you start run-walk: 15 seconds of running, then 45 of walking.")])
        #expect(runs.count == 5)
    }

    // MARK: The step rule (BD-2b, BD-2c, AD-18)

    /// BD-2b and AD-18's hiccups at the week's end: up a step after ≥2 sessions at RPE ≤5; one hard session repeats
    /// the step, two or a "too hard" week go back one, never below the first step; nothing is made up.
    @Test func stepRule() {
        let state = danaState(stepIndex: 5, firstStepIndex: 4)
        let up = endWeek(0, state, [.rated(3), .rated(4), .missed]).update
        #expect(up.state.ladder?.stepIndex == 6)
        #expect(up.state.ladder?.history.last?.reason == .stepUp)
        #expect(up.notes == [CoachNote(.outcome, "Good week. Next week: 3 minutes of running at a time.")])
        // A week's end applies once, even when it is called again.
        #expect(LadderCoach.weekEnded(0, state: up.state, runs: [], now: CoachFixtures.day(8), calendar: calendar).state == up.state)

        let oneHard = endWeek(0, state, [.rated(6), .rated(3), .rated(3)]).update
        #expect(oneHard.state.ladder?.stepIndex == 5)
        #expect(oneHard.notes == [CoachNote(.outcome, "Same step next week, because one session felt hard. Nothing to make up.")])

        let twoHard = endWeek(0, state, [.rated(6), .rated(7), .rated(3)]).update
        #expect(twoHard.state.ladder?.stepIndex == 4)
        #expect(twoHard.state.ladder?.history.last?.reason == .hardSessions)
        #expect(twoHard.notes == [CoachNote(.outcome, "Next week goes back a step, to 1 minute of running at a time, because two sessions felt hard. Nothing to make up.")])

        let tooHard = endWeek(0, state, [.rated(4), .rated(4), .rated(4)], feel: .tooHard).update
        #expect(tooHard.state.ladder?.stepIndex == 4)
        #expect(tooHard.state.ladder?.history.last?.reason == .tooHard)

        let floor = endWeek(0, danaState(), [.rated(6), .rated(6), .rated(3)]).update
        #expect(floor.state.ladder?.stepIndex == RunWalkStep.ladderStart)
        #expect(floor.notes == [CoachNote(.outcome, "Same step next week, because two sessions felt hard. Nothing to make up.")])

        let oneSession = endWeek(0, state, [.rated(3), .missed, .missed]).update
        #expect(oneSession.state.ladder?.stepIndex == 5)
        #expect(oneSession.notes == [CoachNote(.outcome, "Same step next week, so you can do at least two sessions at it. Nothing to make up.")])

        let unrated = endWeek(0, state, [.unrated, .unrated, .rated(3)]).update
        #expect(unrated.state.ladder?.stepIndex == 5)
        #expect(unrated.notes == [CoachNote(.outcome, "Rate two runs this week so I can move you forward.")])
    }

    /// BD-2c: at Gentle every 3rd ladder step takes 2 weeks; at 65+ every step does.
    @Test func weeksPerStep() {
        var gentle = CoachFixtures.danaIntake()
        gentle.level = .gentle
        // The 3-minute step is the ladder's 3rd.
        let third = danaState(stepIndex: 6, intake: gentle)
        let once = endWeek(0, third, [.rated(3), .rated(3), .rated(3)])
        #expect(once.update.state.ladder?.stepIndex == 6)
        #expect(once.update.notes == [CoachNote(.outcome, "Good week. One more week at this step, then the next one.")])
        let twice = endWeek(1, once.update.state, runs: once.runs, [.rated(3), .rated(3), .rated(3)])
        #expect(twice.update.state.ladder?.stepIndex == 7)
        #expect(endWeek(0, danaState(stepIndex: 7, intake: gentle), [.rated(3), .rated(3), .rated(3)]).update.state.ladder?.stepIndex == 8)

        var older = CoachFixtures.danaIntake()
        older.birthYear = 1960
        #expect(endWeek(0, danaState(stepIndex: 7, intake: older), [.rated(3), .rated(3), .rated(3)]).update.state.ladder?.stepIndex == 7)
    }

    // MARK: Gaps and restarts (AD-18)

    /// AD-18's gap rows: 8-14 days without running go back a step, 15-28 days two, longer two until the runner
    /// picks where to restart; never below the runner's first step.
    @Test func gapRows() throws {
        let state = danaState(stepIndex: 8, firstStepIndex: 4)
        let runs = [LoggedRun(start: CoachFixtures.day(1), movingSeconds: 1_200, meters: 2_000, walkingSeconds: 480)]
        func planned(_ week: Int, on day: Int, _ state: CoachState) -> LadderCoach.Week? {
            LadderCoach.week(context(week, state, runs: runs, now: CoachFixtures.day(day)))
        }
        #expect(planned(1, on: 7, state)?.position.stepIndex == 8)
        let tenDays = try #require(planned(1, on: 11, state))
        #expect(tenDays.position.stepIndex == 7)
        #expect(tenDays.restart.reason == .gap)
        #expect(tenDays.restart.gap?.days == 10)
        let note = LadderCoach.notes(tenDays, context: context(1, state, runs: runs, now: CoachFixtures.day(11))).first
        #expect(note == CoachNote(.plan, "Welcome back. After 10 days off, this week restarts one step back, with 4.5 minutes of running at a time. Nothing to catch up."))
        #expect(planned(3, on: 21, state)?.position.stepIndex == 6)
        #expect(planned(3, on: 21, danaState(stepIndex: 5, firstStepIndex: 4))?.position.stepIndex == 4)

        let now = CoachFixtures.day(42)
        let longGap = try #require(planned(6, on: 42, state))
        #expect(longGap.restart.gap?.tier == 3)
        #expect(longGap.position.stepIndex == 6)
        #expect(LadderCoach.questions(state, runs: runs, now: now, calendar: calendar).first == .ladderRestartWhere)
        #expect(LadderCoach.restartOptions(state).map(\.stepIndex) == [4, 5, 6, 7, 8])
        let picked = LadderCoach.restart(at: LadderPosition(form: .runWalk, stepIndex: 5, walkMinutes: 0), state: state, runs: runs, now: now, calendar: calendar)
        #expect(picked.state.ladder?.stepIndex == 5)
        #expect(picked.state.ladder?.history.last?.reason == .chosenRestart)
        #expect(picked.notes == [CoachNote(.plan, "Done: you'll restart with 2 minutes of running at a time. Nothing to catch up.")])
        #expect(LadderCoach.questions(picked.state, runs: runs, now: now, calendar: calendar).isEmpty)
        #expect(planned(6, on: 42, picked.state)?.restart.reason == nil)
        #expect(planned(7, on: 49, picked.state)?.position.stepIndex == 5)
    }

    /// AD-18 through the engine: three weeks without running, then back on day 33. The week restarts two steps
    /// back once, and the ladder climbs from there.
    @Test func gapRestartAppliesOnce() throws {
        let skip: (Int, Int) -> Bool = { week, day in week == 2 || week == 3 || (week == 4 && day != 5) }
        let back = CoachFixtures.followLadder(CoachFixtures.start(CoachFixtures.danaIntake()), days: 36, skip: skip)
        let ladder = try #require(back.state.ladder)
        #expect(ladder.stepIndex == RunWalkStep.ladderStart)
        #expect(ladder.history.filter { $0.reason == .gap }.count == 1)
        #expect(ladder.handledGap == LadderGapMark(lastRunDay: CoachFixtures.day(12, hour: 0), tier: 2))
        let week = try #require(back.state.weeks.first { $0.plan.index == 4 }?.plan)
        #expect(week.notes.contains { $0.text.hasPrefix("Welcome back.") && $0.text.contains("two steps back, with 1 minute of running at a time") })

        let after = CoachFixtures.followLadder(back.state, runs: back.runs, days: 7, from: 36)
        #expect(after.state.ladder?.stepIndex == RunWalkStep.ladderStart + 1)
        #expect(after.state.ladder?.history.filter { $0.reason == .gap }.count == 1)
    }

    /// AD-18: two missed sessions in a row offer an easier restart, one step back, never forced.
    @Test func missedSessionsOfferAnEasierRestart() {
        let simulation = CoachFixtures.followLadder(CoachFixtures.start(CoachFixtures.danaIntake()), days: 12, skip: { week, _ in week == 1 })
        let saturday = CoachFixtures.day(12)
        let refreshed = CoachEngine.refresh(state: simulation.state, runs: simulation.runs, now: saturday, calendar: calendar)
        #expect(refreshed.state.ladder?.stepIndex == 5)
        #expect(refreshed.questions.contains(.ladderEasierRestart))

        let accepted = CoachEngine.answer(.ladderEasierRestart(true), state: refreshed.state, runs: simulation.runs, now: saturday, calendar: calendar).0
        #expect(accepted.state.ladder?.stepIndex == 4)
        #expect(accepted.state.ladder?.history.last?.reason == .easierRestart)
        #expect(accepted.notes.contains(CoachNote(.plan, "Done: you'll restart with 1 minute of running at a time. Nothing to catch up.")))
        #expect(!accepted.questions.contains(.ladderEasierRestart))

        // "Not now" keeps the step, and the next missed session doesn't ask again.
        let declined = LadderCoach.easierRestartDeclined(state: refreshed.state, runs: simulation.runs, now: saturday, calendar: calendar)
        #expect(declined.ladder?.stepIndex == 5)
        #expect(LadderCoach.questions(declined, runs: simulation.runs, now: saturday, calendar: calendar).isEmpty)
        let sunday = CoachEngine.refresh(state: declined, runs: simulation.runs, now: CoachFixtures.day(13), calendar: calendar)
        #expect(!sunday.questions.contains(.ladderEasierRestart))
    }

    /// AD-18: two idle weeks offer a one-tap restart one step back. It counts as the gap row's restart, so the week
    /// doesn't go back again; once the gap row goes back further, the restart takes that.
    @Test func idleRestartCountsAsTheGapRow() {
        let state = danaState(stepIndex: 8, firstStepIndex: 4)
        let runs = [LoggedRun(start: CoachFixtures.day(5), movingSeconds: 1_200, meters: 2_000, walkingSeconds: 480)]
        let now = CoachFixtures.day(19)
        #expect(LadderCoach.questions(state, runs: runs, now: CoachFixtures.day(18), calendar: calendar).isEmpty)
        #expect(LadderCoach.questions(state, runs: runs, now: now, calendar: calendar) == [.ladderIdleRestart])
        let update = LadderCoach.restartEasier(state: state, runs: runs, now: now, calendar: calendar)
        #expect(update.state.ladder?.stepIndex == 7)
        #expect(LadderCoach.questions(update.state, runs: runs, now: now, calendar: calendar).isEmpty)
        #expect(LadderCoach.week(context(2, update.state, runs: runs, now: now))?.position.stepIndex == 7)

        let later = LadderCoach.restartEasier(state: state, runs: runs, now: CoachFixtures.day(21), calendar: calendar)
        #expect(later.state.ladder?.stepIndex == 6)
    }

    /// AD-18: an unplanned run counts for the week, the next day is rest and the next session the shortest; the step
    /// doesn't move.
    @Test func unplannedRunMakesRoom() throws {
        let simulation = CoachFixtures.followLadder(CoachFixtures.start(CoachFixtures.danaIntake()), days: 9)
        var runs = simulation.runs
        let extra = LoggedRun(start: CoachFixtures.day(9, hour: 18), movingSeconds: 2_100, meters: 4_000, walkingSeconds: 600)
        runs.append(extra)
        let now = CoachFixtures.day(9, hour: 19)
        let (update, review) = CoachEngine.logRun(extra, state: simulation.state, runs: runs, now: now, calendar: calendar)
        #expect(review.match == .extra)
        let note = CoachNote(.plan, "That extra run counts toward your week. Take tomorrow off, and your next session is a shorter one. Nothing else changes.")
        #expect(update.notes.contains(note))

        let context = self.context(1, update.state, runs: runs, now: now)
        let week = try #require(LadderCoach.week(context))
        #expect(week.trigger == extra)
        #expect(week.position.stepIndex == RunWalkStep.ladderStart + 1)
        let layout = LadderCoach.layout(week, extras: [], context: context)
        #expect(layout.sessions.map(\.dayOffset) == [1, 5])
        let saturday = try #require(layout.sessions.last)
        #expect(saturday.notes.contains("A shorter session today, after your extra running."))
        #expect(saturday.target.seconds <= RunWalkStep.shortestLadderSession)
        #expect(layout.notes.contains(CoachNote(.plan, "The day after your extra running is a rest day, so this week has 2 sessions.")))

        #expect(LadderCoach.questions(update.state, runs: runs, now: CoachFixtures.day(10), calendar: calendar).contains(.morningCheck(runID: extra.id)))
        let again = CoachEngine.logRun(extra, state: update.state, runs: runs, now: now, calendar: calendar).0
        #expect(!again.notes.contains(note))
    }

    /// AD-18, BD-2f: a non-stop segment past the step's is handled like an unplanned run, and the ladder still moves
    /// one step at a time.
    @Test func longerSegmentDoesNotSkipSteps() throws {
        let simulation = CoachFixtures.followLadder(CoachFixtures.start(CoachFixtures.danaIntake()), days: 8)
        let tuesday = CoachFixtures.day(8)
        let session = try #require(CoachEngine.todaysSessions(simulation.state, now: tuesday, calendar: calendar).first { $0.kind == .runWalk })
        var run = CoachFixtures.ladderRun(for: session, on: tuesday)
        run.track = TrackSummary(longestNonStopSeconds: 360)
        var runs = simulation.runs
        runs.append(run)
        let update = CoachEngine.logRun(run, state: simulation.state, runs: runs, now: CoachFixtures.day(8, hour: 9), calendar: calendar).0
        #expect(update.notes.contains(CoachNote(.plan, "You ran 6 min without stopping. Nice! Take tomorrow off, and your next session is a shorter one. The ladder still moves one step at a time.")))
        #expect(update.state.ladder?.stepIndex == RunWalkStep.ladderStart + 1)
        #expect(LadderCoach.isTrigger(run, state: update.state, calendar: calendar))
    }

    // MARK: Injuries and illness on the ladder (BD-2f, item 9)

    /// AD-13a: a Mild report repeats the step until it closes.
    @Test func mildInjuryHoldsTheStep() throws {
        var state = danaState(stepIndex: 6, firstStepIndex: 4)
        state.injuries = [InjuryReport(reportedAt: CoachFixtures.day(2), origin: .planScreen, level: .mild, baseline: baseline)]
        let context = self.context(0, state, now: CoachFixtures.day(2, hour: 8))
        let week = try #require(LadderCoach.week(context))
        #expect(week.mildInjury)
        #expect(week.position.stepIndex == 6)
        #expect(LadderCoach.plansInjuryWeek(context))
        let targets = try #require(LadderCoach.weekTargets(context))
        #expect(targets.notes.contains(CoachNote(.injury, "This week repeats your step because of your injury. It stays until the injury clears.")))

        let held = endWeek(0, state, [.rated(3), .rated(3), .rated(3)]).update
        #expect(held.state.ladder?.stepIndex == 6)
        #expect(held.notes == [CoachNote(.injury, "Same step next week, because of your injury.")])

        state.injuries[0].status = .closed(on: CoachFixtures.day(5))
        #expect(endWeek(0, state, [.rated(3), .rated(3), .rated(3)]).update.state.ladder?.stepIndex == 7)
    }

    /// AD-13b: after Intense's week of rest the runner restarts 2 steps below the pre-injury step, or as many as they
    /// pick, and the recovery plan ends back on that step.
    @Test func intenseRestartsTwoStepsBack() throws {
        var state = danaState(stepIndex: 8, firstStepIndex: 4)
        var report = InjuryReport(reportedAt: CoachFixtures.day(2), origin: .planScreen, level: .intense, baseline: baseline)
        report.clearance = .yes
        report.recoveryPlan = .standard
        report.recoveryStart = CoachFixtures.day(2)
        report.events.append(InjuryEvent(date: CoachFixtures.day(2), kind: .clearance(.yes)))
        state.injuries = [report]
        let ladder = try #require(state.ladder)
        let threeMinutes = LadderPosition(form: .runWalk, stepIndex: 6, walkMinutes: 0)
        #expect(LadderCoach.injuryPhase(report, ladder: ladder, on: CoachFixtures.day(8), calendar: calendar) == .paused)
        #expect(LadderCoach.injuryPhase(report, ladder: ladder, on: CoachFixtures.day(9), calendar: calendar) == .restart(threeMinutes, holdsUntil: nil))
        #expect(!LadderCoach.plansInjuryWeek(context(1, state, now: CoachFixtures.day(8))))

        let restart = try #require(LadderCoach.week(context(1, state, now: CoachFixtures.day(9))))
        #expect(restart.position == threeMinutes)
        #expect(restart.restart.reason == .injury)
        #expect(LadderCoach.injuryRestartOptions(for: report.id, state: state).map(\.stepIndex) == [4, 5, 6, 7, 8])
        #expect(LadderCoach.injuryRestart(for: report.id, state: state, now: CoachFixtures.day(9), calendar: calendar) == threeMinutes)

        let first = endWeek(1, state, [.missed, .rated(3), .rated(3)])
        let climbing = try #require(first.update.state.ladder)
        #expect(climbing.handledInjuries == [report.id])
        #expect(climbing.history.map(\.reason) == [.injury, .stepUp])
        #expect(climbing.stepIndex == 7)
        #expect(!LadderCoach.backToPreInjuryStep(report, state: first.update.state))
        let second = endWeek(2, first.update.state, runs: first.runs, [.rated(3), .rated(3), .rated(3)])
        #expect(second.update.state.ladder?.stepIndex == 8)
        #expect(LadderCoach.backToPreInjuryStep(report, state: second.update.state))

        let none = LadderCoach.setInjuryRestart(stepsBack: 0, reportID: report.id, state: state)
        #expect(LadderCoach.week(context(1, none, now: CoachFixtures.day(9)))?.position.stepIndex == 8)
    }

    /// AD-13c, AD-14c: after a Severe pause, "Ready" sets the step by AD-18's gap rows (11 days without running, one
    /// step back), and the step holds through the 2 return weeks.
    @Test func severeReturnHoldsTheStep() throws {
        var state = danaState(stepIndex: 8, firstStepIndex: 4)
        var report = InjuryReport(reportedAt: CoachFixtures.day(2), origin: .planScreen, level: .severe, baseline: baseline)
        report.pauseStart = CoachFixtures.day(2)
        report.lastRunBeforePause = CoachFixtures.day(1)
        report.readyAt = CoachFixtures.day(12)
        state.injuries = [report]
        let week = try #require(LadderCoach.week(context(1, state, now: CoachFixtures.day(12))))
        #expect(week.position.stepIndex == 7)
        #expect(week.restart.reason == .injury)

        let held = endWeek(2, state, [.rated(3), .rated(3), .rated(3)])
        #expect(held.update.state.ladder?.stepIndex == 7)
        #expect(held.update.notes == [CoachNote(.injury, "Same step next week, because you're in your return weeks.")])
        let climbing = endWeek(3, held.update.state, runs: held.runs, [.rated(3), .rated(3), .rated(3)])
        #expect(climbing.update.state.ladder?.stepIndex == 8)
    }

    /// AD-12, BD-2f: a cold without fever keeps easy sessions and holds the step; the first run back after an
    /// illness is one short session.
    @Test func illnessOnTheLadder() throws {
        var state = danaState(stepIndex: 6, firstStepIndex: 4)
        state.illnesses = [IllnessEpisode(reportedAt: CoachFixtures.day(2), kind: .headCold)]
        let context = self.context(0, state, now: CoachFixtures.day(2, hour: 8))
        let week = try #require(LadderCoach.week(context))
        #expect(week.illness == .headCold)
        #expect(week.sessions == 3)
        #expect(LadderCoach.plansIllnessWeek(context))
        let targets = try #require(LadderCoach.weekTargets(context))
        #expect(targets.notes.contains(CoachNote(.illness, "Easy sessions while you have a cold, and your step stays the same this week.")))
        let held = endWeek(0, state, [.rated(3), .rated(3), .rated(3)]).update
        #expect(held.state.ladder?.stepIndex == 6)
        #expect(held.notes == [CoachNote(.illness, "Same step next week, because of your cold.")])

        state.illnesses[0].stage = .firstRun
        let firstRun = try #require(LadderCoach.week(self.context(0, state)))
        #expect(firstRun.sessions == 1)
        #expect(firstRun.sessionSeconds == RunWalkStep.shortestLadderSession)
        #expect(LadderCoach.layout(firstRun, extras: [], context: self.context(0, state)).sessions.count == 1)
    }

    // MARK: The top of the ladder

    /// HL-11: strides once a week from the 20-minute step.
    @Test func stridesFromTwentyMinutes() throws {
        let twenty = danaState(stepIndex: 13)
        let week = try #require(LadderCoach.week(context(0, twenty)))
        #expect(week.strides)
        #expect(LadderCoach.layout(week, extras: [], context: context(0, twenty)).sessions.map(\.strides) == [4, 0, 0])
        #expect(LadderCoach.week(context(0, danaState(stepIndex: 12)))?.strides == false)
    }

    /// BD-2a, HL-2: 30 minutes non-stop has no repeats to trim, so a small W4max holds fewer runs instead.
    @Test func thirtyMinuteStepHoldsFewerSessions() throws {
        var state = danaState(stepIndex: RunWalkStep.lastIndex)
        state.v0 = 3_420
        let context = self.context(0, state)
        let week = try #require(LadderCoach.week(context))
        #expect(week.sessions == 2)
        #expect(week.fewerSessions)
        let layout = LadderCoach.layout(week, extras: [], context: context)
        #expect(layout.sessions.map(\.kind) == [.easy, .easy])
        #expect(layout.plannedVolume == 3_600)
        let targets = try #require(LadderCoach.weekTargets(context))
        #expect(targets.form == .continuous)
        #expect(targets.notes.contains(CoachNote(.limit, "This week has 2 runs of 30 minutes, as much running as your recent weeks allow.")))
    }

    // MARK: Dana's worked example

    /// Dana from 1 minute to 30 minutes non-stop, week by week: one step a week, the 6-minute step repeated after
    /// Thursday's RPE 6 in week 5, and 30 minutes at RPE 5 in week 13 hands her to the cycle as a Novice. Each week
    /// holds the running BD-2a's sessions allow inside HL-2 (W4max + 10 min under 60 min a week, then 1.20 × W4max).
    @Test func danaClimbsTheLadder() throws {
        let simulation = CoachFixtures.followLadder(CoachFixtures.start(CoachFixtures.danaIntake()), days: 7 * 13 + 1, rpe: { week, day in
            if week == 4, day == 3 { return 6 }
            if week == 12, day == 1 { return 5 }
            return 3
        })
        let dana = simulation.state
        let sessions = LoadMetrics.sessions(from: simulation.runs)
        let steps: [Double] = [1, 2, 3, 4.5, 6, 6, 8, 10, 12, 15, 20, 25, 30]
        let running: [Double] = [24, 33, 36, 43.5, 51, 58.5, 66, 66, 78, 85.5, 85.5, 85.5, 90]
        for index in steps.indices {
            let start = dana.weekStart(index, calendar: calendar)
            let end = dana.weekStart(index + 1, calendar: calendar)
            let record = try #require(dana.weeks.first { $0.plan.index == index })
            #expect(record.plan.kind == .ladder, "week \(index + 1) is \(record.plan.kind)")
            let weekRuns = simulation.runs.filter { $0.start >= start && $0.start < end }
            #expect(weekRuns.count == 3, "week \(index + 1) has \(weekRuns.count) runs")
            let longest = weekRuns.compactMap { $0.track?.longestNonStopSeconds }.max() ?? 0
            #expect(longest == steps[index] * 60, "week \(index + 1) runs \(longest) s non-stop")
            let done = LoadMetrics.doneVolume(week: index, planStart: dana.startDate, sessions: sessions, unit: .time, pace: nil, calendar: calendar)
            #expect(abs(done - running[index] * 60) < 0.5, "week \(index + 1) holds \(done / 60) min of running")
        }
        let ladder = try #require(dana.ladder)
        #expect(ladder.form == .done)
        #expect(ladder.history.filter { $0.reason == .stepUp }.count == 11)
        #expect(ladder.finishedOn == CoachFixtures.day(85))
        #expect(dana.assessment.tier == .novice)
        #expect(dana.assessment.runs30Minutes)
        #expect(dana.assessment.start.sustainedRunLength == 1_800)
        #expect(dana.v0 == 5_400)
        let next = try #require(dana.weeks.first { $0.plan.index == 13 }?.plan)
        #expect(next.kind == .loading)
        #expect(next.cycleWeek == .newLongest)
    }
}
