//
//  WeekPlanner.swift
//  Wind Run
//

import Foundation

/// Plans each week inside the safe zone: the rule modules first (injury, illness, the ladder, gaps,
/// the race), then calibration and the level's cycle, then the hard limits, then the layout
/// (CL-1, CL-2, TI-5, HL-1 to HL-14, BD-3, SW-3, EV-1, EV-6, AD-5, AD-6a, AD-10).
enum WeekPlanner {
    // MARK: Context

    static func seed(for state: CoachState) -> LoadSeed {
        LoadSeed(
            date: state.startDate,
            longest: state.assessment.start.planningLongest,
            reportedLongest: state.assessment.start.reportedLongest,
            weeklyVolume: state.v0
        )
    }

    static func makeContext(week index: Int, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> PlanningContext {
        // Duplicates and runs under 500 m or over 100 km don't count (FB-2).
        let sessions = LoadMetrics.sessions(from: RunDataGate.usableRuns(runs))
        let start = state.weekStart(index, calendar: calendar)
        let seed = seed(for: state)
        let unit = state.volumeUnit
        let pace = state.paces.easyPace
        let ramp = state.gap
        let longest = LoadMetrics.longest(
            before: start,
            sessions: sessions,
            seed: seed,
            countFrom: ramp?.startedAt,
            ceiling: ramp.map(\.referenceLongRun),
            capOnly: raceRunIDs(state),
            calendar: calendar
        )
        let w4max = LoadMetrics.w4max(week: index, planStart: state.startDate, sessions: sessions, unit: unit, pace: pace, seed: seed, calendar: calendar)
        var cap = LoadMetrics.weekCap(w4max: w4max, unit: unit)
        // HL-2's small-week allowance, at the slow fallback pace when there's no easy pace, so the cap is never 0.
        let allowancePace = pace ?? Scheduler.fallbackEasyPace
        if unit == .distance, w4max / 1_000 * allowancePace < CoachLimits.smallWeekSeconds {
            cap = max(cap, w4max + CoachLimits.smallWeekAllowanceSeconds / allowancePace * 1_000)
        }
        // AD-10: the first week back after a gap restarts at its tier's share of the weeks before it. With no
        // running in the last 4 weeks HL-2 has nothing to compare that week with, so the share sets its cap;
        // from the next week W4max holds the return week. Any running in those weeks keeps HL-2's cap.
        if let ramp, ramp.weeksDone == 0, w4max <= 0 {
            cap = max(cap, ramp.reference * ramp.share)
        }
        var context = PlanningContext(
            state: state,
            runs: runs,
            sessions: sessions,
            weekIndex: index,
            weekStart: start,
            longest: longest,
            w4max: w4max,
            weekCap: cap,
            now: now,
            calendar: calendar
        )
        // The same for the first running week of an injury recovery plan or a Severe return (AD-14b, AD-14c).
        if w4max <= 0, let restart = InjuryCoach.restartVolume(context) { context.weekCap = max(context.weekCap, restart) }
        return context
    }

    /// Runs on race day never raise P-L30 (HL-1, EV-9).
    static func raceRunIDs(_ state: CoachState) -> Set<UUID> {
        var ids = Set<UUID>()
        for record in state.weeks {
            for session in record.plan.sessions where session.kind == .race {
                if case .done(let runID) = session.status { ids.insert(runID) }
            }
        }
        return ids
    }

    // MARK: Planning a week

    /// Plans week `index` and returns the state with the week recorded and the cycle moved on.
    static func planWeek(_ index: Int, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachState {
        var state = state
        // A re-plan starts again from the state this week was first planned from.
        let baseline: PlanBaseline
        if let existing = state.weeks.first(where: { $0.plan.index == index })?.planBaseline {
            baseline = existing
            baseline.restorePlanning(into: &state)
            RunReviewer.restoreRunFacts(into: &state, week: index, since: baseline, paces: false)
        } else {
            baseline = PlanBaseline(state)
        }
        let context = makeContext(week: index, state: state, runs: runs, now: now, calendar: calendar)
        var (targets, cycle) = weekTargets(context)
        RunReviewer.shape(&targets, context: context)
        SpeedWorkPlanner.advance(&state, targets: &targets, context: context)
        CheckPlanner.addCheck(&targets, context: context)
        CheckPlanner.track(&state, targets: targets, index: index)
        targets = applyLimits(targets, context: context)
        if state.assessment.age >= 65, targets.kind != .paused, !targets.extras.contains(.strength) {
            targets.extras += [.strength, .strength]
        }
        let layout = Scheduler.layout(targets, context: context)
        var notes = targets.notes + layout.notes

        // The cycle records what was actually planned.
        if targets.kind == .loading || targets.kind == .hold {
            cycle.lastLoadingVolume = layout.plannedVolume
            if let longRun = layout.longRun { cycle.lastLoadingLongRun = longRun }
        }
        if let long = layout.sessions.first(where: { $0.kind == .long }), long.isNewLongest {
            cycle.lastNewLongest = calendar.date(byAdding: .day, value: long.dayOffset, to: context.weekStart)
        }
        state.cycle = cycle

        if index == 0, !state.shownOnce.contains("safetyLine") {
            state.shownOnce.insert("safetyLine")
        }
        notes = notes.reduce(into: []) { result, note in if !result.contains(note) { result.append(note) } }

        var laidOut = layout.sessions
        let reviewNotes = RunReviewer.finish(&laidOut, context: context)
        notes += reviewNotes.filter { !notes.contains($0) }
        let sessions = stableIDs(firstWeekSessions(laidOut, context: context), week: index, state: state)
        var plannedVolume = layout.plannedVolume
        if sessions.count < layout.sessions.count || laidOut != layout.sessions {
            plannedVolume = sessions.filter(\.kind.isRun).reduce(0) { $0 + $1.target.amount(in: context.unit) }
        }
        let week = PlannedWeek(
            index: index,
            start: context.weekStart,
            kind: targets.kind,
            cycleWeek: targets.cycleWeek,
            phase: targets.phase,
            blockWeek: targets.blockWeek,
            volumeUnit: context.unit,
            plannedVolume: plannedVolume,
            longRun: layout.longRun,
            sessions: sessions,
            notes: notes
        )
        let existing = state.weeks.first { $0.plan.index == index }
        state.weeks.removeAll { $0.plan.index == index }
        state.weeks.append(WeekRecord(plan: week, checkIn: existing?.checkIn, review: nil, planBaseline: baseline))
        state.weeks.sort { $0.plan.index < $1.plan.index }
        for dose in targets.quality { state.quality.setDose(dose) }
        if let first = targets.quality.first {
            state.quality.recentTypes.append(first.type)
            if state.quality.recentTypes.count > 8 { state.quality.recentTypes.removeFirst() }
        }
        return state
    }

    /// An event plan's first week can start before the day the plan was made: sessions on days already gone
    /// then are left out. Later re-plans keep the rest of the week (CoachEngine.replanCurrentWeek).
    static func firstWeekSessions(_ sessions: [PlannedSession], context: PlanningContext) -> [PlannedSession] {
        let calendar = context.calendar
        let created = calendar.startOfDay(for: context.state.createdAt ?? context.now)
        guard context.weekIndex == 0, context.weekStart < created else { return sessions }
        let past = calendar.dateComponents([.day], from: context.weekStart, to: created).day ?? 0
        return sessions.filter { $0.dayOffset >= past || $0.kind == .race }
    }

    /// Session IDs that stay the same when a week is planned again, so the app can update its rows in place.
    static func stableIDs(_ sessions: [PlannedSession], week index: Int, state: CoachState) -> [PlannedSession] {
        var seen: [String: Int] = [:]
        return sessions.map { session in
            var session = session
            let key = "\(index)|\(session.dayOffset)|\(session.kind.rawValue)"
            let count = seen[key, default: 0]
            seen[key] = count + 1
            session.id = StableID.make("\(state.startDate.timeIntervalSinceReferenceDate)|\(state.goal.flavor.rawValue)|\(key)|\(count)")
            return session
        }
    }

    // MARK: Targets

    /// Which rule shapes the week, in the order the rules win: injury, illness, pause, the ladder,
    /// the race, a gap ramp, calibration, then the weekly outcome on the level's cycle.
    static func weekTargets(_ context: PlanningContext) -> (WeekTargets, CycleState) {
        let state = context.state
        var cycle = state.cycle

        if let plan = InjuryCoach.weekPlan(context) { return (raceWeek(plan.targets, context: context), plan.cycle) }
        if let illness = IllnessCoach.weekTargets(context) { return (raceWeek(illness, context: context), cycle) }
        if case .paused(let reason, _) = state.status {
            return (.paused(notes: [CoachNote(.plan, "No running for now, because \(reason == .heat ? "the heat got to you" : "you need a rest"). Your plan is paused, not lost. Tap 'Ready' when you want to start back.")]), cycle)
        }
        if let ladder = state.ladder, ladder.form != .done, let ladderWeek = LadderCoach.weekTargets(context) {
            return (raceWeek(ladderWeek, context: context), cycle)
        }
        if let event = eventTargets(context) { return (event, cycle) }
        if state.gap != nil, let ramp = rampTargets(context, cycle: &cycle) { return (ramp, cycle) }
        if let event = lifeEvent(context) { return (busyTargets(context, event: event), cycle) }
        if state.assessment.habitMode { return (habitTargets(context), cycle) }
        if state.assessment.start.calibrates, context.weekIndex < Progression.calibrationWeeks + extraCalibrationWeeks(state) {
            return (calibrationTargets(context), cycle)
        }
        if !state.goal.maintain, let speedWork = SpeedWorkPlanner.weekTargets(context, cycle: &cycle) { return (speedWork, cycle) }
        return outcomeTargets(context, cycle: cycle)
    }

    /// EV-6 and EF-5 when an injury, an illness or the ladder shapes the race week: the race stays unless that
    /// rule stops running, and the week stays a dead week, at most its share of peak with easy running only.
    static func raceWeek(_ targets: WeekTargets, context: PlanningContext) -> WeekTargets {
        guard eventPhase(context) == .raceWeek, let dead = eventTargets(context), dead.kind == .dead,
              targets.kind != .paused, targets.runs > 0 else { return targets }
        var targets = targets
        targets.phase = .raceWeek
        targets.volume = min(targets.volume, dead.volume)
        targets.longRun = nil
        targets.isNewLongest = false
        targets.quality = []
        targets.strides = 0
        targets.check = nil
        targets.race = dead.race
        targets.runs = max(targets.runs, 1)
        targets.notes += dead.notes
        return targets
    }

    /// A calibration week under 40% done is repeated (AD-10's new-runner rule).
    static func extraCalibrationWeeks(_ state: CoachState) -> Int {
        state.weeks.filter { $0.plan.kind == .calibration && ($0.review?.completion ?? 1) < 0.4 }.count
    }

    /// A repeated or "too hard" calibration week never drops below G4's lower bound, 30% of V0 (AD-10's
    /// tier table), so a week with almost nothing done still plans enough running to measure.
    static let calibrationFloorShare = 0.30

    /// TI-5: just under the reported numbers, nothing progresses. AD-7: week 2 after a "too hard" week 1 is
    /// 0.9 × what was done.
    static func calibrationTargets(_ context: PlanningContext) -> WeekTargets {
        let state = context.state
        var volume = 0.9 * state.v0
        let floor = calibrationFloorShare * state.v0
        var notes: [CoachNote] = []
        if context.weekIndex == 0 {
            notes.append(CoachNote(.plan, "For two weeks I'm checking your starting point. Your runs sit a little under what you told me, and nothing gets longer yet. Your chosen level starts in week 3."))
        }
        var noQuality = false
        if let previous = context.previousWeek, previous.review?.reason == .tooHard || previous.checkIn?.week == .tooHard {
            let done = previous.review?.doneVolume ?? volume
            if previous.review?.negativeFamilies.contains(.wellness) == true {
                volume = min(volume, max(0.75 * done, floor))
                noQuality = true
                notes.append(CoachNote(.outcome, "Last week felt too hard and your legs or energy were worse, so this week is a quarter under what you did, with no hard sessions."))
            } else {
                volume = min(volume, max(0.9 * done, floor))
                notes.append(CoachNote(.outcome, "Last week felt too hard, so this week is 10% under what you did, with no new longest run."))
            }
        } else if let previous = context.previousWeek, (previous.review?.completion ?? 1) < 0.4 {
            volume = min(volume, max(0.9 * (previous.review?.doneVolume ?? volume), floor))
        }
        let longRun = context.longest
        let runs = state.cycle.runsPerWeek
        let quality = noQuality ? [] : calibrationQuality(context)
        return WeekTargets(
            kind: .calibration,
            phase: state.goal.flavor == .event ? .base : nil,
            volume: volume,
            longRun: longRun.amount(in: context.unit) > 0 ? longRun : nil,
            runs: runs,
            quality: quality,
            strides: 0,
            notes: notes
        )
    }

    /// TI-5's Q: the lower of the current number and Gentle's allowance, dose unchanged, only if the early window
    /// is over and no injury report is open. Build Distance keeps an existing Q at its dose (BD-3e).
    static func calibrationQuality(_ context: PlanningContext) -> [QualityDose] {
        let state = context.state
        let assessment = state.assessment
        guard !assessment.overlays.earlyWindow, state.openInjuries.isEmpty, assessment.start.currentQ > 0 else { return [] }
        let allowance = QualityPlanner.levelTarget(tier: assessment.tier, level: .gentle)
        let count = min(assessment.start.currentQ, allowance, QualityPlanner.hardCap(runs: state.cycle.runsPerWeek, assessment: assessment))
        guard count > 0 else { return [] }
        let type: QualityType = state.goal.flavor == .event && state.goal.distance.isUpToTenK ? .vo2max : .threshold
        let dose = state.quality.dose(for: type)
            ?? QualityPlanner.dose(type, step: 1, age: assessment.age, runsPerWeek: state.cycle.runsPerWeek)
        return Array(repeating: dose, count: 1)
    }

    /// Habit mode, one run day a week: one run plus walking and no Q. The run starts at the runner's usual week and
    /// gets 10% longer after each week it is run (the same again after a missed week), up to the goal's long run and
    /// HL-5's ceiling, inside HL-1's and HL-2's caps.
    static func habitTargets(_ context: PlanningContext) -> WeekTargets {
        let state = context.state
        let unit = context.unit
        let pace = context.easyPace ?? RunnerAssessor.fallbackPace
        let start = min(state.v0, context.longest.amount(in: unit))
        var run = start
        if let last = state.weeks.last(where: { $0.plan.index < context.weekIndex && $0.plan.kind == .habit }) {
            let planned = last.plan.plannedVolume
            let done = LoadMetrics.doneVolume(week: last.plan.index, planStart: state.startDate, sessions: context.sessions, unit: unit, pace: context.easyPace, calendar: context.calendar)
            run = done >= 0.9 * planned ? planned * CoachLimits.sessionGrowth : planned
        }
        let goalLong = FeasibilityEngine.amount(meters: GoalChecker.greenTargets(for: state.goal).longRun, unit: unit, pace: pace)
        let ceiling = min(
            FeasibilityEngine.amount(meters: CoachLimits.longRunCeiling.meters, unit: unit, pace: pace),
            FeasibilityEngine.amount(seconds: CoachLimits.longRunCeiling.seconds, unit: unit, pace: pace)
        )
        run = max(start, min(run, max(goalLong, start), ceiling, context.weekCap, context.longest.amount(in: unit) * CoachLimits.sessionGrowth))
        return WeekTargets(
            kind: .habit,
            volume: run,
            longRun: nil,
            runs: 1,
            extras: [.walk, .walk],
            notes: [CoachNote(.plan, "One run this week, a little longer than last time. A second run day gets you to your goal sooner.")]
        )
    }

    // MARK: The weekly outcome on the cycle

    /// The level in force for rates: one lower during an RB-6 drop.
    static func effectiveLevel(_ state: CoachState, now: Date, calendar: Calendar) -> CommitmentLevel {
        var level = state.level
        if let until = state.assessment.recovery.levelDropUntil, until > now { level = level.lower }
        if InjuryCoach.injuryWindowActive(state, now: now, calendar: calendar) { level = min(level.lower, .steady) }
        return level
    }

    static func cycle(for state: CoachState, now: Date, calendar: Calendar) -> [CycleWeek] {
        CycleWeek.cycle(
            for: effectiveLevel(state, now: now, calendar: calendar),
            stepBackEveryThird: state.assessment.recoveryTier.stepsBackEveryThird,
            twoWeekHold: InjuryCoach.injuryWindowActive(state, now: now, calendar: calendar)
        )
    }

    /// The last loading or HOLD week, and its base: the lower of planned and done (CL-1).
    static func lastLoading(_ context: PlanningContext) -> (record: WeekRecord, base: Double)? {
        let state = context.state
        guard let record = state.weeks.last(where: { $0.plan.index < context.weekIndex && ($0.plan.kind == .loading || $0.plan.kind == .hold) }) else {
            return nil
        }
        let done = LoadMetrics.doneVolume(week: record.plan.index, planStart: state.startDate, sessions: context.sessions, unit: context.unit, pace: context.easyPace, calendar: context.calendar)
        return (record, min(record.plan.plannedVolume, done))
    }

    static func outcomeTargets(_ context: PlanningContext, cycle: CycleState) -> (WeekTargets, CycleState) {
        var cycle = cycle
        let state = context.state
        let unit = context.unit
        let previous = context.previousWeek
        var outcome = previous?.review?.outcome ?? .progress
        let phase = eventPhase(context) ?? SpeedWorkPlanner.phase(context)
        var notes: [CoachNote] = []
        if let note = previous?.review?.note, outcome != .progress { notes.append(note) }
        // EV-1: an unused buffer week is planned as a HOLD.
        if outcome == .progress, cycle.preCutVolume == nil, isBufferWeek(context) {
            outcome = .hold
            notes.append(CoachNote(.event, "This is a spare week: the same running as last week. If a week gets lost to illness or a busy stretch, this is where it's made up."))
        }

        let previousVolume = previous.map { record -> Double in
            let done = record.review?.doneVolume ?? record.plan.plannedVolume
            return min(record.plan.plannedVolume, done)
        } ?? state.v0
        let previousLong = previous?.plan.longRun ?? cycle.lastLoadingLongRun

        switch outcome {
        case .hold:
            // Same targets. After a planned step-back, the pre-step-back targets without the extra step.
            var volume = previous?.plan.plannedVolume ?? state.v0
            var long = previousLong
            if previous?.plan.kind == .stepBack || previous?.plan.kind == .calibration {
                volume = cycle.lastLoadingVolume > 0 ? cycle.lastLoadingVolume : state.v0
                long = previous?.plan.kind == .calibration ? context.longest : cycle.lastLoadingLongRun
            }
            cycle.loadingInRow += 1
            if cycle.loadingInRow > CoachLimits.loadingWeeksInRow {
                return stepBackTargets(context, cycle: &cycle, base: lastLoading(context)?.base ?? volume, adaptive: false, notes: notes)
            }
            let quality = heldQuality(context)
            return (WeekTargets(kind: .hold, phase: phase, volume: volume, longRun: long.capped(at: context.longest), runs: cycle.runsPerWeek, quality: quality, strides: stridesCount(context), notes: notes), cycle)

        case .ease:
            cycle.preCutVolume = cycle.preCutVolume ?? previous?.plan.plannedVolume
            cycle.preCutLongRun = cycle.preCutLongRun ?? previousLong
            cycle.loadingInRow += 1
            if cycle.loadingInRow > CoachLimits.loadingWeeksInRow {
                return stepBackTargets(context, cycle: &cycle, base: previousVolume, adaptive: true, notes: notes)
            }
            var quality = heldQuality(context)
            if !quality.isEmpty { quality.removeFirst() }
            return (WeekTargets(kind: .ease, phase: phase, volume: 0.9 * previousVolume, longRun: previousLong.capped(at: context.longest), runs: cycle.runsPerWeek, quality: quality, notes: notes), cycle)

        case .stepBack:
            cycle.preCutVolume = cycle.preCutVolume ?? previous?.plan.plannedVolume
            cycle.preCutLongRun = cycle.preCutLongRun ?? previousLong
            if previous?.review?.reason == .fatigueLevel1 {
                // AD-6b Level 1: easy runs only, 50% of the pre-cut volume, at least 2 rest days.
                cycle.position = 0
                cycle.loadingInRow = 0
                let preCut = state.fatigue.preCutVolume ?? cycle.preCutVolume ?? previousVolume
                return (WeekTargets(kind: .fatigueEasy, phase: phase, volume: 0.5 * preCut, longRun: nil, runs: cycle.runsPerWeek, minimumRestDays: 2, notes: notes), cycle)
            }
            return stepBackTargets(context, cycle: &cycle, base: previousVolume, adaptive: true, notes: notes)

        case .pause, .recoveryPlan, .returnRamp:
            // The modules above own these weeks; if none claimed this one, hold.
            return (WeekTargets(kind: .hold, phase: phase, volume: previous?.plan.plannedVolume ?? state.v0, longRun: previousLong.capped(at: context.longest), runs: cycle.runsPerWeek, notes: notes), cycle)

        case .progress:
            break
        }

        // Back to the level before an EASE or STEP BACK, never higher (AD-6a).
        if let preCut = cycle.preCutVolume {
            cycle.preCutVolume = nil
            let long = cycle.preCutLongRun ?? previousLong
            cycle.preCutLongRun = nil
            cycle.loadingInRow += 1
            let quality = heldQuality(context).map { QualityPlanner.twoThirds($0) }
            return (WeekTargets(kind: .hold, phase: phase, volume: preCut, longRun: long.capped(at: context.longest), runs: cycle.runsPerWeek, quality: quality, strides: quality.isEmpty ? stridesCount(context) : 0, notes: [CoachNote(.outcome, "Back to where you were before the lighter week.")]), cycle)
        }

        let weeks = WeekPlanner.cycle(for: state, now: context.now, calendar: context.calendar)
        var cycleWeek = weeks[cycle.position % weeks.count]
        if cycleWeek.isLoading, cycle.loadingInRow >= CoachLimits.loadingWeeksInRow { cycleWeek = .stepBack }
        let base = lastLoading(context)?.base ?? state.v0

        if cycleWeek == .stepBack {
            return stepBackTargets(context, cycle: &cycle, base: base, adaptive: false, notes: notes)
        }

        // BD-1g, SW-7c: keeping a distance or fitness, N and H weeks hold the last building week's volume and long
        // run, and S weeks stay. Speed Work keeps one quality session a week at the current dose.
        if state.goal.maintain {
            cycle.position += 1
            cycle.loadingInRow += 1
            let held = (cycle.lastLoadingLongRun.amount(in: unit) > 0 ? cycle.lastLoadingLongRun : context.longest).capped(at: context.longest)
            let quality = Array(heldQuality(context).prefix(1))
            let targets = WeekTargets(
                kind: .maintain,
                cycleWeek: .heldLongRun,
                phase: phase,
                volume: base,
                longRun: held,
                runs: cycle.runsPerWeek,
                quality: quality,
                strides: quality.isEmpty ? stridesCount(context) : 0,
                notes: notes
            )
            return (targets, cycle)
        }

        // N and H: volume grows at the level's rate from the base; risk score ≥2 makes H a full hold (TI-4).
        let rate = effectiveLevel(state, now: context.now, calendar: context.calendar).loadingRate
        let fullHold = cycleWeek == .heldLongRun && state.assessment.risk.isHigh
        var volume = fullHold ? base : base * (1 + rate)
        var longRun: Load
        var isNew = false
        let held = (cycle.lastLoadingLongRun.amount(in: unit) > 0 ? cycle.lastLoadingLongRun : context.longest).capped(at: context.longest)
        if cycleWeek == .newLongest, canAddNewLongest(context) {
            longRun = context.longest.scaled(by: CoachLimits.sessionGrowth)
            isNew = true
        } else {
            longRun = held
            if cycleWeek == .newLongest {
                cycleWeek = .heldLongRun
                notes.append(CoachNote(.limit, "Your last new longest run was under 7 days ago, so the long run holds this week."))
            }
        }

        // The goal's long-run target and the volume ceiling (BD-3a step 2, BD-3b, HL-14).
        let targetLong = goalLongRun(state, pace: context.easyPace)
        if let targetLong, longRun.amount(in: unit) >= targetLong.amount(in: unit) {
            longRun = targetLong.amount(in: unit) > held.amount(in: unit) ? targetLong : held
            isNew = longRun.amount(in: unit) > context.longest.amount(in: unit) + 0.000_1
        }
        let ceiling = volumeCeiling(state, pace: context.easyPace)
        if volume >= ceiling {
            volume = max(ceiling, base)
            if !state.shownOnce.contains("ceiling") {
                notes.append(CoachNote(.limit, "You already run enough each week for your goal, so I'll keep your weekly distance here."))
            }
        }

        // BD-3a step 5: over 60% of the week while below the ceiling, the long run holds and the step goes to other runs.
        if isNew, volume < ceiling, longRun.amount(in: unit) > CoachLimits.longRunWeekShare * volume {
            longRun = held
            isNew = false
            cycleWeek = .heldLongRun
        }

        cycle.position += 1
        cycle.loadingInRow += 1

        var targets = WeekTargets(
            kind: .loading,
            cycleWeek: cycleWeek,
            phase: phase,
            volume: volume,
            longRun: longRun,
            isNewLongest: isNew,
            runs: runsThisWeek(context, cycle: &cycle, volume: volume, longRun: longRun),
            notes: notes
        )
        addQuality(&targets, context: context, cycle: cycle)
        if isNew {
            targets.notes.append(CoachNote(.plan, "Long run: \(CoachFormat.load(longRun, in: unit, unit: state.intake.distanceUnit)), your new longest. Easy enough to talk the whole way; walk breaks are fine."))
        }
        return (targets, cycle)
    }

    /// A planned (CL-2) or adaptive (AD-5) step-back: −25% from the base, the long run at 70% of P-L30, one fewer Q
    /// (none when adaptive), no new longest. Either way the next cycle starts after it.
    static func stepBackTargets(_ context: PlanningContext, cycle: inout CycleState, base: Double, adaptive: Bool, notes: [CoachNote]) -> (WeekTargets, CycleState) {
        cycle.position = 0
        cycle.loadingInRow = 0
        var notes = notes
        if !adaptive {
            notes.append(CoachNote(.plan, "This is a lighter week: about a quarter less running and a shorter long run. Every few weeks I plan one so you start the next block fresh."))
        }
        var quality = adaptive ? [] : heldQuality(context)
        if !quality.isEmpty { quality.removeLast() }
        let targets = WeekTargets(
            kind: adaptive ? .adaptiveStepBack : .stepBack,
            cycleWeek: .stepBack,
            phase: eventPhase(context),
            volume: CoachLimits.stepBackVolume * base,
            longRun: context.longest.scaled(by: CoachLimits.stepBackLongRun),
            runs: cycle.runsPerWeek,
            quality: quality,
            strides: adaptive ? 0 : stridesCount(context),
            notes: notes
        )
        return (targets, cycle)
    }

    /// HL-1: a new longest needs 7 days since the last one, and HL-15 needs no open report.
    static func canAddNewLongest(_ context: PlanningContext) -> Bool {
        let state = context.state
        guard state.openInjuries.isEmpty else { return false }
        // AD-8: no new longest run for 7 days after a spike.
        let longDayOffset = state.intake.longRunDay.map { Scheduler.WeekDays(first: Weekday(of: context.weekStart, calendar: context.calendar)).offset(of: $0) } ?? 6
        let longDate = context.calendar.date(byAdding: .day, value: longDayOffset, to: context.weekStart) ?? context.weekStart
        if state.runReview.spikes.contains(where: { longDate.timeIntervalSince($0.date) < 7 * 86_400 && $0.date <= longDate }) { return false }
        guard let last = state.cycle.lastNewLongest else { return true }
        let longDay = state.intake.longRunDay.map { Scheduler.WeekDays(first: Weekday(of: context.weekStart, calendar: context.calendar)).offset(of: $0) } ?? 6
        let date = context.calendar.date(byAdding: .day, value: longDay, to: context.weekStart) ?? context.weekStart
        let days = context.calendar.dateComponents([.day], from: context.calendar.startOfDay(for: last), to: date).day ?? 7
        return days >= 7
    }

    /// The long run the goal needs (RC-2), capped by HL-5, in the plan's unit with both sides.
    static func goalLongRun(_ state: CoachState, pace: Double?) -> Load? {
        let goal = state.goal
        let meters = GoalChecker.greenTargets(for: goal).longRun
        var load = Load(meters, in: .distance, pace: pace)
        if goal.distance == .fiveK, load.seconds == 0 || load.seconds > 30 * 60 { load = load.capped(at: Load(meters: 5_000, seconds: 30 * 60)) }
        load = load.capped(at: CoachLimits.longRunCeiling)
        if goal.flavor == .event || goal.flavor == .buildDistance || goal.flavor == .speedWork { return load }
        return nil
    }

    /// HL-14's volume ceiling: the higher of the volume already sustained and the goal's Green volume + 10%,
    /// or the completion week's minimum (BD-3b): the goal's long run, each other run at 20 min and, in an event
    /// plan, its Q at the top of their ladders with the shortest warm-up and cool-down, so the Q can grow while
    /// volume holds (HL-3).
    static func volumeCeiling(_ state: CoachState, pace: Double?) -> Double {
        let unit = state.volumeUnit
        let green = GoalChecker.greenTargets(for: state.goal).volume
        let greenAmount: Double
        if state.goal.distance == .fiveK {
            greenAmount = Load(90 * 60, in: .time, pace: pace).amount(in: unit)
        } else if green > 0 {
            greenAmount = Load(green, in: .distance, pace: pace).amount(in: unit)
        } else {
            greenAmount = 0
        }
        let others = max(0, state.cycle.runsPerWeek - 1)
        let minimumRun = Load(CoachLimits.minimumRunSeconds, in: .time, pace: pace).amount(in: unit)
        let quality = completionQuality(state).prefix(others).map { dose in
            max(minimumRun, Scheduler.qualityLoad(dose, paces: state.paces).amount(in: unit))
        }
        let completion = (goalLongRun(state, pace: pace)?.amount(in: unit) ?? 0)
            + quality.reduce(0, +) + Double(others - quality.count) * minimumRun
        return max(state.assessment.start.v0, greenAmount * 1.10, completion)
    }

    /// The Q an event's completion week holds: the level's count, each type at the top of its ladder. Speed Work
    /// holds volume through its blocks instead (SW-6), and Build Distance has no Q.
    static func completionQuality(_ state: CoachState) -> [QualityDose] {
        guard state.goal.flavor == .event else { return [] }
        let runs = state.cycle.runsPerWeek
        let count = QualityPlanner.count(state: state, runs: runs, weekIndex: .max)
        let types = QualityPlanner.types(count: count, state: state, weekIndex: 0, phase: nil)
        return types.map { QualityPlanner.dose($0, step: .max, age: state.assessment.age, runsPerWeek: runs) }
    }

    /// Whether the week's long run, its Q at these doses and its other runs at 20 min fit its volume.
    static func qualityFits(_ doses: [QualityDose], targets: WeekTargets, context: PlanningContext) -> Bool {
        let unit = context.unit
        let minimumRun = Load(CoachLimits.minimumRunSeconds, in: .time, pace: context.easyPace).amount(in: unit)
        let quality = doses.map { max(minimumRun, Scheduler.qualityLoad($0, paces: context.state.paces).amount(in: unit)) }
        let long = targets.longRun?.amount(in: unit) ?? 0
        let others = max(0, targets.runs - doses.count - (targets.longRun == nil ? 0 : 1))
        return long + quality.reduce(0, +) + Double(others) * minimumRun <= targets.volume + 0.000_1
    }

    /// BD-3c: runs are lengthened before one is added; at a cycle start the level may add an easy run of 20-30 min
    /// once the other runs would pass 2/3 of the long run, ≥4 weeks after the last one, inside HL-9 and the days offered.
    static func runsThisWeek(_ context: PlanningContext, cycle: inout CycleState, volume: Double, longRun: Load) -> Int {
        let state = context.state
        let assessment = state.assessment
        var runs = cycle.runsPerWeek
        guard cycle.position == 1 else { return runs }
        let level = effectiveLevel(state, now: context.now, calendar: context.calendar)
        let levelCap: Int
        switch level {
        case .gentle: levelCap = runs
        case .steady: levelCap = assessment.tier == .novice ? 3 : (assessment.tier == .regular ? 4 : 5)
        case .ambitious: levelCap = assessment.runsCap
        }
        let cap = min(levelCap, assessment.runsCap, state.intake.runDays.isEmpty ? 5 : state.intake.runDays.count, 5)
        guard runs < cap else { return runs }
        if let last = cycle.lastRunAddedWeek, context.weekIndex - last < 4 { return runs }
        let others = max(1, runs - 1)
        let share = (volume - longRun.amount(in: context.unit)) / Double(others)
        if share > longRun.amount(in: context.unit) * CoachLimits.otherRunShare {
            runs += 1
            cycle.runsPerWeek = runs
            cycle.lastRunAddedWeek = context.weekIndex
        }
        return runs
    }

    // MARK: Quality

    /// Strides: one set a week from 20 min non-stop and plan week 4 (BD-3e, HL-13); none in a dead week.
    static func stridesCount(_ context: PlanningContext) -> Int {
        let state = context.state
        guard context.weekIndex >= 3, state.openInjuries.isEmpty else { return 0 }
        return 1
    }

    /// The Q doses in force, unchanged (HOLD and EASE repeat the last dose).
    static func heldQuality(_ context: PlanningContext) -> [QualityDose] {
        let state = context.state
        guard state.goal.flavor != .buildDistance, state.openInjuries.isEmpty,
              QualityPlanner.gateBlocker(state: state, runs: context.runs, now: context.now, calendar: context.calendar) == nil,
              distanceReady(context) else { return [] }
        let count = QualityPlanner.count(state: state, runs: state.cycle.runsPerWeek, weekIndex: context.weekIndex)
        let types = QualityPlanner.types(count: count, state: state, weekIndex: context.weekIndex, phase: eventPhase(context))
        return types.compactMap { type in
            state.quality.dose(for: type) ?? QualityPlanner.firstDose(type, current: nil, age: state.assessment.age, runsPerWeek: state.cycle.runsPerWeek)
        }
    }

    /// Speed Work runs Build Distance weeks until the goal's distance readiness is Green (SW-1b).
    static func distanceReady(_ context: PlanningContext) -> Bool {
        let state = context.state
        guard state.goal.flavor == .speedWork else { return true }
        guard let target = goalLongRun(state, pace: context.easyPace) else { return true }
        let unit = context.unit
        let longestOK = context.longest.amount(in: unit) >= target.amount(in: unit) * 0.999
        let greenVolume = GoalChecker.greenTargets(for: state.goal).volume
        let volumeOK = greenVolume == 0 || context.w4max >= Load(greenVolume, in: .distance, pace: context.easyPace).amount(in: unit) * 0.999
        return longestOK && volumeOK
    }

    /// Adds the week's Q: the gate, the count and the mix, each dose one step up in a block or H week (HL-3, SW-3a, EV-1).
    static func addQuality(_ targets: inout WeekTargets, context: PlanningContext, cycle: CycleState) {
        let state = context.state
        let assessment = state.assessment
        if state.goal.flavor == .buildDistance || !state.openInjuries.isEmpty || InjuryCoach.qualityWaits(state, now: context.now, calendar: context.calendar) {
            targets.strides = stridesCount(context)
            return
        }
        if let blocker = QualityPlanner.gateBlocker(state: state, runs: context.runs, now: context.now, calendar: context.calendar) {
            targets.strides = stridesCount(context)
            if !state.shownOnce.contains("qGate") {
                targets.notes.append(CoachNote(.limit, "Speed sessions unlock after a few steady weeks. Until then: easy runs plus a few short strides. That's because \(blocker)."))
            }
            return
        }
        guard distanceReady(context) else {
            targets.strides = stridesCount(context)
            return
        }
        // Speed Work's Q steps only inside its blocks: Build Distance weeks before the first block have none,
        // and SW-6's volume cycle holds each Q at its dose (SW-1b, SW-6).
        if state.goal.flavor == .speedWork, targets.phase != .speedBlock {
            targets.quality = targets.phase == .volumeCycle ? heldQuality(context) : []
            targets.strides = targets.quality.isEmpty ? stridesCount(context) : 0
            return
        }
        let count = QualityPlanner.count(state: state, runs: targets.runs, weekIndex: context.weekIndex)
        let types = QualityPlanner.types(count: count, state: state, weekIndex: context.weekIndex, phase: targets.phase)
        var doses: [QualityDose] = []
        var newType = false
        // HL-3 and EV-1: a Q steps in a speed block, in H weeks, and in loading weeks that hold volume and the
        // long run (targets already reached, HL-14). Outside a block it steps only when the week still fits.
        let holdsLoad = targets.kind == .loading && !targets.isNewLongest
            && targets.volume <= max(context.w4max, cycle.lastLoadingVolume) + 0.000_1
        let block = targets.phase == .speedBlock
        let mayStep = block || targets.cycleWeek == .heldLongRun || holdsLoad
        for type in types {
            if let current = state.quality.dose(for: type) {
                doses.append(mayStep ? QualityPlanner.stepped(current, age: assessment.age, runsPerWeek: targets.runs) : current)
            } else {
                newType = true
                doses.append(QualityPlanner.firstDose(type, current: state.quality.doses.last, age: assessment.age, runsPerWeek: targets.runs))
            }
        }
        if mayStep, !block {
            var capped = targets
            capped.volume = min(targets.volume, max(context.w4max, cycle.lastLoadingVolume))
            if !qualityFits(doses, targets: capped, context: context) {
                doses = zip(doses, types).map { dose, type in state.quality.dose(for: type) ?? dose }
            }
        }
        targets.quality = doses
        if !doses.isEmpty {
            // HL-3: intensity steps only with volume held; a new Q type's first week runs at 0.90 × W4max.
            let stepped = zip(doses, types).contains { dose, type in (state.quality.dose(for: type)?.step ?? -1) < dose.step }
            if newType {
                targets.volume = min(targets.volume, 0.9 * context.w4max)
                if targets.isNewLongest {
                    targets.isNewLongest = false
                    if let long = targets.longRun { targets.longRun = long.capped(at: context.longest) }
                }
                targets.notes.append(CoachNote(.plan, "This week adds speed, so your distance stays the same. I never raise both in one week."))
            } else if stepped {
                targets.volume = min(targets.volume, max(context.w4max, cycle.lastLoadingVolume))
                if targets.isNewLongest, state.goal.flavor == .speedWork {
                    targets.isNewLongest = false
                    if let long = targets.longRun { targets.longRun = long.capped(at: context.longest) }
                }
            }
            targets.strides = 0
        } else {
            targets.strides = stridesCount(context)
        }
    }

    // MARK: Events (EV-1, EV-6, EV-8, EV-9)

    /// The event phase of the planning week, or nil outside an event plan.
    static func eventPhase(_ context: PlanningContext) -> TrainingPhase? {
        guard let event = context.state.event else { return nil }
        let start = context.weekStart
        if start >= event.raceDate { return .recovery }
        if let raceWeek = context.calendar.date(byAdding: .day, value: -6, to: context.calendar.startOfDay(for: event.raceDate)), start >= raceWeek { return .raceWeek }
        if start >= event.taperStart { return .taper }
        if start >= event.specificStart { return .specific }
        if let speed = event.speedBlockStart, start >= speed { return .speedBlock }
        return context.weekIndex < Progression.calibrationWeeks ? .base : .build
    }

    /// EV-1: the unused buffer weeks sit directly before the speed block, or before the specific phase without one.
    /// Each lost build week uses the first unused one (EF-2), so the build carries on there instead.
    static func isBufferWeek(_ context: PlanningContext) -> Bool {
        guard let event = context.state.event, eventPhase(context) == .build else { return false }
        let unused = max(0, event.bufferWeeks - event.bufferUsed)
        let end = event.speedBlockStart ?? event.specificStart
        guard unused > 0, let start = context.calendar.date(byAdding: .day, value: -7 * unused, to: end) else { return false }
        return context.weekStart >= start && context.weekStart < end
    }

    /// The taper, the race week and the recovery after the race; nil for other weeks.
    static func eventTargets(_ context: PlanningContext) -> WeekTargets? {
        let state = context.state
        guard let event = state.event, let phase = eventPhase(context) else { return nil }
        let unit = context.unit
        let distance = state.goal.distance
        switch phase {
        case .taper, .raceWeek:
            let peak = peakVolume(context)
            let peakLong = peakLongRun(context)
            let taperWeek = taperWeekNumber(context)
            let (share, longShare) = taperShares(distance: distance, peak: Load(peak, in: unit, pace: context.easyPace).meters, week: taperWeek, raceWeek: phase == .raceWeek)
            var targets = WeekTargets(
                kind: phase == .raceWeek ? .dead : .taper,
                phase: phase,
                volume: peak * share,
                longRun: longShare.map { peakLong.scaled(by: $0) },
                runs: state.cycle.runsPerWeek,
                notes: []
            )
            if phase == .raceWeek {
                let raceDay = context.calendar.startOfDay(for: event.raceDate)
                let raceOffset = context.calendar.dateComponents([.day], from: context.weekStart, to: raceDay).day ?? 6
                targets.longRun = nil
                targets.notes.append(CoachNote(.event, "This is race week: easy runs only, at most half your usual weekly distance, and no speed work, so you start fresh."))
                // HL-19 (EF-5): a fever or below-the-neck illness now or within 48 h of the start means don't start.
                // The start time isn't known, so the 48 h count back from the start of race day.
                if IllnessCoach.raceStartBlocked(state, raceStart: raceDay) {
                    targets.notes.append(CoachNote(.event, "With a fever or an illness below the neck this close to race day, please don't start. I know that's hard after all your training. Let's pick another race once you're well."))
                } else {
                    targets.race = RaceDay(dayOffset: raceOffset.clamped(to: 0 ... 6), distance: distance, targetSeconds: state.goal.targetSeconds)
                }
            } else {
                // Before the dead week: only intensity done in the last 4 weeks, at half the reps.
                targets.quality = state.quality.doses.filter { dose in
                    state.weeks.suffix(4).contains { $0.plan.sessions.contains { $0.dose?.type == dose.type } }
                }.map { dose in
                    var half = dose
                    half.reps = max(1, dose.reps / 2)
                    if dose.continuous { half.repSeconds = (dose.repSeconds / 2).rounded(toMultipleOf: 60) }
                    return half
                }
                if taperWeek == 1 {
                    targets.notes.append(CoachNote(.event, "Your taper starts today. Same number of runs, just shorter, so you arrive fresh."))
                }
            }
            return targets
        case .recovery:
            return raceRecoveryTargets(context, event: event)
        default:
            return nil
        }
    }

    /// 1 for the first taper week, counting to the dead week.
    static func taperWeekNumber(_ context: PlanningContext) -> Int {
        guard let event = context.state.event else { return 1 }
        let days = context.calendar.dateComponents([.day], from: event.taperStart, to: context.weekStart).day ?? 0
        return days / 7 + 1
    }

    /// EV-6's shares of peak volume, and of the peak long run, for each taper week.
    static func taperShares(distance: RaceDistance, peak meters: Double, week: Int, raceWeek: Bool) -> (Double, Double?) {
        switch distance {
        case .mile, .fiveK, .tenK:
            return (0.50, nil)
        case .halfMarathon:
            return raceWeek ? (0.45, nil) : (0.70, 0.60)
        case .marathon:
            if meters < 40_000 {
                return raceWeek ? (0.40, nil) : (0.65, 0.55)
            }
            if raceWeek { return (0.35, nil) }
            return week == 1 ? (0.75, 0.55) : (0.55, 0.40)
        }
    }

    /// Peak = the mean weekly volume of the 4 weeks before the taper (EV-6).
    static func peakVolume(_ context: PlanningContext) -> Double {
        let state = context.state
        guard let event = state.event else { return state.v0 }
        let taperIndex = state.weekIndex(on: event.taperStart, calendar: context.calendar)
        let weeks = (taperIndex - 4 ..< taperIndex).filter { $0 >= 0 }
        guard !weeks.isEmpty else { return state.v0 }
        let volumes = weeks.map { index -> Double in
            let done = LoadMetrics.doneVolume(week: index, planStart: state.startDate, sessions: context.sessions, unit: context.unit, pace: context.easyPace, calendar: context.calendar)
            let planned = state.weeks.first { $0.plan.index == index }?.plan.plannedVolume ?? done
            return index < context.weekIndex && done > 0 ? done : planned
        }
        return volumes.reduce(0, +) / Double(volumes.count)
    }

    static func peakLongRun(_ context: PlanningContext) -> Load {
        let longs = context.state.weeks.compactMap(\.plan.longRun)
        return longs.max { $0.amount(in: context.unit) < $1.amount(in: context.unit) } ?? context.longest
    }

    /// EV-9: the weeks after the race; when they end the plan is complete and the next goal is offered.
    static func raceRecoveryTargets(_ context: PlanningContext, event: EventState) -> WeekTargets {
        let state = context.state
        let daysSince = context.calendar.dateComponents([.day], from: context.calendar.startOfDay(for: event.raceDate), to: context.weekStart).day ?? 0
        let week = daysSince / 7
        let preTaper = peakVolume(context)
        // A race not finished recovers by the distance run (EV-9); the race day's message says when hard running
        // can start again.
        let distance = EventReviewer.recoveryDistance(state) ?? state.goal.distance
        let share: Double
        switch distance {
        case .mile, .fiveK, .tenK: share = 0.6
        case .halfMarathon: share = 0.5
        case .marathon: share = week == 0 ? 0.3 : (week == 1 ? 0.5 : 0.75)
        }
        let cap: Load? = distance == .marathon && week == 0 ? Load(meters: 0, seconds: 30 * 60) : nil
        return WeekTargets(
            kind: .raceRecovery,
            phase: .recovery,
            volume: preTaper * share,
            longRun: nil,
            runs: max(2, state.cycle.runsPerWeek - 1),
            sessionCap: cap
        )
    }

    // MARK: Gaps (AD-10)

    static func rampTargets(_ context: PlanningContext, cycle: inout CycleState) -> WeekTargets? {
        guard let ramp = context.state.gap else { return nil }
        let first = ramp.referenceLongRun.scaled(by: ramp.tier.longRunShare)
        var long = first
        if ramp.weeksDone > 0, let previous = context.previousWeek, previous.plan.kind == .ramp, let previousLong = previous.plan.longRun {
            long = previousLong.scaled(by: CoachLimits.sessionGrowth)
        }
        long = long.capped(at: ramp.referenceLongRun)
        // Q by tier: G1 and G2 from the second week, G3 from the third, at half dose; G4 after the ramp (AD-10).
        var quality: [QualityDose] = []
        let firstQWeek: Int? = switch ramp.tier {
        case .g0, .g1, .g2: 1
        case .g3: 2
        case .g4: nil
        }
        if let firstQWeek, ramp.weeksDone >= firstQWeek {
            quality = heldQuality(context).prefix(1).map { dose in
                var half = dose
                if dose.continuous || dose.reps <= 1 {
                    half.repSeconds = max(60, (dose.repSeconds / 2).rounded(toMultipleOf: 60))
                } else {
                    half.reps = max(1, dose.reps / 2)
                }
                return half
            }
        }
        var notes: [CoachNote] = []
        if ramp.weeksDone == 0 {
            switch ramp.tier {
            case .g0: notes.append(CoachNote(.outcome, "A few days off doesn't cost meaningful fitness, unless you were in bed."))
            case .g1: notes.append(CoachNote(.outcome, "A week off costs little fitness; we'll ease back in over two weeks."))
            case .g2: notes.append(CoachNote(.outcome, "We'll rebuild step by step, running by feel at first."))
            case .g3, .g4: notes.append(CoachNote(.outcome, "Aerobic fitness returns fairly fast; legs and race speed take longer."))
            }
        }
        return WeekTargets(
            kind: .ramp,
            phase: eventPhase(context),
            volume: ramp.reference * ramp.share,
            longRun: long,
            runs: cycle.runsPerWeek,
            quality: quality,
            notes: notes
        )
    }

    // MARK: Busy weeks (AD-11)

    /// The busy or travel entry in force at the week's start, if any.
    static func lifeEvent(_ context: PlanningContext) -> LifeEvent? {
        context.state.lifeEvents.last { event in
            [.busy, .holiday, .travelling, .bigLifeChange].contains(event.kind) && event.isActive(on: context.weekStart, calendar: context.calendar)
        }
    }

    /// Busy weeks keep ≥2 runs of ≥25 min and ≥30% of usual volume: the long run at ≥60% of usual first, then a Q
    /// for Regular and Experienced runners at a lower dose, then easy runs. Longer busy stretches keep 2 runs, one a
    /// short threshold session. A big life change holds with at most 2 hard days.
    static func busyTargets(_ context: PlanningContext, event: LifeEvent) -> WeekTargets {
        let state = context.state
        let usual = lastLoading(context)?.base ?? state.v0
        let usualLong = (state.cycle.lastLoadingLongRun.amount(in: context.unit) > 0 ? state.cycle.lastLoadingLongRun : context.longest).capped(at: context.longest)
        let experienced = state.assessment.tier >= .regular
        let busyWeeksInRow = state.weeks.reversed().prefix { $0.plan.kind == .busy }.count
        let previousVolume = context.previousWeek?.plan.plannedVolume ?? usual

        switch event.kind {
        case .bigLifeChange:
            return WeekTargets(
                kind: .hold,
                phase: eventPhase(context),
                volume: previousVolume,
                longRun: usualLong,
                runs: state.cycle.runsPerWeek,
                quality: Array(heldQuality(context).prefix(1)),
                notes: [CoachNote(.plan, "Same targets as last week, because a lot is going on. Nothing to make up.")]
            )
        case .travelling where event.length == .oneWeek || event.length == nil:
            return WeekTargets(
                kind: .hold,
                phase: eventPhase(context),
                volume: previousVolume,
                longRun: usualLong,
                runs: state.cycle.runsPerWeek,
                quality: Array(heldQuality(context).prefix(1)),
                notes: [CoachNote(.plan, "Same targets as last week while you travel. Run what fits; nothing to make up.")]
            )
        default:
            break
        }

        let longMode = event.length == .longer || busyWeeksInRow >= 3
        let twentyFive = Load(25 * 60, in: .time, pace: context.easyPace)
        if longMode {
            var quality: [QualityDose] = []
            if experienced, state.quality.gateMetOn != nil {
                quality = [QualityDose(type: .threshold, step: 0, reps: 3, repSeconds: 180, recoverySeconds: 90)]
            }
            return WeekTargets(
                kind: .busy,
                phase: eventPhase(context),
                volume: max(2 * twentyFive.amount(in: context.unit), 0.3 * usual),
                longRun: nil,
                runs: 2,
                quality: quality,
                notes: [CoachNote(.plan, "Busy stretch: two runs a week keep your fitness for months. Nothing to make up.")]
            )
        }
        let runs = min(3, max(2, state.cycle.runsPerWeek))
        let long = usualLong.scaled(by: 0.6)
        var quality: [QualityDose] = []
        if experienced { quality = heldQuality(context).prefix(1).map { QualityPlanner.twoThirds($0) } }
        let floor = long.amount(in: context.unit) + Double(runs - 1) * twentyFive.amount(in: context.unit)
        return WeekTargets(
            kind: .busy,
            phase: eventPhase(context),
            volume: max(floor, 0.3 * usual, min(0.6 * usual, previousVolume)),
            longRun: long,
            runs: runs,
            quality: quality,
            notes: [CoachNote(.plan, "Busy week? Two 25-minute runs and a shorter long run keep your fitness; nothing to make up.")]
        )
    }

    // MARK: Hard limits

    /// Applies HL-1, HL-2, HL-5, HL-11, HL-14 and the day limits to whatever rule shaped the week.
    static func applyLimits(_ targets: WeekTargets, context: PlanningContext) -> WeekTargets {
        var targets = targets
        let state = context.state
        let unit = context.unit
        let distanceUnit = state.intake.distanceUnit

        // HL-2: the weekly cap. A race's own distance isn't counted (EV-6). Ladder weeks apply HL-2 themselves
        // by trimming repeats, never the segment (BD-2a).
        if targets.kind != .ladder, targets.volume > context.weekCap + 0.000_1 {
            targets.volume = context.weekCap
            targets.notes.append(CoachNote(.limit, "This week is capped at \(CoachFormat.amount(context.weekCap, in: unit, unit: distanceUnit)), 20% above your biggest recent week."))
        }

        if var long = targets.longRun {
            // HL-1: no session over 1.10 × P-L30, in distance or in time.
            let sessionCap = context.longest.scaled(by: CoachLimits.sessionGrowth)
            if context.longest.amount(in: unit) > 0, long.amount(in: unit) > sessionCap.amount(in: unit) + 0.000_1 {
                long = long.capped(at: sessionCap)
                targets.notes.append(CoachNote(.limit, "Your longest run in the last month is \(CoachFormat.load(context.longest, in: unit, unit: distanceUnit)), so this week's long run is \(CoachFormat.load(long, in: unit, unit: distanceUnit)). Gradual steps lower injury risk; they can't remove it."))
            }
            // HL-5: the long-run ceiling.
            long = long.capped(at: CoachLimits.longRunCeiling)
            // Convert both sides at the easy pace so caps on either side bind.
            if let pace = context.easyPace {
                let amount = Load(long.amount(in: unit), in: unit, pace: pace)
                long = amount.capped(at: long)
            }
            targets.longRun = long
            if long.amount(in: unit) <= context.longest.amount(in: unit) + 0.000_1 { targets.isNewLongest = false }
        }

        // HL-11: the session cap for the first 12 weeks of regular running.
        if state.assessment.overlays.earlyWindow, state.ladder == nil || state.ladder?.form == .done,
           RunnerAssessor.regularWeeks(before: context.weekIndex, state: state, sessions: context.sessions, calendar: context.calendar) < CoachLimits.earlyWindowWeeks {
            let seconds = targets.form == .continuous ? CoachLimits.earlyWindowRunSeconds : CoachLimits.earlyWindowRunWalkSeconds
            let cap = Load(meters: 0, seconds: seconds)
            targets.sessionCap = targets.sessionCap.map { InjuryCoach.tighter($0, cap) } ?? cap
            if !state.shownOnce.contains("earlyWindow") {
                targets.notes.append(CoachNote(.limit, "For now your runs stay at 30 minutes or less. Short, regular runs let your legs adapt before we add more."))
            }
        }

        targets.volume = max(0, targets.volume)
        fitRuns(&targets, context: context)
        return targets
    }

    /// HL-2, HL-6 and EV-6 together: every run is at least 20 minutes, so when the week's limit can't give each run
    /// 20 minutes, runs drop one at a time (easy runs first, then quality, AD-11's order) instead of the week going
    /// over. The limit is HL-2's cap, or in the race week the dead week's share of peak. The long run can still
    /// shrink to 20 minutes, and one run always stays.
    static func fitRuns(_ targets: inout WeekTargets, context: PlanningContext) {
        guard targets.form == .continuous, targets.runs > 1, ![.ladder, .habit, .paused].contains(targets.kind) else { return }
        let unit = context.unit
        let pace = context.easyPace ?? Scheduler.fallbackEasyPace
        let minimumRun = Load(CoachLimits.minimumRunSeconds, in: .time, pace: pace).amount(in: unit)
        let deadWeek = eventPhase(context) == .raceWeek && targets.race != nil
        let limit = deadWeek ? min(targets.volume, context.weekCap) : context.weekCap
        var test = false
        if case .test = targets.check { test = true }
        func fixedRuns() -> Int { (targets.race != nil || targets.longRun != nil ? 1 : 0) + targets.quality.count + (test ? 1 : 0) }
        func floor() -> Double {
            let long = targets.race == nil && targets.longRun != nil ? minimumRun : 0
            let quality = targets.quality.reduce(0) { $0 + max(minimumRun, Scheduler.qualityLoad($1, paces: context.state.paces).amount(in: unit)) }
            let others = Double(max(0, targets.runs - fixedRuns()) + (test ? 1 : 0))
            return long + quality + others * minimumRun
        }
        let before = targets.runs
        while targets.runs > 1, floor() > limit + 0.000_1 {
            if targets.runs > fixedRuns() {
                targets.runs -= 1
            } else if !targets.quality.isEmpty {
                targets.quality.removeLast()
                targets.runs -= 1
            } else {
                break
            }
        }
        guard targets.runs < before else { return }
        let runs = targets.runs - (targets.race == nil ? 0 : 1)
        let count = runs == 1 ? "1 run" : "\(runs) runs"
        targets.notes.append(CoachNote(.limit, deadWeek
            ? (runs == 0 ? "Race week stays at half your usual distance, so the race is your only run." : "Race week stays at half your usual distance, so it has \(count) before the race, each at least 20 minutes.")
            : "This week has \(count), so each can be at least 20 minutes inside your weekly limit."))
    }
}
