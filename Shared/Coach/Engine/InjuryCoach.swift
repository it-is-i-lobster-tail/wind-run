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
}

/// Reporting an injury: reports, their questions, and the weeks they shape (AD-13, AD-14, HL-15, HL-18, TI-3b, TI-3c).
enum InjuryCoach {
    /// The injury window lasts 12 weeks from the first run back after an Intense or Severe report (TI-3c).
    static let windowWeeks = 12

    /// A new report (AD-13). The engine re-plans the current week after it, so AD-5 runs again at once.
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
        let report = InjuryReport(reportedAt: now, origin: origin, runID: runID, level: level, area: area, baseline: baseline(state: state, runs: runs, now: now, calendar: calendar))
        state.injuries.append(report)
        var questions: [CoachQuestion] = []
        switch level {
        case .mild:
            break
        case .intense:
            state.status = .paused(reason: .injury, since: now)
            questions.append(.medicalClearance(reportID: report.id))
        case .severe:
            state.status = .paused(reason: .injury, since: now)
        }
        return CoachUpdate(state: state, notes: [], questions: questions)
    }

    /// The values the report keeps through every level change (AD-13e).
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
        let current = state.weeks.last { $0.plan.start <= now }?.plan
        return InjuryBaseline(
            volumeUnit: state.volumeUnit,
            weekVolume: reference.volume,
            longRun: reference.longest,
            heldVolume: current?.plannedVolume,
            heldLongRun: current?.longRun,
            qualityDoses: state.quality.doses,
            ladderStep: state.ladder?.stepIndex,
            ranThirtyMinutesNonStop: state.assessment.runs30Minutes || QualityPlanner.ranThirtyMinutes(runs)
        )
    }

    static func answer(_ answer: InjuryAnswer, reportID: UUID, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        CoachUpdate(state: state)
    }

    static func setRecoveryPlan(_ settings: RecoveryPlanSettings, reportID: UUID, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        CoachUpdate(state: state)
    }

    static func setReturn(_ settings: ReturnSettings, reportID: UUID, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        CoachUpdate(state: state)
    }

    /// The weeks a recovery plan would give, before the runner confirms it (AD-14b).
    static func previewRecovery(_ settings: RecoveryPlanSettings, reportID: UUID, state: CoachState) -> [RecoveryWeekPreview] {
        []
    }

    /// The week while a report is open, or nil when no report shapes it. The most restrictive report wins (AD-13e).
    static func weekTargets(_ context: PlanningContext) -> WeekTargets? {
        let open = context.state.openInjuries
        guard let worst = open.max(by: { $0.level < $1.level }) else { return nil }
        switch worst.level {
        case .severe, .intense:
            return .paused(notes: [CoachNote(.injury, "No running for now, because you need a break from running for your injury. Your plan is paused, not lost. Tap 'Ready' when you want to start back.")])
        case .mild:
            let unit = context.unit
            let volume = worst.baseline.heldVolume ?? worst.baseline.weekVolume
            let long = worst.baseline.heldLongRun.map { $0.capped(at: context.longest) }
            return WeekTargets(
                kind: .hold,
                volume: volume,
                longRun: long.flatMap { $0.amount(in: unit) > 0 ? $0 : nil },
                runs: context.state.cycle.runsPerWeek,
                notes: [CoachNote(.injury, "Same targets as last week, because of your injury. Easy runs only until it clears.")]
            )
        }
    }

    /// The 12-week injury window after an Intense or Severe report (TI-3c): one level lower, 2-week holds.
    static func injuryWindowActive(_ state: CoachState, now: Date, calendar: Calendar) -> Bool {
        state.injuries.contains { report in
            guard report.everIntenseOrSevere, let firstRun = report.firstRunBack,
                  let end = calendar.date(byAdding: .weekOfYear, value: windowWeeks, to: firstRun) else { return false }
            return now >= firstRun && now < end
        }
    }

    /// A saved run: the first run back after an Intense or Severe report starts the injury window (TI-3c).
    static func runLogged(_ run: LoggedRun, state: CoachState, now: Date, calendar: Calendar) -> CoachUpdate {
        CoachUpdate(state: state)
    }

    /// Week-end work for open reports: their weekly checks and the follow-up timers. May be called again for
    /// the same week after a late check-in, so it must not apply anything twice.
    static func weekEnded(_ index: Int, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        CoachUpdate(state: state)
    }

    /// AD-5's injury rows, or nil when no report sets the outcome.
    static func outcome(_ state: CoachState) -> (WeekOutcome, OutcomeReason)? {
        let open = state.openInjuries
        if open.contains(where: { $0.level == .severe }) { return (.pause, .severeInjury) }
        if let intense = open.first(where: { $0.level == .intense }) {
            return intense.clearance == .yes ? (.recoveryPlan, .intenseCleared) : (.pause, .intenseNotCleared)
        }
        if open.contains(where: { $0.level == .mild }) { return (.hold, .mildInjury) }
        return nil
    }

    /// Questions the open reports are waiting on.
    static func questions(_ state: CoachState, now: Date, calendar: Calendar) -> [CoachQuestion] {
        state.openInjuries.compactMap { report in
            report.level == .intense && report.clearance == nil ? .medicalClearance(reportID: report.id) : nil
        }
    }
}
