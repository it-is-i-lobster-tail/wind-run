//
//  InjuryCoach.swift
//  Wind Run
//

import Foundation

/// An answer to one of the injury questions (AD-13a to AD-14c).
enum InjuryAnswer: Codable, Hashable {
    /// "Are you medically cleared to keep training?" (AD-13b)
    case clearance(ClearanceAnswer)
    /// Mild's weekly check (AD-13a).
    case mildCheck(MildCheckAnswer)
    /// Intense's and the Severe return's weekly check (AD-13b, AD-14c).
    case recoveryCheck(RecoveryCheckAnswer)
    /// "Ready to run again?" (AD-13c)
    case ready(Bool)
    /// The one-week follow-up after a Mild report clears (AD-14a).
    case followUp(FollowUpAnswer)
    /// The runner's choice after a suggestion (AD-13a, AD-13b).
    case suggestion(InjurySuggestionChoice)
    /// The runner moved the report to another level.
    case level(InjuryLevel)
}

/// One week of a recovery plan, for the recovery plan screen's preview (AD-14b, AD-14c).
struct RecoveryWeekPreview: Codable, Hashable {
    /// 1 for the first week of the recovery.
    var weekNumber: Int
    /// Share of the pre-injury week, 0 for a week off.
    var share: Double
    /// Planned running in the plan's unit.
    var volume: Double
    var longRun: Load?
    /// "Week 1: no running", "Week 2: 50%".
    var label: String
    /// The unit of `volume`: running minutes for a jog/walk or ladder week (AD-14c, AD-18), else the plan's unit.
    var volumeUnit: VolumeUnit
    /// HL-1 or HL-2 held this week below the plan's share (AD-14b's projection).
    var capped: Bool

    init(weekNumber: Int, share: Double, volume: Double, longRun: Load? = nil, label: String, volumeUnit: VolumeUnit = .distance, capped: Bool = false) {
        self.weekNumber = weekNumber
        self.share = share
        self.volume = volume
        self.longRun = longRun
        self.label = label
        self.volumeUnit = volumeUnit
        self.capped = capped
    }
}

/// Reporting an injury: reports, their questions, and the weeks they shape (AD-13, AD-14, HL-15, HL-18, TI-3b, TI-3c).
enum InjuryCoach {
    /// The injury window lasts 12 weeks from the first run back after an Intense or Severe report (TI-3c).
    static let windowWeeks = 12
    /// Marks a planning probe: the rules after this module shape the week, then the open reports limit it.
    static let chainSentinel = "chain.injury"

    // MARK: Reporting (AD-13, AD-13e, AD-13g)

    /// A new report (AD-13). Reporting again at an area with an open report changes that report's level instead
    /// (AD-13e). The engine re-plans the current week after it, so AD-5 runs again at once.
    static func report(
        level: InjuryLevel,
        area: InjuryArea?,
        origin: InjuryOrigin,
        runID: UUID?,
        state: CoachState,
        runs: [LoggedRun],
        now: Date,
        calendar: Calendar
    ) -> CoachUpdate {
        var state = state
        var notes: [CoachNote] = []
        var questions: [CoachQuestion] = []

        if let position = state.injuries.lastIndex(where: { !$0.status.isClosed && $0.area == area }) {
            if state.injuries[position].level != level {
                let change = changeLevel(position, to: level, suggested: false, state: &state, runs: runs, now: now, calendar: calendar)
                notes += change.notes
                questions += change.questions
            } else {
                if state.injuries[position].clearedDate != nil, state.injuries[position].mode != .returning {
                    reopen(position, state: &state, now: now, calendar: calendar)
                }
                state.injuries[position].events.append(InjuryEvent(date: now, kind: .reported(level)))
                let report = state.injuries[position]
                switch report.mode {
                case .awaitingClearance: questions.append(.medicalClearance(reportID: report.id))
                case .paused: notes.append(Notes.severePause)
                case .mild: notes.append(Notes.mildStart)
                default: break
                }
            }
        } else {
            let report = InjuryReport(
                reportedAt: now,
                origin: origin,
                runID: runID,
                level: level,
                area: area,
                baseline: baseline(state: state, runs: runs, now: now, calendar: calendar)
            )
            state.injuries.append(report)
            let position = state.injuries.count - 1
            switch level {
            case .severe:
                pause(position, state: &state, runs: runs, now: now)
                notes.append(Notes.severePause)
            case .intense:
                questions.append(.medicalClearance(reportID: report.id))
            case .mild:
                notes.append(Notes.mildStart)
            }
            if let note = routeNote(state.injuries[position]) { notes.append(note) }
            // AD-13g: a third report at the same area within 6 months.
            if let area, area != .other {
                let since = calendar.date(byAdding: .month, value: -6, to: now) ?? now
                if state.injuries.filter({ $0.area == area && $0.reportedAt >= since }).count >= 3 {
                    notes += suggestPhysio(position, state: &state, now: now)
                }
            }
        }
        notes += settle(&state, now: now, calendar: calendar)
        return CoachUpdate(state: state, notes: unique(notes), questions: questions)
    }

    /// The values the report keeps through every level change (AD-13e, AD-14b): AD-10's reference week and long run,
    /// the report week's planned level for Mild, the Q doses, and the ladder step.
    static func baseline(state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> InjuryBaseline {
        let sessions = LoadMetrics.sessions(from: RunDataGate.usableRuns(runs))
        let reference = LoadMetrics.gapReference(
            gapStart: now,
            planStart: state.startDate,
            sessions: sessions,
            unit: state.volumeUnit,
            pace: state.paces.easyPace,
            seed: WeekPlanner.seed(for: state),
            fallbackVolume: state.v0,
            fallbackLongest: state.assessment.start.planningLongest,
            calendar: calendar
        )
        let current = state.weeks.last { $0.plan.start <= now && $0.plan.plannedVolume > 0 && $0.plan.kind != .paused }?.plan
        let held = heldLevel(current, state: state)
        let monthAgo = calendar.date(byAdding: .day, value: -LoadMetrics.windowDays, to: now) ?? now
        let recent = runs.filter { $0.start >= monthAgo && $0.start <= now }
        let ladder = state.ladder.flatMap { $0.form == .done ? nil : $0 }
        return InjuryBaseline(
            volumeUnit: state.volumeUnit,
            weekVolume: reference.volume,
            longRun: reference.longest,
            heldVolume: held.volume,
            heldLongRun: held.longRun,
            qualityDoses: state.quality.doses,
            ladderStep: ladder?.stepIndex,
            ranThirtyMinutesNonStop: recent.isEmpty ? state.assessment.runs30Minutes : QualityPlanner.ranThirtyMinutes(recent),
            ladderForm: ladder?.form,
            walkMinutes: ladder?.form == .walkStage ? ladder?.walkMinutes : nil
        )
    }

    /// AD-13a's held level: the report week's planned volume and long run, or the level before it when that week is
    /// a planned step-back, as AD-5 HOLD holds after one (the step-back week itself still comes).
    static func heldLevel(_ week: PlannedWeek?, state: CoachState) -> (volume: Double?, longRun: Load?) {
        guard let week, week.plannedVolume > 0 else { return (nil, nil) }
        if week.kind == .stepBack, state.cycle.lastLoadingVolume > week.plannedVolume {
            return (state.cycle.lastLoadingVolume, state.cycle.lastLoadingLongRun)
        }
        return (week.plannedVolume, week.longRun)
    }

    // MARK: Answers (AD-13a to AD-14c)

    static func answer(_ answer: InjuryAnswer, reportID: UUID, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        guard let position = state.injuries.firstIndex(where: { $0.id == reportID }), !state.injuries[position].status.isClosed else {
            return CoachUpdate(state: state)
        }
        var notes: [CoachNote] = []
        var questions: [CoachQuestion] = []
        let report = state.injuries[position]
        let week = checkWeek(state, now: now, calendar: calendar)

        switch answer {
        case .clearance(let clearance):
            guard report.mode == .awaitingClearance else { break }
            state.injuries[position].clearance = clearance
            state.injuries[position].events.append(InjuryEvent(date: now, kind: .clearance(clearance)))
            guard clearance == .yes else {
                // AD-13b: No or Not sure is Severe.
                _ = changeLevel(position, to: .severe, suggested: false, state: &state, runs: runs, now: now, calendar: calendar)
                notes.append(CoachNote(.injury, "Then let's pause your plan until you're ready."))
                break
            }
            if report.pauseStart != nil, report.readyAt == nil {
                // A Severe pause moved down to Intense comes back the way Ready does (AD-13e).
                notes += startReturn(position, state: &state, now: now, calendar: calendar)
            } else if report.returnStart == nil {
                // AD-13b: the default recovery plan starts now; the runner can change it at any time.
                state.injuries[position].recoveryStart = now
                state.injuries[position].recoveryPlan = nil
                state.injuries[position].ladderRestart = nil
                questions.append(.recoveryPlan(reportID: reportID))
                restartLadderIfDue(position, state: &state, now: now, calendar: calendar)
            }

        case .mildCheck(let check):
            guard report.level == .mild, report.status.isOpen else { break }
            state.injuries[position].events.append(InjuryEvent(date: now, kind: .mildCheck(check), week: week))
            switch check {
            case .cleared:
                state.injuries[position].status = .cleared(on: now)
                state.injuries[position].pendingSuggestion = nil
                if report.mode == .returning {
                    notes.append(CoachNote(.injury, "Great news. Your runs keep building back to your usual week, and I'll check again in a week."))
                } else if state.goal.flavor != .buildDistance, !state.quality.doses.isEmpty {
                    notes.append(CoachNote(.injury, "Great news. Speed work comes back a little lighter this week, and I'll check again in a week."))
                } else {
                    notes.append(CoachNote(.injury, "Great news. Your usual runs are back this week, and I'll check again in a week."))
                }
            case .stillThere:
                break
            case .worse:
                state.injuries[position].pendingSuggestion = InjurySuggestion(kind: .switchToIntense, week: week)
                questions.append(.suggestIntense(reportID: reportID))
            }
            let updated = state.injuries[position]
            let unclear = updated.events.filter { if case .mildCheck(let answer) = $0.kind { answer != .cleared } else { false } }.count
            if unclear >= 3 || worseAnswers(updated) >= 2 { notes += suggestPhysio(position, state: &state, now: now) }

        case .recoveryCheck(let check):
            guard report.mode == .recoveryPlan || report.mode == .returning else { break }
            let previous = report.events.last { if case .recoveryCheck = $0.kind { true } else { false } }
            state.injuries[position].events.append(InjuryEvent(date: now, kind: .recoveryCheck(check), week: week))
            switch check {
            case .worse:
                state.injuries[position].pendingSuggestion = InjurySuggestion(kind: .repeatOrPause, week: week)
                questions.append(.suggestRepeatOrPause(reportID: reportID))
            case .same:
                // "Same" twice in a row in the ramp: suggest repeating the week (AD-13b).
                let inRamp = stage(report, week: week, state: state, calendar: calendar)?.isRamp == true
                    && stage(report, week: week - 1, state: state, calendar: calendar)?.isRamp == true
                if inRamp, previous?.kind == .recoveryCheck(.same), previous?.week == week - 1 {
                    state.injuries[position].pendingSuggestion = InjurySuggestion(kind: .repeatWeek, week: week)
                    questions.append(.suggestRepeat(reportID: reportID))
                }
            case .better:
                break
            }
            if worseAnswers(state.injuries[position]) >= 2 { notes += suggestPhysio(position, state: &state, now: now) }

        case .ready(let ready):
            switch report.mode {
            case .paused:
                if ready {
                    notes += startReturn(position, state: &state, now: now, calendar: calendar)
                } else {
                    state.injuries[position].events.append(InjuryEvent(date: now, kind: .ready(false)))
                    notes.append(CoachNote(.injury, "No rush. I'll ask again next week, or tap Ready whenever you are."))
                }
            case .awaitingClearance:
                // An Intense report restarts through the medical question (AD-13b).
                questions.append(.medicalClearance(reportID: reportID))
            default:
                break
            }

        case .followUp(let followUp):
            guard report.clearedDate != nil, report.mode != .returning else { break }
            state.injuries[position].events.append(InjuryEvent(date: now, kind: .followUp(followUp), week: week))
            switch followUp {
            case .stillClear:
                // AD-14a: the report closes and progression resumes (HL-15).
                state.injuries[position].status = .closed(on: now)
                state.injuries[position].events.append(InjuryEvent(date: now, kind: .closed, week: week))
                notes.append(Notes.closed(report))
            case .itsBack:
                reopen(position, state: &state, now: now, calendar: calendar)
                notes.append(Notes.mildStart)
            }

        case .suggestion(let choice):
            let pending = report.pendingSuggestion
            state.injuries[position].events.append(InjuryEvent(date: now, kind: .suggestion(choice), week: week))
            state.injuries[position].pendingSuggestion = nil
            switch choice {
            case .switchToIntense, .pausePlan:
                let level: InjuryLevel = choice == .switchToIntense ? .intense : .severe
                let change = changeLevel(position, to: level, suggested: true, state: &state, runs: runs, now: now, calendar: calendar)
                notes += change.notes
                questions += change.questions
            case .repeatWeek:
                notes += repeatWeek(position, week: pending?.week ?? week, state: &state, now: now, calendar: calendar)
            case .keepGoing:
                break
            }

        case .level(let level):
            let change = changeLevel(position, to: level, suggested: false, state: &state, runs: runs, now: now, calendar: calendar)
            notes += change.notes
            questions += change.questions
        }

        notes += settle(&state, now: now, calendar: calendar)
        return CoachUpdate(state: state, notes: unique(notes), questions: questions)
    }

    /// The runner shapes the Intense recovery plan, faster or slower, at any time (AD-14b). The rest of the plan is
    /// planned again at once, with a new end date.
    static func setRecoveryPlan(_ settings: RecoveryPlanSettings, reportID: UUID, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        guard let position = state.injuries.firstIndex(where: { $0.id == reportID }), state.injuries[position].mode == .recoveryPlan else {
            return CoachUpdate(state: state)
        }
        let settings = settings.normalized
        let previous = recoverySettings(state.injuries[position])
        state.injuries[position].recoveryPlan = settings
        if state.injuries[position].recoveryStart == nil { state.injuries[position].recoveryStart = now }
        state.injuries[position].events.append(InjuryEvent(date: now, kind: .recoveryPlanSet(settings)))
        restartLadderIfDue(position, state: &state, now: now, calendar: calendar)
        if settings.ladderStepsBack != previous.ladderStepsBack {
            reapplyRestart(position, stepsBack: settings.ladderStepsBack, state: &state)
        }
        var notes = planChangedNotes(position, state: state, now: now, calendar: calendar)
        notes += settle(&state, now: now, calendar: calendar)
        return CoachUpdate(state: state, notes: unique(notes))
    }

    /// The runner shapes the Severe return (AD-14c), before Ready or during it.
    static func setReturn(_ settings: ReturnSettings, reportID: UUID, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        guard let position = state.injuries.firstIndex(where: { $0.id == reportID }) else { return CoachUpdate(state: state) }
        let mode = state.injuries[position].mode
        guard mode == .paused || mode == .returning else { return CoachUpdate(state: state) }
        let settings = settings.normalized
        let previous = returnSettings(state.injuries[position], calendar: calendar)
        state.injuries[position].returnPlan = settings
        state.injuries[position].events.append(InjuryEvent(date: now, kind: .returnSet(settings)))
        var notes: [CoachNote] = []
        if mode == .returning {
            if settings.ladderStepsBack != previous.ladderStepsBack {
                let days = pauseDays(state.injuries[position], now: now, calendar: calendar)
                reapplyRestart(position, stepsBack: settings.ladderStepsBack ?? gapStepsBack(days: days), state: &state)
            }
            notes += planChangedNotes(position, state: state, now: now, calendar: calendar)
        }
        notes += settle(&state, now: now, calendar: calendar)
        return CoachUpdate(state: state, notes: unique(notes))
    }

    /// The weeks a recovery plan would give, before the runner confirms it (AD-14b): every hard limit applied and
    /// each week assumed done as planned. Empty only when the report isn't found.
    static func previewRecovery(_ settings: RecoveryPlanSettings, reportID: UUID, state: CoachState) -> [RecoveryWeekPreview] {
        guard let report = state.injuries.first(where: { $0.id == reportID }) else { return [] }
        return recoveryProjection(settings, report: report, state: state).weeks
    }

    /// The weeks a Severe return would give (AD-14c): the return weeks, then the ramp until 100%, with HL-1 and HL-2
    /// applied as AD-14c's example shows. Before Ready the pause counts to `now`, or to the latest planned week's start.
    static func previewReturn(_ settings: ReturnSettings, reportID: UUID, state: CoachState, now: Date? = nil, calendar: Calendar? = nil) -> [RecoveryWeekPreview] {
        guard let report = state.injuries.first(where: { $0.id == reportID }) else { return [] }
        let days = pauseDays(report, now: now ?? state.weeks.last?.plan.start ?? report.reportedAt, calendar: calendar)
        return returnProjection(settings, report: report, state: state, pauseDays: days).weeks
    }

    // MARK: The weeks (AD-13a to AD-14c, HL-15, HL-18)

    /// The week while a report is open, or nil when no report shapes it. The most restrictive report wins (AD-13e).
    static func weekTargets(_ context: PlanningContext) -> WeekTargets? {
        weekPlan(context)?.targets
    }

    /// The week while a report is open and the cycle it leaves, or nil when no report shapes it (AD-13e, HL-18).
    /// A Severe pause or an Intense report waiting on the medical question pauses running; recovery plans and returns
    /// replace the table; Mild and the weeks after "Cleared" limit the plan's own week, whose cycle moves on as a
    /// HOLD (HL-4).
    static func weekPlan(_ context: PlanningContext) -> (targets: WeekTargets, cycle: CycleState)? {
        let state = context.state
        guard !state.shownOnce.contains(chainSentinel) else { return nil }
        let open = state.openInjuries
        guard !open.isEmpty else { return nil }
        let cycle = state.cycle

        if open.contains(where: { $0.mode == .paused }) {
            return (.paused(notes: [CoachNote(.injury, "No running for now, because you need a break from running for your injury. Your plan is paused until you're ready to come back; tap Ready whenever you are.")]), cycle)
        }
        if open.contains(where: { $0.mode == .awaitingClearance }) {
            return (.paused(notes: [CoachNote(.injury, "No running for now, because you're not cleared to train yet. Your plan is paused until you answer the medical question.")]), cycle)
        }
        // Illness, heat and fatigue pauses come next in the chain.
        if state.status.isPaused || state.activeIllness?.stopsRunning == true { return nil }

        // Recovery plans and returns replace the table (AD-14b, AD-14c); ladder runners keep their steps (AD-18).
        var explicit: WeekTargets?
        for report in open.sorted(by: { $0.level > $1.level }) {
            guard let stage = stage(report, week: context.weekIndex, state: state, calendar: context.calendar) else { continue }
            if report.baseline.isLadder, ladderActive(state), !(stage.isRest && report.mode == .recoveryPlan) { continue }
            let targets = recoveryTargets(report, stage: stage, context: context)
            explicit = explicit.map { stricter($0, targets) } ?? targets
        }
        if var targets = explicit {
            for report in open where isMildHold(report) {
                targets.volume = min(targets.volume, report.heldVolume)
                if let held = report.baseline.heldLongRun { targets.longRun = targets.longRun.map { tighter($0, held) } }
            }
            var illnessContext = context
            illnessContext.state.shownOnce.insert(chainSentinel)
            if let illness = IllnessCoach.weekTargets(illnessContext) { targets = stricter(targets, illness) }
            targets.notes += open.compactMap(routeNote)
            return (unique(targets), cycle)
        }

        // Mild (AD-13a) and the weeks after "Cleared" (AD-14a) limit the plan's own week.
        let mild = open.filter { holds($0, week: context.weekIndex, state: state, calendar: context.calendar) }
        let cleared = open.filter { report in isMildHold(report) && !mild.contains { $0.id == report.id } }
        guard !mild.isEmpty || !cleared.isEmpty, !ladderActive(state) else { return nil }
        var probeContext = context
        probeContext.state.shownOnce.insert(chainSentinel)
        probeContext.state.injuries.removeAll { report in cleared.contains { $0.id == report.id } }
        let probe = WeekPlanner.weekTargets(probeContext)
        guard probe.0.kind != .paused, probe.0.runs > 0 else { return nil }

        var targets = probe.0
        var nextCycle = probe.1
        targets.isNewLongest = false
        if targets.kind == .loading {
            // HL-15: no loading week while a report is open or before the follow-up; a HOLD doesn't move the cycle on.
            targets.kind = .hold
            targets.cycleWeek = nil
            targets.runs = min(targets.runs, state.cycle.runsPerWeek)
            nextCycle.position = state.cycle.position
            nextCycle.runsPerWeek = state.cycle.runsPerWeek
            nextCycle.lastRunAddedWeek = state.cycle.lastRunAddedWeek
        }
        for report in mild + cleared {
            targets.volume = min(targets.volume, report.heldVolume)
            if var long = targets.longRun {
                if context.longest.amount(in: context.unit) > 0 { long = long.capped(at: context.longest) }
                if let held = report.baseline.heldLongRun { long = tighter(long, held) }
                targets.longRun = long
            }
        }
        if !mild.isEmpty {
            // AD-13a: every run easy, with no Q or strides.
            targets.quality = []
            targets.strides = 0
            if cleared.isEmpty, targets == probe.0 { return nil }
            let latest = mild.max { $0.levelChangedAt < $1.levelChangedAt }
            targets.notes.append(CoachNote(.injury, "Easy runs only this week, with no speed work, because of \(latest?.areaName ?? "your injury")."))
            targets.notes += mild.compactMap(routeNote)
        } else {
            // AD-14a: only the Q types the runner had, at 2/3 of their last dose in the week after "Cleared".
            targets.quality = targets.quality.filter { state.quality.dose(for: $0.type) != nil }
            if cleared.contains(where: { context.weekIndex <= clearedCheckWeek($0, state: state, calendar: context.calendar) + 1 }) {
                targets.quality = targets.quality.map(QualityPlanner.twoThirds)
            }
        }
        return (unique(withoutStaleNotes(targets)), nextCycle)
    }

    /// The planned volume of the first running week of a recovery plan or a Severe return, or nil for any other
    /// week. After a long pause or rest W4max has nothing to compare it with, so HL-2 lets it run at its share, as
    /// AD-10's first ramp week does (AD-14b, AD-14c).
    static func restartVolume(_ context: PlanningContext) -> Double? {
        let state = context.state
        let restarts = state.openInjuries.contains { report in
            guard let first = firstRecoveryWeek(report, state: state, calendar: context.calendar),
                  stage(report, week: context.weekIndex, state: state, calendar: context.calendar) != nil else { return false }
            let week = max(0, context.weekIndex - first)
            return report.mode == .returning ? week == 0 : week == recoverySettings(report).restWeeks
        }
        guard restarts, let plan = weekPlan(context), plan.targets.kind == .recovery || plan.targets.kind == .injuryReturn else { return nil }
        return plan.targets.volume
    }

    /// The 12-week injury window after an Intense or Severe report (TI-3c): one level lower, 2-week holds.
    static func injuryWindowActive(_ state: CoachState, now: Date, calendar: Calendar) -> Bool {
        state.injuries.contains { report in
            guard report.everIntenseOrSevere, let firstRun = report.firstRunBack,
                  let end = calendar.date(byAdding: .weekOfYear, value: windowWeeks, to: firstRun) else { return false }
            return now >= firstRun && now < end
        }
    }

    // MARK: Runs and week ends

    /// A saved run. During a Severe pause it counts for volume and caps, restarts nothing and brings "Ready to run
    /// again?" (AD-13c); the first run back after an Intense or Severe report starts the injury window (TI-3c).
    static func runLogged(_ run: LoggedRun, state: CoachState, now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        var notes: [CoachNote] = []
        var questions: [CoachQuestion] = []
        for position in state.injuries.indices where !state.injuries[position].status.isClosed {
            let report = state.injuries[position]
            if report.mode == .paused, let start = report.pauseStart, run.start >= start, run.start > (report.pauseRunAt ?? .distantPast) {
                state.injuries[position].pauseRunAt = run.start
                notes.append(CoachNote(.injury, "I see you went for a run. Ready to run again?"))
                questions.append(.readyToRun(reportID: report.id))
            }
            if report.everIntenseOrSevere, report.firstRunBack == nil, startsWindow(report, run: run, state: state, calendar: calendar) {
                state.injuries[position].firstRunBack = run.start
            }
        }
        return CoachUpdate(state: state, notes: unique(notes), questions: questions)
    }

    /// Week-end work for open reports (AD-13b, AD-14b, AD-14c, AD-18): suggestions expire, ladder runners restart
    /// after the rest phase, a return week that met AD-10's drop rule holds the ramp, and a recovery plan or return
    /// that reached the pre-injury week ends. May be called again for the same week after a late check-in, so it
    /// recomputes rather than repeats.
    static func weekEnded(_ index: Int, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        var notes: [CoachNote] = []
        let weekEnd = state.weekStart(index + 1, calendar: calendar)
        let record = state.weeks.first { $0.plan.index == index }

        for position in state.injuries.indices {
            let report = state.injuries[position]
            // A late review starts again from the state before this week's first review: apply its end again.
            if report.closedWeek == index || report.returnReachedAt == weekEnd {
                applyEnd(report, state: &state)
                continue
            }
            guard !report.status.isClosed else { continue }
            if let suggestion = report.pendingSuggestion, suggestion.week < index {
                state.injuries[position].pendingSuggestion = nil
            }
            if let restart = report.ladderRestart, restart.at >= weekEnd {
                applyLadder(restart, reportID: report.id, state: &state)
            } else if report.mode == .recoveryPlan, report.ladderRestart == nil, report.baseline.isLadder, ladderActive(state),
                      stage(report, week: index, state: state, calendar: calendar)?.isRest == true,
                      stage(report, week: index + 1, state: state, calendar: calendar)?.isRest == false {
                // AD-13b: after the rest phase the ladder restarts below the pre-injury step.
                let step = ladderRestartStep(report, stepsBack: recoverySettings(report).ladderStepsBack, state: state)
                setRestart(position, LadderRestart(at: weekEnd, stepIndex: step.stepIndex, walkMinutes: step.walkMinutes), state: &state)
            }
            if report.mode == .returning, let record, stage(report, week: index, state: state, calendar: calendar) != nil {
                // AD-10's drop rule in the return: "too hard", or soreness or fatigue over 5 on 2 or more days.
                let dropped = record.checkIn?.week == .tooHard || WeeklyReviewer.morningHighDays(record.plan, state: state, calendar: calendar) >= 2
                state.injuries[position].returnDropWeeks.removeAll { $0 == index }
                if dropped { state.injuries[position].returnDropWeeks.append(index) }
            }
            guard state.injuries[position].pendingSuggestion == nil,
                  reachedBaseline(state.injuries[position], week: index, state: state, runs: runs, now: now, calendar: calendar) else { continue }
            notes += end(position, week: index, at: weekEnd, state: &state, calendar: calendar)
        }
        notes += settle(&state, now: now, calendar: calendar)
        return CoachUpdate(state: state, notes: unique(notes))
    }

    /// AD-5's injury rows, or nil when no report sets the outcome.
    static func outcome(_ state: CoachState) -> (WeekOutcome, OutcomeReason)? {
        let modes = state.openInjuries.map(\.mode)
        if modes.contains(.paused) { return (.pause, .severeInjury) }
        if modes.contains(.awaitingClearance) { return (.pause, .intenseNotCleared) }
        if modes.contains(.recoveryPlan) || modes.contains(.returning) { return (.recoveryPlan, .intenseCleared) }
        if modes.contains(.mild) { return (.hold, .mildInjury) }
        if state.openInjuries.contains(where: isMildHold) { return (.hold, .mildCleared) }
        return nil
    }

    /// Questions the open reports are waiting on (AD-13a to AD-14c). Weekly checks come with the weekly check-in, and
    /// an unanswered one comes back the next week (AD-17).
    static func questions(_ state: CoachState, now: Date, calendar: Calendar) -> [CoachQuestion] {
        let window = checkWindow(state, now: now, calendar: calendar)
        var questions: [CoachQuestion] = []
        for report in state.openInjuries {
            if let suggestion = report.pendingSuggestion {
                switch suggestion.kind {
                case .switchToIntense: questions.append(.suggestIntense(reportID: report.id))
                case .repeatOrPause: questions.append(.suggestRepeatOrPause(reportID: report.id))
                case .repeatWeek: questions.append(.suggestRepeat(reportID: report.id))
                }
            }
            switch report.mode {
            case .awaitingClearance:
                questions.append(.medicalClearance(reportID: report.id))
            case .paused:
                if readyDue(report, now: now, calendar: calendar) { questions.append(.readyToRun(reportID: report.id)) }
            case .cleared(let date):
                if window != nil, let due = calendar.date(byAdding: .day, value: 6, to: date), now >= due {
                    questions.append(.mildFollowUp(reportID: report.id))
                }
            case .mild, .recoveryPlan, .returning:
                guard let week = window, !checked(report, week: week) else { break }
                let start = [report.levelChangedAt, report.recoveryStart, report.returnStart].compactMap { $0 }.max() ?? report.reportedAt
                if let latest = calendar.date(byAdding: .day, value: 3, to: state.weekStart(week, calendar: calendar)), start <= latest {
                    questions.append(.injuryCheck(reportID: report.id))
                }
            case .closed:
                break
            }
        }
        return questions
    }

    // MARK: Level changes and the way back (AD-13b, AD-13c, AD-13e, AD-14c)

    /// Moves a report up or down a level (AD-13e). Severe pauses at once; Intense starts AD-13b's question; Intense
    /// moved down to Mild ends the recovery plan at the current recovery week's level; a Severe pause moved down
    /// comes back the way Ready does.
    static func changeLevel(
        _ position: Int,
        to level: InjuryLevel,
        suggested: Bool,
        state: inout CoachState,
        runs: [LoggedRun],
        now: Date,
        calendar: Calendar
    ) -> (notes: [CoachNote], questions: [CoachQuestion]) {
        var report = state.injuries[position]
        let from = report.level
        guard from != level else { return ([], []) }
        let previous = report.mode
        let currentStage = stage(report, week: state.weekIndex(on: now, calendar: calendar), state: state, calendar: calendar)
        report.events.append(InjuryEvent(date: now, kind: .levelChanged(from: from, to: level, suggested: suggested)))
        report.level = level
        report.levelChangedAt = now
        report.pendingSuggestion = nil
        if report.clearedDate != nil { report.status = .open }
        if level >= .intense { report.everIntenseOrSevere = true }
        // TI-3c: a new Intense or Severe report restarts the window at the next first run back.
        if level > from { report.firstRunBack = nil }
        state.injuries[position] = report

        switch level {
        case .severe:
            pause(position, state: &state, runs: runs, now: now)
            return ([Notes.severePause], [])
        case .intense:
            state.injuries[position].clearance = nil
            if from == .mild, previous != .returning { clearWayBack(position, state: &state) }
            return ([], [.medicalClearance(reportID: report.id)])
        case .mild:
            switch previous {
            case .recoveryPlan:
                // AD-13e: Mild from the current recovery week's level (in phase 1, the first phase-2 week's).
                let settings = recoverySettings(report)
                let share = currentStage.map { $0.isRest ? settings.reducedShare : $0.share } ?? settings.reducedShare
                state.injuries[position].baseline.heldVolume = share * report.baseline.weekVolume
                state.injuries[position].baseline.heldLongRun = report.baseline.longRun.scaled(by: share)
                return ([CoachNote(.injury, "Got it. Your recovery plan ends here, and your runs stay easy at this week's distance until \(report.areaName) clears.")], [])
            case .paused:
                return (startReturn(position, state: &state, now: now, calendar: calendar), [])
            case .awaitingClearance where report.pauseStart != nil && report.readyAt == nil:
                return (startReturn(position, state: &state, now: now, calendar: calendar), [])
            case .returning:
                return ([], [])
            default:
                return ([Notes.mildStart], [])
            }
        }
    }

    /// AD-13c: the pause starts now. A new pause starts a new return at the next Ready (AD-14c).
    static func pause(_ position: Int, state: inout CoachState, runs: [LoggedRun], now: Date) {
        clearWayBack(position, state: &state)
        state.injuries[position].pauseStart = now
        state.injuries[position].lastRunBeforePause = runs.filter { $0.start <= now }.map(\.start).max()
    }

    /// Forgets a pause and its return, for a new pause or a Mild report moving up.
    static func clearWayBack(_ position: Int, state: inout CoachState) {
        state.injuries[position].pauseStart = nil
        state.injuries[position].lastRunBeforePause = nil
        state.injuries[position].readyAt = nil
        state.injuries[position].returnStart = nil
        state.injuries[position].returnReachedAt = nil
        state.injuries[position].returnPlan = nil
        state.injuries[position].returnDropWeeks = []
        state.injuries[position].pauseRunAt = nil
        state.injuries[position].ladderRestart = nil
    }

    /// "Ready": the return starts (AD-14c). Ladder and walk-stage runners restart by AD-18's gap rows instead.
    static func startReturn(_ position: Int, state: inout CoachState, now: Date, calendar: Calendar) -> [CoachNote] {
        state.injuries[position].readyAt = now
        state.injuries[position].returnStart = now
        state.injuries[position].returnReachedAt = nil
        state.injuries[position].returnDropWeeks = []
        state.injuries[position].events.append(InjuryEvent(date: now, kind: .ready(true)))
        let report = state.injuries[position]
        let settings = returnSettings(report, calendar: calendar)
        if report.baseline.isLadder, ladderActive(state) {
            let stepsBack = settings.ladderStepsBack ?? gapStepsBack(days: pauseDays(report, now: now, calendar: calendar))
            let step = ladderRestartStep(report, stepsBack: stepsBack, state: state)
            setRestart(position, LadderRestart(at: now, stepIndex: step.stepIndex, walkMinutes: step.walkMinutes), state: &state)
            let name = stepName(form: report.baseline.ladderForm ?? .runWalk, stepIndex: step.stepIndex, walkMinutes: step.walkMinutes)
            return [CoachNote(.injury, "Welcome back. For \(CoachFormat.weeks(settings.weeks)) we'll stay at \(name), then build back step by step. You can make it faster or slower any time.")]
        }
        let form = settings.form == .jogging ? "jogging" : "jog-walk sessions"
        let usual = state.volumeUnit == .distance ? "your usual distance" : "your usual running time"
        return [CoachNote(.injury, "Welcome back. For \(CoachFormat.weeks(settings.weeks)) we'll do easy \(form) at about \(CoachFormat.percent(settings.share)) of \(usual), then build back step by step. You can make it faster or slower any time.")]
    }

    /// "It's back", or the same level reported again after "Cleared": Mild again from this week's level (AD-14a).
    static func reopen(_ position: Int, state: inout CoachState, now: Date, calendar: Calendar) {
        state.injuries[position].status = .open
        state.injuries[position].levelChangedAt = now
        let index = state.weekIndex(on: now, calendar: calendar)
        let held = heldLevel(state.weeks.first { $0.plan.index == index }?.plan, state: state)
        if let volume = held.volume {
            state.injuries[position].baseline.heldVolume = volume
            state.injuries[position].baseline.heldLongRun = held.longRun
        }
    }

    /// "Repeat this week": the week's targets again, with a week added to its phase (AD-13b, AD-14b, AD-14c).
    static func repeatWeek(_ position: Int, week: Int, state: inout CoachState, now: Date, calendar: Calendar) -> [CoachNote] {
        let report = state.injuries[position]
        guard let stage = stage(report, week: week, state: state, calendar: calendar) else { return [] }
        switch report.mode {
        case .recoveryPlan:
            var settings = recoverySettings(report)
            switch stage {
            case .rest: settings.restWeeks += 1
            case .reduced: settings.reducedWeeks += 1
            case .ramp(let ramp, _): settings.repeatedRampWeeks.append(ramp)
            case .returnWeek: return []
            }
            state.injuries[position].recoveryPlan = settings
        case .returning:
            var settings = returnSettings(report, calendar: calendar)
            switch stage {
            case .returnWeek: settings.weeks += 1
            case .ramp(let ramp, _): settings.repeatedRampWeeks.append(ramp)
            case .rest, .reduced: return []
            }
            state.injuries[position].returnPlan = settings
        default:
            return []
        }
        state.injuries[position].events.append(InjuryEvent(date: now, kind: .weekAdded, week: week))
        return planChangedNotes(position, state: state, now: now, calendar: calendar)
    }

    /// "Done. Your recovery now ends on {date}.", and the safety-limit stretch when HL-1 and HL-2 add weeks (AD-14b).
    static func planChangedNotes(_ position: Int, state: CoachState, now: Date, calendar: Calendar) -> [CoachNote] {
        guard let result = projection(for: state.injuries[position], state: state, now: now, calendar: calendar) else { return [] }
        let endWeek = max(result.firstWeek + result.projection.weeks.count, state.weekIndex(on: now, calendar: calendar) + 1)
        let end = calendar.date(byAdding: .day, value: -1, to: state.weekStart(endWeek, calendar: calendar)) ?? now
        var notes = [CoachNote(.injury, "Done. Your recovery now ends on \(CoachFormat.date(end, calendar: calendar)).")]
        if result.projection.addedWeeks > 0 { notes.append(Notes.stretch(result.projection.addedWeeks)) }
        return notes
    }

    // MARK: Ends (AD-13b, AD-14b, AD-14c, TI-3c)

    /// Whether week `index` was the first week back at the pre-injury week with the long run back, as planned inside
    /// the hard limits; ladder runners are back on their pre-injury step (AD-14b, AD-14c, AD-18).
    static func reachedBaseline(_ report: InjuryReport, week index: Int, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> Bool {
        guard report.mode == .recoveryPlan || report.mode == .returning,
              let first = firstRecoveryWeek(report, state: state, calendar: calendar), index >= first,
              let stage = stage(report, week: index, state: state, calendar: calendar) else { return false }
        if report.baseline.isLadder, ladderActive(state) {
            let done = report.mode == .recoveryPlan ? recoverySettings(report).restWeeks : returnSettings(report, calendar: calendar).weeks - 1
            return index - first >= done && ladderBack(report, state: state)
        }
        guard stage.share >= 1 - 0.000_1 else { return false }
        let settings = report.mode == .returning ? returnSettings(report, calendar: calendar) : nil
        guard jogWalkPattern(stage, form: settings?.form) == nil else { return false }
        let context = WeekPlanner.makeContext(week: index, state: state, runs: runs, now: now, calendar: calendar)
        let week = WeekPlanner.applyLimits(recoveryTargets(report, stage: stage, context: context), context: context)
        let unit = state.volumeUnit
        let volumeBack = week.volume >= report.baseline.weekVolume * 0.999
        let longBack = (week.longRun?.amount(in: unit) ?? 0) >= report.baseline.longRun.amount(in: unit) * 0.999
        return volumeBack && longBack
    }

    /// The state AD-5 decides week `index` on: a recovery plan or return that reaches the pre-injury week this week
    /// ends at this week's review (`weekEnded`), so it no longer sets the outcome and the next week is planned
    /// without it (AD-14b, AD-14c).
    static func reviewState(_ state: CoachState, week index: Int, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachState {
        var reviewed = state
        let weekEnd = state.weekStart(index + 1, calendar: calendar)
        for position in state.injuries.indices {
            let report = state.injuries[position]
            guard !report.status.isClosed, (report.pendingSuggestion?.week ?? .min) < index,
                  reachedBaseline(report, week: index, state: state, runs: runs, now: now, calendar: calendar) else { continue }
            if report.level == .mild {
                reviewed.injuries[position].returnReachedAt = weekEnd
            } else {
                reviewed.injuries[position].status = .closed(on: weekEnd)
            }
        }
        return reviewed
    }

    /// The recovery plan or return reached the pre-injury week: an Intense or Severe report closes; a Mild report
    /// moved down from Severe stays open, held there, until it clears (AD-13e).
    static func end(_ position: Int, week index: Int, at date: Date, state: inout CoachState, calendar: Calendar) -> [CoachNote] {
        let report = state.injuries[position]
        var notes: [CoachNote] = []
        if report.level == .mild {
            state.injuries[position].returnReachedAt = date
            state.injuries[position].baseline.heldVolume = report.baseline.weekVolume
            state.injuries[position].baseline.heldLongRun = report.baseline.longRun
            state.injuries[position].events.append(InjuryEvent(date: date, kind: .returnReached, week: index))
        } else {
            state.injuries[position].status = .closed(on: date)
            state.injuries[position].closedWeek = index
            state.injuries[position].events.append(InjuryEvent(date: date, kind: .closed, week: index))
            notes.append(Notes.closed(report))
        }
        applyEnd(state.injuries[position], state: &state)
        // TI-3c: the window's limits shape the plan from here.
        let start = report.firstRunBack ?? date
        if let windowEnd = calendar.date(byAdding: .weekOfYear, value: windowWeeks, to: start), windowEnd > date {
            let weeks = Int((windowEnd.timeIntervalSince(date) / (7 * 86_400)).rounded(.up))
            notes.append(CoachNote(.injury, "For the next \(CoachFormat.weeks(weeks)) I'll build a little more slowly. A recent injury makes another one more likely, so this protects your progress."))
        }
        return notes
    }

    /// The plan picks up from the pre-injury week: a new cycle from it, Q from its first dose (AD-14d), no gap ramp.
    static func applyEnd(_ report: InjuryReport, state: inout CoachState) {
        state.cycle.position = 0
        state.cycle.loadingInRow = 0
        state.cycle.lastLoadingVolume = report.baseline.weekVolume
        state.cycle.lastLoadingLongRun = report.baseline.longRun
        state.cycle.preCutVolume = nil
        state.cycle.preCutLongRun = nil
        state.cycle.stepBackPending = false
        state.quality.doses = []
        state.quality.cleanWeeksAtOneQ = 0
        state.gap = nil
    }

    // MARK: Helpers

    /// After any change: TI-3b's memory, the way back that replaces AD-10's ramp, and the plan's status.
    static func settle(_ state: inout CoachState, now: Date, calendar: Calendar) -> [CoachNote] {
        let notes = applyRiskMemory(&state, now: now, calendar: calendar)
        if state.openInjuries.contains(where: setsWayBack) { state.gap = nil }
        syncPause(&state, now: now)
        return notes
    }

    /// An Intense or Severe report on its way back: its own steps replace AD-10's ramp (AD-10's injury returns).
    static func setsWayBack(_ report: InjuryReport) -> Bool {
        switch report.mode {
        case .paused, .awaitingClearance, .recoveryPlan, .returning: true
        case .mild, .cleared, .closed: false
        }
    }

    /// A Mild report, or a cleared one before its follow-up: it limits the plan's own week (AD-13a, AD-14a).
    static func isMildHold(_ report: InjuryReport) -> Bool {
        switch report.mode {
        case .mild, .cleared: true
        default: false
        }
    }

    /// Mild holds the week (AD-13a), as does "Cleared" until the week its check belongs to has ended (AD-14a).
    static func holds(_ report: InjuryReport, week index: Int, state: CoachState, calendar: Calendar) -> Bool {
        switch report.mode {
        case .mild: true
        case .cleared: index <= clearedCheckWeek(report, state: state, calendar: calendar)
        default: false
        }
    }

    /// The plan week of the check that answered "Cleared": quality comes back in the week after it (AD-14a).
    static func clearedCheckWeek(_ report: InjuryReport, state: CoachState, calendar: Calendar) -> Int {
        let event = report.events.last { $0.kind == .mildCheck(.cleared) }
        return event?.week ?? state.weekIndex(on: report.clearedDate ?? report.reportedAt, calendar: calendar)
    }

    /// The plan week a weekly check answered now belongs to: the week before on a week's first three days.
    static func checkWeek(_ state: CoachState, now: Date, calendar: Calendar) -> Int {
        let index = state.weekIndex(on: now, calendar: calendar)
        let offset = calendar.dateComponents([.day], from: state.weekStart(index, calendar: calendar), to: calendar.startOfDay(for: now)).day ?? 0
        return offset <= 2 && index > 0 ? index - 1 : max(0, index)
    }

    /// The plan week whose weekly check is open now, with the weekly check-in: its last day, or the next week's first
    /// three days (AD-3).
    static func checkWindow(_ state: CoachState, now: Date, calendar: Calendar) -> Int? {
        let index = state.weekIndex(on: now, calendar: calendar)
        guard index >= 0 else { return nil }
        let offset = calendar.dateComponents([.day], from: state.weekStart(index, calendar: calendar), to: calendar.startOfDay(for: now)).day ?? 0
        if offset >= 6 { return index }
        if offset <= 2, index > 0 { return index - 1 }
        return nil
    }

    static func checked(_ report: InjuryReport, week: Int) -> Bool {
        report.events.contains { event in
            guard event.week == week else { return false }
            switch event.kind {
            case .mildCheck, .recoveryCheck: return true
            default: return false
            }
        }
    }

    /// AD-13c: the weekly "Ready to run again?" card, and the same question after a run logged during the pause.
    static func readyDue(_ report: InjuryReport, now: Date, calendar: Calendar) -> Bool {
        guard let start = report.pauseStart else { return false }
        let lastAnswer = report.events.filter { $0.kind == .ready(false) && $0.date >= start }.map(\.date).max()
        if let run = report.pauseRunAt, run > (lastAnswer ?? start) { return true }
        guard let due = calendar.date(byAdding: .day, value: 7, to: max(start, lastAnswer ?? start)) else { return false }
        return now >= due
    }

    /// TI-3c: the first run after phase 1 of the recovery plan, the first return run, or any run after a move to Mild.
    static func startsWindow(_ report: InjuryReport, run: LoggedRun, state: CoachState, calendar: Calendar) -> Bool {
        switch report.mode {
        case .recoveryPlan:
            guard let start = report.recoveryStart, let first = firstRecoveryWeek(report, state: state, calendar: calendar) else { return false }
            let restWeeks = recoverySettings(report).restWeeks
            let afterRest = restWeeks == 0 ? start : state.weekStart(first + restWeeks, calendar: calendar)
            return run.start >= max(start, afterRest)
        case .returning:
            return run.start >= (report.returnStart ?? report.readyAt ?? .distantFuture)
        case .mild, .cleared:
            return run.start >= report.levelChangedAt
        case .paused, .awaitingClearance, .closed:
            return false
        }
    }

    static func worseAnswers(_ report: InjuryReport) -> Int {
        report.events.filter { $0.kind == .mildCheck(.worse) || $0.kind == .recoveryCheck(.worse) }.count
    }

    /// AD-13g: once per report, advice only.
    static func suggestPhysio(_ position: Int, state: inout CoachState, now: Date) -> [CoachNote] {
        guard !state.injuries[position].physioSuggested else { return [] }
        state.injuries[position].physioSuggested = true
        state.injuries[position].events.append(InjuryEvent(date: now, kind: .physioSuggested))
        return [CoachNote(.injury, "This has been hanging around. A physio can often help with injuries like this.")]
    }

    /// AD-13d's route changes, while the report limits the plan.
    static func routeNote(_ report: InjuryReport) -> CoachNote? {
        guard let area = report.area, area.avoidsHills || area.avoidsDownhills else { return nil }
        switch report.mode {
        case .mild, .recoveryPlan, .returning, .awaitingClearance: break
        case .paused, .cleared, .closed: return nil
        }
        let left = area.avoidsHills ? "hills" : "steep downhills"
        return CoachNote(.injury, "Because of your \(area.name), I'll suggest flat routes and leave out \(left) for now.")
    }

    // MARK: Ladder restarts (AD-13b, AD-18)

    /// An Intense recovery plan whose rest phase is over (or has none) restarts the ladder at once.
    static func restartLadderIfDue(_ position: Int, state: inout CoachState, now: Date, calendar: Calendar) {
        let report = state.injuries[position]
        guard report.mode == .recoveryPlan, report.ladderRestart == nil, report.baseline.isLadder, ladderActive(state),
              stage(report, week: state.weekIndex(on: now, calendar: calendar), state: state, calendar: calendar)?.isRest == false else { return }
        let step = ladderRestartStep(report, stepsBack: recoverySettings(report).ladderStepsBack, state: state)
        setRestart(position, LadderRestart(at: now, stepIndex: step.stepIndex, walkMinutes: step.walkMinutes), state: &state)
    }

    /// A new number of steps back moves a restart the runner hasn't climbed from yet (AD-13b, AD-14c).
    static func reapplyRestart(_ position: Int, stepsBack: Int?, state: inout CoachState) {
        let report = state.injuries[position]
        guard let restart = report.ladderRestart, let ladder = state.ladder, ladder.form != .done,
              ladder.stepIndex == restart.stepIndex, restart.walkMinutes.map({ abs(ladder.walkMinutes - $0) < 0.001 }) ?? true else { return }
        let step = ladderRestartStep(report, stepsBack: stepsBack, state: state)
        setRestart(position, LadderRestart(at: restart.at, stepIndex: step.stepIndex, walkMinutes: step.walkMinutes), state: &state)
    }

    static func setRestart(_ position: Int, _ restart: LadderRestart, state: inout CoachState) {
        state.injuries[position].ladderRestart = restart
        applyLadder(restart, reportID: state.injuries[position].id, state: &state)
    }

    /// Moves the ladder to the restart and marks the report handled, so the ladder's own injury rules don't
    /// apply it again (AD-13b, AD-14c).
    static func applyLadder(_ restart: LadderRestart, reportID: UUID, state: inout CoachState) {
        guard var ladder = state.ladder, ladder.form != .done else { return }
        let position = LadderPosition(form: ladder.form, stepIndex: restart.stepIndex, walkMinutes: restart.walkMinutes ?? ladder.walkMinutes)
        if position != ladder.position { ladder.move(to: position, on: restart.at, reason: .injury) }
        if !ladder.handledInjuries.contains(reportID) { ladder.handledInjuries.append(reportID) }
        state.ladder = ladder
    }

    // MARK: Combining weeks (AD-13e)

    /// The stricter of two weeks: the lower volume and long run (no long run wins), fewer runs, no Q or strides unless
    /// both allow them, the tighter session cap, run-walk or walking over continuous running, and every note.
    static func stricter(_ first: WeekTargets, _ second: WeekTargets) -> WeekTargets {
        var targets = first
        targets.volume = min(first.volume, second.volume)
        if let a = first.longRun, let b = second.longRun {
            targets.longRun = tighter(a, b)
        } else {
            targets.longRun = nil
        }
        targets.isNewLongest = first.isNewLongest && second.isNewLongest
        targets.runs = min(first.runs, second.runs)
        targets.quality = first.quality.isEmpty || second.quality.isEmpty ? [] : first.quality
        targets.strides = min(first.strides, second.strides)
        if first.form == .continuous { targets.form = second.form }
        if let a = first.sessionCap, let b = second.sessionCap {
            targets.sessionCap = tighter(a, b)
        } else {
            targets.sessionCap = first.sessionCap ?? second.sessionCap
        }
        targets.extras = first.extras + second.extras.filter { !first.extras.contains($0) }
        targets.minimumRestDays = [first.minimumRestDays, second.minimumRestDays].compactMap { $0 }.max()
        targets.notes = first.notes + second.notes
        return targets
    }

    /// The smaller of two loads on each side; a 0 side is unknown, so the other side's value stands.
    static func tighter(_ a: Load, _ b: Load) -> Load {
        func side(_ x: Double, _ y: Double) -> Double { x > 0 && y > 0 ? min(x, y) : max(x, y) }
        return Load(meters: side(a.meters, b.meters), seconds: side(a.seconds, b.seconds))
    }

    static func unique(_ notes: [CoachNote]) -> [CoachNote] {
        notes.reduce(into: []) { result, note in if !result.contains(note) { result.append(note) } }
    }

    static func unique(_ targets: WeekTargets) -> WeekTargets {
        var targets = targets
        targets.notes = unique(targets.notes)
        return targets
    }

    /// Drops the plan's own lines about a new longest run or added speed once an injury or illness limit has taken
    /// them out of the week.
    static func withoutStaleNotes(_ targets: WeekTargets) -> WeekTargets {
        var targets = targets
        let newLongest = targets.isNewLongest
        let speed = !targets.quality.isEmpty
        targets.notes.removeAll { note in
            note.topic == .plan
                && ((!newLongest && note.text.contains("your new longest")) || (!speed && note.text.hasPrefix("This week adds speed")))
        }
        return targets
    }

    /// The coach's injury lines ("What the coach says").
    enum Notes {
        static let mildStart = CoachNote(.injury, "Got it. Until it clears, your runs are all easy, with no speed work or hills, and your distance stays where it is. I'll check in each week.")
        static let severePause = CoachNote(.injury, "Your plan is paused until you're ready to come back. Rest up, and follow your doctor's or physio's advice if you're seeing one. Your goal and runs are saved.")

        static func closed(_ report: InjuryReport) -> CoachNote {
            guard let area = report.area, area != .other else { return CoachNote(.injury, "Your injury is closed. I'll keep it in mind for a while.") }
            return CoachNote(.injury, "Your \(area.name) injury is closed. I'll keep it in mind for a while.")
        }

        static func stretch(_ weeks: Int) -> CoachNote {
            CoachNote(.limit, "Your plan's safety limits add \(CoachFormat.weeks(weeks)): no week more than 20% above your biggest recent week, and no run more than 10% longer than your longest in the last month.")
        }
    }
}
