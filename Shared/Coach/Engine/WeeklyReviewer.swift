//
//  WeeklyReviewer.swift
//  Wind Run
//

import Foundation

/// The week-end review: the signal families, the one outcome from the decision table, the fatigue clock,
/// calibration's re-base and the start of a return ramp (AD-4 to AD-7, AD-10, AD-17, RB-6, RB-7, TI-5).
enum WeeklyReviewer {
    /// What a finished week shows (AD-4).
    struct Signals: Hashable {
        var plannedVolume: Double
        var doneVolume: Double
        /// Done ÷ planned, extra runs counted up to the plan.
        var completion: Double
        var ratedRuns: Int
        var effortFlags: Int
        /// Easy runs rated 4 or more (AD-7's pace change).
        var easyRunsTooHard: Int
        var families: [SignalFamily]
        /// Days from the last qualifying run to the week's end (AD-5, AD-10).
        var daysOff: Int
        /// Share of the planned week lost to heat, travel or illness.
        var cutShare: Double
        /// A completed 7 days over 1.20 × W4max.
        var overWeeklyCap: Bool
        /// A run over 1.30 × P-L30 (AD-8).
        var largeSpike: Bool
        /// The weekly check-in is missing for this week and the one before (AD-17).
        var missedCheckIns: Bool
        var lifeStressWorse: Bool
        var loadJump: Bool
        var busy: Bool
        /// Extra runs left the week more than 10% over plan and trims couldn't fit it (AD-8).
        var overPlan: Bool
        /// A second down-step in a row for one Q type (FB-4g, PZ-7): the fatigue check.
        var secondDownStep: Bool
        /// FB-4l's higher heart rate at the same easy pace, or PZ-13's resting-HR flag: a note only, because nothing
        /// derived from heart rate is kept in the plan (PZ-13).
        var heartRateHigher: Bool

        func has(_ family: SignalFamily) -> Bool { families.contains(family) }
    }

    /// AD-5's completion bands.
    static let rampCompletion = 0.40
    static let holdCompletion = 0.70
    /// AD-5: ≥8 days without a qualifying run starts the return ramp.
    static let gapDays = 8

    // MARK: Review

    /// Reviews plan week `index` after it ends: records the review and moves the counters the next plan reads.
    /// A second call (a late check-in) starts again from the state the first review saw.
    static func review(week index: Int, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        guard let position = state.weeks.firstIndex(where: { $0.plan.index == index }) else { return CoachUpdate(state: state) }
        if let baseline = state.weeks[position].reviewBaseline {
            baseline.restore(into: &state)
            RunReviewer.restoreRunFacts(into: &state, week: index, since: baseline, paces: true)
        } else {
            state.weeks[position].reviewBaseline = PlanBaseline(state)
        }
        let record = state.weeks[position]
        let previous = state.weeks.last { $0.plan.index == index - 1 }
        let signals = self.signals(record, previous: previous, state: state, runs: runs, calendar: calendar)
        var notes: [CoachNote] = []
        var questions: [CoachQuestion] = []

        // Calibration's re-base (TI-5, AD-7).
        if record.plan.kind == .calibration {
            if signals.has(.user) {
                state.v0 = min(state.v0, max(signals.doneVolume, 0))
            }
            if index == Progression.calibrationWeeks - 1 + WeekPlanner.extraCalibrationWeeks(state) {
                let logged = state.weeks
                    .filter { $0.plan.kind == .calibration && $0.plan.index <= index }
                    .map { week -> Double in week.plan.index == index ? signals.doneVolume : (week.review?.doneVolume ?? 0) }
                state.v0 = LoadMetrics.rebasedV0(state.v0, loggedWeeks: logged)
            }
        }
        // AD-7: easy runs rated 4 or more in a "too hard" week move the easy band 15 s/km slower.
        if signals.has(.user), signals.easyRunsTooHard > 0, let easy = state.paces.easy {
            state.paces.easy = easy.shifted(by: 15)
            notes.append(CoachNote(.pace, "Your easy runs felt harder than easy, so your easy pace is now 15 s/km slower."))
        }

        var (outcome, reason) = decide(signals, record: record, previous: previous, state: state)

        // The fatigue clock (AD-6b): cuts that don't work escalate.
        if outcome == .stepBack || state.fatigue.level > 0 || state.fatigue.stepBacksInRow > 0 {
            (outcome, reason) = escalate(outcome, reason, signals: signals, state: &state, record: record)
        }
        if signals.families.isEmpty, outcome != .stepBack, outcome != .pause {
            state.fatigue = FatigueState()
        }
        if outcome == .pause, reason == .fatigueLevel2 {
            state.status = .paused(reason: .fatigue, since: now)
        }

        // The return ramp (AD-10), unless an injury sets the way back or the runner is on the ladder.
        if outcome == .returnRamp {
            state.gap = startRamp(daysOff: signals.daysOff, state: state, runs: runs, weekEnd: weekEnd(record.plan, calendar: calendar), now: now, calendar: calendar)
        } else if var ramp = state.gap, record.plan.kind == .ramp {
            let dropped = signals.has(.user) || morningHighDays(record.plan, state: state, calendar: calendar) >= 2
            if dropped {
                ramp.share = max(ramp.tier.firstWeekShare.lower, ramp.share - ramp.step)
                ramp.dropsInRow += 1
                if ramp.dropsInRow >= 2 { questions.append(.rampDrops) }
            } else {
                let holdsThisWeek = state.assessment.age >= 65 && ramp.weeksDone % 2 == 1
                if !holdsThisWeek { ramp.share = min(1, ramp.share + ramp.step) }
                ramp.dropsInRow = 0
            }
            ramp.weeksDone += 1
            let longReached = (record.plan.longRun?.amount(in: state.volumeUnit) ?? 0) >= ramp.referenceLongRun.amount(in: state.volumeUnit) * 0.999
            let volumeReached = record.plan.plannedVolume >= ramp.reference * 0.999
            if !dropped, volumeReached, longReached {
                state.gap = nil
                state.cycle.lastLoadingVolume = ramp.reference
                state.cycle.lastLoadingLongRun = ramp.referenceLongRun
                notes.append(CoachNote(.outcome, "You're back to where you were before the break, so your plan picks up from there."))
            } else {
                state.gap = ramp
            }
        }

        // Counters the next weeks read.
        if record.checkIn?.week == .tooEasy, state.openInjuries.isEmpty {
            state.cycle.tooEasyWeeks += 1
        } else {
            state.cycle.tooEasyWeeks = 0
        }
        // AD-6d: two "too easy" weeks in a row bring the next benchmark or retest forward; the rating itself never
        // speeds anything up (HL-28).
        if state.cycle.tooEasyWeeks == 2, state.quality.retestWeek == nil, state.ladder == nil || state.ladder?.form == .done {
            state.quality.retestWeek = index + 1
            notes.append(CoachNote(.outcome, "Glad it feels easy; most weeks should. I'll bring your next check run forward to see whether your paces should change."))
        }
        if state.cycle.tooEasyWeeks >= 4, !state.cycle.levelUpOffered, let next = state.level.higher, state.assessment.levels.allows(next) {
            state.cycle.levelUpOffered = true
            questions.append(.levelUp(next))
        }
        let qDone = record.plan.qualitySessions.filter { if case .done = $0.status { return true } else { return false } }.count
        switch outcome {
        case .progress where qDone >= 1:
            state.quality.cleanWeeksAtOneQ += 1
        case .stepBack, .ease, .pause, .recoveryPlan, .returnRamp:
            state.quality.cleanWeeksAtOneQ = 0
        default:
            break
        }
        if signals.lifeStressWorse, previous?.checkIn?.lifeStress == .worse {
            questions.append(.lighterWeek)
        }
        if signals.loadJump { applyLoadJump(record.checkIn, state: &state, now: now, calendar: calendar) }
        if signals.heartRateHigher, !signals.families.contains(.heartRate) {
            notes.append(CoachNote(.insight, "Your heart rate has been higher than usual for your pace. Feeling run down? An easy day may help."))
        }

        let note = CoachNote(.outcome, message(outcome, reason))
        let review = WeekReview(
            weekIndex: index,
            completion: signals.completion,
            doneVolume: signals.doneVolume,
            ratedRuns: signals.ratedRuns,
            negativeFamilies: signals.families,
            outcome: outcome,
            reason: reason,
            note: note
        )
        state.weeks[position].review = review
        return CoachUpdate(state: state, notes: notes, questions: questions)
    }

    // MARK: Signals (AD-4)

    static func weekEnd(_ week: PlannedWeek, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 7, to: week.start) ?? week.start
    }

    static func signals(_ record: WeekRecord, previous: WeekRecord?, state: CoachState, runs: [LoggedRun], calendar: Calendar) -> Signals {
        let week = record.plan
        let start = week.start
        let end = weekEnd(week, calendar: calendar)
        let unit = state.volumeUnit
        let pace = state.paces.easyPace
        let usable = RunDataGate.usableRuns(runs)
        let sessions = LoadMetrics.sessions(from: usable)
        let weekRuns = usable.filter { $0.start >= start && $0.start < end }
        let done = LoadMetrics.volume(from: start, to: end, sessions: sessions, unit: unit, pace: pace)
        let planned = week.plannedVolume
        let completion = planned > 0 ? min(1, done / planned) : 1

        // E: effort flags on planned sessions, leaving out hot and hilly runs and allowing 1 point after leg work.
        var flags = 0
        var easyTooHard = 0
        let doneSessions = Dictionary(
            state.weeks.flatMap(\.plan.sessions).compactMap { session -> (UUID, PlannedSession)? in
                if case .done(let runID) = session.status { return (runID, session) }
                return nil
            },
            uniquingKeysWith: { first, _ in first }
        )
        for run in weekRuns {
            guard let checkIn = run.checkIn else { continue }
            if checkIn.cutShort == .tired {
                flags += 1
                continue
            }
            // FB-3's "Tired" counts like a run cut short from tiredness, through the run signals below.
            if checkIn.cutShort == nil, checkIn.whatHappened == .tired { continue }
            guard let rpe = checkIn.rpe, let session = doneSessions[run.id], let line = session.effort.tooHardRPE else { continue }
            if (checkIn.heat ?? .cool) >= .warm || isHilly(run) { continue }
            let allowance = afterLegWork(run, state: state, calendar: calendar) ? 1 : 0
            if rpe >= line + allowance {
                flags += 1
                if session.effort == .easy { easyTooHard += 1 }
            }
        }

        // What the week's runs add (Applying AD-4, AD-8, FB-4g).
        let runSignals = RunReviewer.weekSignals(week: week.index, state: state, runs: runs, calendar: calendar)
        flags += runSignals.extraEffortFlags

        var families: [SignalFamily] = []
        let slowEasy = slowEasyRuns(weekRuns, runs: runs, sessions: doneSessions, weekStart: start)
        let slowQuality = qualitySlowTwice(runs: runs, sessions: doneSessions, weekStart: start, weekEnd: end)
        if flags >= 2 || slowEasy >= 3 || slowQuality || runSignals.secondDownStep { families.append(.effort) }
        let morningHigh = morningHighDays(week, state: state, calendar: calendar)
        if (record.checkIn?.worseWellnessItems ?? 0) >= 2 || morningHigh >= 2 { families.append(.wellness) }
        if record.checkIn?.week == .tooHard { families.append(.user) }
        if state.openInjuries.contains(where: { $0.level == .mild }) { families.append(.injury) }

        let usualEasy = week.sessions.filter { $0.kind == .easy }.map(\.target.seconds).filter { $0 > 0 }
        let usualEasySeconds = usualEasy.isEmpty ? nil : usualEasy.sorted()[usualEasy.count / 2]
        let daysOff = LoadMetrics.daysSinceQualifyingRun(at: end, sessions: sessions, usualEasySeconds: usualEasySeconds, calendar: calendar)
            ?? (calendar.dateComponents([.day], from: calendar.startOfDay(for: state.startDate), to: end).day ?? 0)

        // Heat, travel or illness cuts.
        var cut = 0.0
        for session in week.runs where !isDone(session) {
            let day = state.date(of: session, in: week, calendar: calendar)
            let ill = state.illnesses.contains { $0.reportedAt <= day && ($0.endedAt ?? .distantFuture) > day }
            let travelling = state.lifeEvents.contains { $0.kind == .travelling && $0.isActive(on: day, calendar: calendar) }
            let hot = state.readiness.contains { $0.sessionID == session.id && ($0.heat ?? .cool) >= .hot }
            if ill || travelling || hot { cut += session.target.amount(in: unit) }
        }
        for run in weekRuns where run.checkIn?.cutShort == .unwellInHeat || run.checkIn?.cutShort == .feltIll {
            if let session = doneSessions[run.id] {
                cut += max(0, session.target.amount(in: unit) - LoggedRunVolume.amount(run, unit: unit, pace: pace))
            }
        }

        let context = WeekPlanner.makeContext(week: week.index, state: state, runs: runs, now: end, calendar: calendar)
        let lastDay = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let rolling = LoadMetrics.maxRolling7Days(from: start, through: lastDay, sessions: sessions, unit: unit, pace: pace, calendar: calendar)
        let overCap = context.weekCap > 0 && rolling > context.weekCap * 1.000_1

        let seed = WeekPlanner.seed(for: state)
        let largeSpike = sessions.filter { $0.start >= start && $0.start < end }.contains { session in
            let longest = LoadMetrics.longest(before: session.start, sessions: sessions, seed: seed, calendar: calendar)
            let amount = unit == .time ? session.runningSeconds : session.volume(in: unit, pace: pace)
            let reference = longest.amount(in: unit)
            return reference > 0 && amount > 1.30 * reference
        }

        let busy = state.lifeEvents.contains { event in
            [.busy, .holiday, .bigLifeChange].contains(event.kind) && event.isActive(on: start, calendar: calendar)
        }

        return Signals(
            plannedVolume: planned,
            doneVolume: done,
            completion: completion,
            ratedRuns: weekRuns.filter { $0.rpe != nil }.count,
            effortFlags: flags,
            easyRunsTooHard: easyTooHard,
            families: families,
            daysOff: daysOff,
            cutShare: planned > 0 ? cut / planned : 0,
            overWeeklyCap: overCap,
            largeSpike: largeSpike,
            missedCheckIns: record.checkIn == nil && previous != nil && previous?.checkIn == nil && previous?.plan.kind != .paused,
            lifeStressWorse: record.checkIn?.lifeStress == .worse,
            loadJump: isLoadJump(record.checkIn, state: state),
            busy: busy,
            overPlan: runSignals.overPlan,
            secondDownStep: runSignals.secondDownStep,
            heartRateHigher: runSignals.heartRateNegative
        )
    }

    static func isDone(_ session: PlannedSession) -> Bool {
        if case .done = session.status { return true }
        return false
    }

    /// AD-4: easy runs this week that are ≥5% slower than the 4-week median of easy runs at the same RPE. Only
    /// like-for-like runs count: flat, in cool weather, and from the same source (treadmill with treadmill).
    static func slowEasyRuns(_ weekRuns: [LoggedRun], runs: [LoggedRun], sessions: [UUID: PlannedSession], weekStart: Date) -> Int {
        func comparable(_ run: LoggedRun) -> (rpe: Int, pace: Double, treadmill: Bool)? {
            guard sessions[run.id]?.kind == .easy, let rpe = run.checkIn?.rpe, (run.checkIn?.heat ?? .cool) == .cool,
                  run.meters > 0, run.movingSeconds > 0, isFlat(run) else { return nil }
            return (rpe, run.movingSeconds / run.meters * 1_000, run.source == .treadmill)
        }
        let monthBefore = weekStart.addingTimeInterval(-28 * 86_400)
        let earlier = runs.filter { $0.start >= monthBefore && $0.start < weekStart }.compactMap(comparable)
        return weekRuns.compactMap(comparable).filter { run in
            let paces = earlier.filter { $0.rpe == run.rpe && $0.treadmill == run.treadmill }.map(\.pace).sorted()
            guard paces.count >= 3 else { return false }
            return run.pace >= 1.05 * paces[paces.count / 2]
        }.count
    }

    /// AD-4: the last 2 Q sessions up to this week's end, the later one this week, each >3% slower than its
    /// target pace over the work steps. Only runs with step data (the guided session) count.
    static func qualitySlowTwice(runs: [LoggedRun], sessions: [UUID: PlannedSession], weekStart: Date, weekEnd: Date) -> Bool {
        let quality = runs
            .filter { $0.start < weekEnd && (sessions[$0.id]?.isQuality ?? false) && sessions[$0.id]?.kind != .test && sessions[$0.id]?.kind != .race }
            .filter { (($0.checkIn?.heat ?? .cool) == .cool) && !isHilly($0) }
            .compactMap { run -> (start: Date, slow: Bool)? in
                guard let band = sessions[run.id]?.paceBand, let steps = run.steps?.filter(\.isWork), !steps.isEmpty else { return nil }
                let meters = steps.reduce(0) { $0 + $1.meters }
                let seconds = steps.reduce(0) { $0 + $1.seconds }
                guard meters > 0 else { return nil }
                return (run.start, seconds / meters * 1_000 > 1.03 * (band.fast + band.slow) / 2)
            }
            .sorted { $0.start < $1.start }
            .suffix(2)
        return quality.count == 2 && quality.allSatisfy(\.slow) && (quality.last?.start ?? .distantPast) >= weekStart
    }

    /// Flat enough to compare paces: under 10 m of climb per km, or a treadmill. Manual runs have no pace.
    static func isFlat(_ run: LoggedRun) -> Bool {
        switch run.source {
        case .treadmill: return true
        case .manual: return false
        case .gps, .otherApp:
            guard let track = run.track, run.meters > 0 else { return false }
            return (track.climbFirstHalf + track.climbSecondHalf) / (run.meters / 1_000) < 10
        }
    }

    /// FB-2: a run whose halves differ by 20 m of climb or more gets no pace or effort comparison.
    static func isHilly(_ run: LoggedRun) -> Bool {
        guard let track = run.track else { return false }
        return abs(track.climbFirstHalf - track.climbSecondHalf) >= 20
    }

    /// RB-5, AD-4: a run within 48 h after leg strength work.
    static func afterLegWork(_ run: LoggedRun, state: CoachState, calendar: Calendar) -> Bool {
        let from = run.start.addingTimeInterval(-48 * 3_600)
        if state.otherSessions.contains(where: { $0.worksLegs && $0.date >= from && $0.date < run.start }) { return true }
        let runDay = Weekday(of: run.start, calendar: calendar)
        let routineDays = (state.intake.otherTraining ?? []).filter(\.isLegSession).flatMap(\.days)
        return routineDays.contains { $0 == runDay.adding(-1) || $0 == runDay.adding(-2) }
    }

    /// Days in the week with fatigue or soreness over 5 of 7 (AD-2).
    static func morningHighDays(_ week: PlannedWeek, state: CoachState, calendar: Calendar) -> Int {
        let end = weekEnd(week, calendar: calendar)
        let days = state.morningChecks
            .filter { $0.date >= week.start && $0.date < end && $0.isHigh }
            .map { calendar.startOfDay(for: $0.date) }
        return Set(days).count
    }

    /// RB-6: other training "more" or "new" with 2 or more extra hard sessions, a new hard activity,
    /// or non-running load (RPE × minutes) 30% over the routine.
    static func isLoadJump(_ checkIn: WeeklyCheckIn?, state: CoachState) -> Bool {
        guard let checkIn, checkIn.otherTraining == .more || checkIn.otherTraining == .new else { return false }
        let routine = state.intake.otherTraining ?? []
        let routineHard = routine.filter { $0.activityClass == .hard }.reduce(0) { $0 + $1.sessionsPerWeek }
        let routineLoad = routine.reduce(0.0) { $0 + Double($1.sessionsPerWeek) * $1.minutes * Double($1.effort) }
        let sessions = checkIn.otherSessions
        guard !sessions.isEmpty else { return false }
        let hard = sessions.filter { $0.activityClass == .hard }
        let load = sessions.reduce(0.0) { $0 + $1.minutes * Double($1.effort) }
        let newHardKind = hard.contains { session in !routine.contains { $0.kind == session.kind && $0.activityClass == .hard } }
        if checkIn.otherTraining == .new, !hard.isEmpty { return true }
        if hard.count >= routineHard + 2 || newHardKind { return true }
        return routineLoad > 0 && load >= 1.30 * routineLoad
    }

    /// RB-6's level drop: heavy-leg or vigorous training 3 or more times a week drops the level one step for 8 weeks.
    static func applyLoadJump(_ checkIn: WeeklyCheckIn?, state: inout CoachState, now: Date, calendar: Calendar) {
        let vigorous = (checkIn?.otherSessions ?? []).filter { $0.heavy || $0.activityClass == .hard }
        if vigorous.count >= 3 || checkIn?.otherTraining == .new {
            state.assessment.recovery.levelDropUntil = calendar.date(byAdding: .weekOfYear, value: 8, to: now)
        }
    }

    // MARK: The decision table (AD-5)

    /// The first matching row wins.
    static func decide(_ signals: Signals, record: WeekRecord, previous: WeekRecord?, state: CoachState) -> (WeekOutcome, OutcomeReason) {
        if let injury = InjuryCoach.outcome(state), injury.0 == .pause || injury.0 == .recoveryPlan { return injury }
        if let illness = IllnessCoach.outcome(state), illness.0 == .pause { return illness }
        if state.fatigue.level >= 2 { return (.pause, .fatigueLevel2) }

        // Ladder and walk-stage runners follow AD-18; a calibration week under 40% repeats (AD-10 new runners).
        let onLadder = state.ladder.map { $0.form != .done } ?? false
        let injuryWayBack = state.injuries.contains { $0.level >= .intense && !$0.status.isClosed }
        if !onLadder, !injuryWayBack, record.plan.kind != .paused {
            if signals.daysOff >= gapDays { return (.returnRamp, .gap) }
            if signals.completion < rampCompletion, record.plan.kind != .calibration { return (.returnRamp, .lowCompletion) }
        }

        let families = signals.families
        let previousOutcome = previous?.review?.outcome
        let effortTwice = signals.has(.effort) && (previous?.review?.negativeFamilies.contains(.effort) ?? false)
        if families.count >= 2, !(families.count == 2 && families.contains(.heartRate) && families.contains(.injury)) {
            return (.stepBack, .twoFamilies)
        }
        if signals.has(.user), previousOutcome == .ease { return (.stepBack, .tooHardAfterEase) }
        if effortTwice { return (.stepBack, .effortTwoWeeks) }
        if signals.secondDownStep { return (.stepBack, .sessionsTooHard) }

        if families == [.effort] { return (.ease, .effort) }
        if families == [.user] { return (.ease, .tooHard) }
        if families == [.heartRate] { return (.ease, .heartRate) }
        if let illness = IllnessCoach.outcome(state), illness.0 == .ease { return illness }

        if families == [.wellness] { return (.hold, .wellness) }
        if families == [.injury] { return (.hold, .mildInjury) }
        if let injury = InjuryCoach.outcome(state), injury.0 == .hold { return injury }
        if signals.completion < holdCompletion, record.plan.kind != .calibration { return (.hold, .lowCompletion) }
        if record.checkIn?.week == .hardButOK { return (.hold, .hardButOK) }
        if signals.lifeStressWorse { return (.hold, .lifeStress) }
        if signals.loadJump { return (.hold, .loadJump) }
        if signals.busy { return (.hold, .busy) }
        if signals.ratedRuns < 2, record.plan.kind != .calibration { return (.hold, .fewRatedRuns) }
        if signals.missedCheckIns { return (.hold, .missedCheckIns) }
        if signals.cutShare >= 0.2 { return (.hold, .weekCut) }
        if signals.overWeeklyCap { return (.hold, .overWeeklyCap) }
        if signals.largeSpike { return (.hold, .spike) }
        if signals.overPlan { return (.hold, .extraRuns) }
        if record.plan.kind == .calibration, record.plan.index < Progression.calibrationWeeks - 1 + WeekPlanner.extraCalibrationWeeks(state) {
            return (.hold, .calibration)
        }
        return (.progress, .progress)
    }

    /// AD-6b: STEP BACK twice, then Fatigue Level 1, then Level 2 (PAUSE). A week with no negative family ends it.
    static func escalate(_ outcome: WeekOutcome, _ reason: OutcomeReason, signals: Signals, state: inout CoachState, record: WeekRecord) -> (WeekOutcome, OutcomeReason) {
        let negative = !signals.families.isEmpty
        guard negative else {
            state.fatigue = FatigueState()
            return (outcome, reason)
        }
        if state.fatigue.level == 1 {
            state.fatigue.level = 2
            return (.pause, .fatigueLevel2)
        }
        if state.fatigue.stepBacksInRow >= 2 {
            state.fatigue.level = 1
            return (.stepBack, .fatigueLevel1)
        }
        if outcome == .stepBack {
            if state.fatigue.stepBacksInRow == 0 {
                state.fatigue.preCutVolume = record.plan.plannedVolume
            }
            state.fatigue.stepBacksInRow += 1
        }
        return (outcome, reason)
    }

    // MARK: The return ramp (AD-10)

    static func startRamp(daysOff: Int, state: CoachState, runs: [LoggedRun], weekEnd: Date, now: Date, calendar: Calendar) -> GapRamp {
        var tier = GapTier(daysOff: daysOff)
        // Bed-bound or feverish illness: at least G1 if ≤14 days, else one tier up.
        let bedBound = state.illnesses.contains { $0.bedBound || $0.kind == .feverOrBelowNeck }
        if bedBound {
            tier = daysOff <= 14 ? max(tier, .g1) : (GapTier(rawValue: min(GapTier.g4.rawValue, tier.rawValue + 1)) ?? tier)
        }
        if tier == .g0 { tier = .g1 }
        let sessions = LoadMetrics.sessions(from: RunDataGate.usableRuns(runs))
        let gapStart = LoadMetrics.lastQualifying(before: weekEnd, sessions: sessions, usualEasySeconds: nil)?.end
            ?? calendar.date(byAdding: .day, value: -daysOff, to: weekEnd) ?? weekEnd
        let reference = LoadMetrics.gapReference(
            gapStart: gapStart,
            planStart: state.startDate,
            sessions: sessions,
            unit: state.volumeUnit,
            pace: state.paces.easyPace,
            seed: WeekPlanner.seed(for: state),
            fallbackVolume: state.v0,
            fallbackLongest: state.assessment.start.planningLongest,
            calendar: calendar
        )
        let lowerBound = state.assessment.risk.isHigh || state.assessment.age >= 65
            || InjuryCoach.injuryWindowActive(state, now: now, calendar: calendar)
            || state.injuries.contains { $0.level == .severe }
        let share = lowerBound ? tier.firstWeekShare.lower : tier.firstWeekShare.normal
        return GapRamp(
            tier: tier,
            daysOff: daysOff,
            reference: reference.volume,
            referenceLongRun: reference.longest,
            share: share,
            step: tier.step,
            weeksDone: 0,
            dropsInRow: 0,
            startedAt: weekEnd
        )
    }

    // MARK: What the coach says (AD-5)

    static func message(_ outcome: WeekOutcome, _ reason: OutcomeReason) -> String {
        let because = reason.phrase
        switch outcome {
        case .progress:
            return "Good week. Because it felt about right, your plan takes its next step."
        case .hold:
            if reason == .fewRatedRuns { return "Rate two runs this week so I can move you forward." }
            return "Same targets as last week, because \(because). We'll step up once things settle."
        case .ease:
            return "Because \(because), this week is 10% lighter and your hardest session is an easy run."
        case .stepBack:
            if reason == .fatigueLevel1 {
                return "You've needed two lighter weeks and still feel worn down, so this week is easy running only, with at least two rest days."
            }
            return "Because \(because), this week is 25% lighter with no hard sessions, so your body can catch up."
        case .pause:
            if reason == .fatigueLevel2 {
                return "You've been worn down for three weeks, so let's pause your plan. A short easy run is fine if you feel like it. If the tiredness hangs around, it's worth checking with a doctor."
            }
            return "No running for now, because \(because). Your plan is paused, not lost. Tap 'Ready' when you want to start back."
        case .recoveryPlan:
            return "Your recovery plan sets your running for now, because \(because)."
        case .returnRamp:
            return "Welcome back. We'll ease in over the next few weeks, because \(because)."
        }
    }
}

/// A logged run's volume in a plan's unit.
enum LoggedRunVolume {
    static func amount(_ run: LoggedRun, unit: VolumeUnit, pace: Double?) -> Double {
        switch unit {
        case .distance:
            if run.meters > 0 { return run.meters }
            guard let pace, pace > 0 else { return 0 }
            return run.runningSeconds / pace * 1_000
        case .time:
            return run.runningSeconds
        }
    }
}
