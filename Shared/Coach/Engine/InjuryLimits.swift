//
//  InjuryLimits.swift
//  Wind Run
//

import Foundation

/// How the open reports shape a ladder or walk-stage week, for the ladder module (AD-13a to AD-13c, AD-14c, AD-18).
enum LadderInjuryRule: Hashable {
    /// No running: a Severe pause, an Intense report waiting on the medical question, or the recovery plan's rest
    /// phase.
    case paused
    /// The current step repeats, with no step up: Mild, the week "Cleared" belongs to, and the Severe return's weeks.
    case holdStep
    /// The ladder climbs from its restart as BD-2b allows; the report ends once it is back on the pre-injury step or
    /// walks (nil when the report kept none).
    case climbBack(toStep: Int?, walkMinutes: Double?)

    /// Strictest first when several reports apply (AD-13e).
    var strictness: Int {
        switch self {
        case .paused: 2
        case .holdStep: 1
        case .climbBack: 0
        }
    }
}

/// The runs a week an open report lets the runner swap for a pain-free bike, pool or elliptical session (AD-14e).
enum CrossTrainingSwaps: Hashable {
    case none
    /// Mild: in place of up to 1 run a week.
    case oneRunAWeek
    /// Intense (phase 1 and any recovery run) and Severe (any time).
    case anyRun
}

extension InjuryCoach {
    /// TI-3b: an Intense or Severe report is remembered, with its risk points, for 12 months.
    static let memoryMonths = 12
    /// TI-3b: a Mild report's area is listed first for 3 months.
    static let mildMemoryMonths = 3
    /// TI-4, AD-14d: at a risk score of 2 or more, Q waits for 8 weeks with no open injury report.
    static let qualityWaitWeeks = 8
    /// AD-14c: a pause over 56 days re-asks intake (AD-10 G4, IN-22).
    static let newIntakeDays = 56

    /// "Want to swap today's run for a pain-free bike or pool session? Same minutes, same easy effort." (AD-14e)
    static let crossTrainingOffer = "Want to swap today's run for a pain-free bike or pool session? Same minutes, same easy effort."

    // MARK: Memory and risk points (TI-3b, TI-4)

    /// The day the report last became Intense or Severe: TI-3b's 12 months count from here.
    static func memoryStart(_ report: InjuryReport) -> Date? {
        report.events.compactMap { event -> Date? in
            switch event.kind {
            case .reported(let level) where level >= .intense: event.date
            case .levelChanged(_, let level, _) where level >= .intense: event.date
            default: nil
            }
        }.max()
    }

    /// TI-3b: an Intense or Severe report in the last 12 months.
    static func riskMemoryActive(_ state: CoachState, now: Date, calendar: Calendar) -> Bool {
        state.injuries.contains { report in
            guard let start = memoryStart(report), let end = calendar.date(byAdding: .month, value: memoryMonths, to: start) else { return false }
            return now >= start && now < end
        }
    }

    /// TI-3b, TI-4: while an Intense or Severe report is remembered, its 2 points put the runner in TI-4's row for a
    /// score of 2 or more: Gentle only (CL-3), at most 3 runs a week (HL-9), H weeks held in full and at most 1 Q a
    /// week (HL-7). When the 12 months end the points go, the levels open up to the new ceiling (the runner raises
    /// the level, CL-4) and the caps come back from the intake. An injury report never changes the tier (TI-6).
    static func applyRiskMemory(_ state: inout CoachState, now: Date, calendar: Calendar) -> [CoachNote] {
        let active = riskMemoryActive(state, now: now, calendar: calendar)
        var factors = state.assessment.risk.factors
        guard active != factors.contains(.recentInjury) else { return [] }
        if active {
            factors.insert(.recentInjury, at: 0)
        } else {
            factors.removeAll { $0 == .recentInjury }
        }
        state.assessment.risk = RiskScore(factors: factors)
        state.assessment.levels = levelOptions(state, now: now, calendar: calendar)

        guard active else {
            if !state.assessment.risk.isHigh {
                let intake = RunnerAssessor.assess(state.intake, now: now, calendar: calendar)
                state.assessment.runsCap = intake.runsCap
                state.assessment.qCap = intake.qCap
            }
            return []
        }
        state.assessment.runsCap = min(state.assessment.runsCap, 3)
        state.assessment.qCap = min(state.assessment.qCap, 1)
        state.cycle.runsPerWeek = max(1, min(state.cycle.runsPerWeek, state.assessment.runsCap))
        let ceiling = state.assessment.levels.ceiling
        guard state.level > ceiling else { return [] }
        state.levelChanges.append(LevelChange(date: now, from: state.level, to: ceiling))
        state.level = ceiling
        return [CoachNote(.level, "Your plan builds at \(ceiling.name) for now, because a recent injury makes another one more likely.")]
    }

    /// CL-3's preset and ceiling for the risk score, lowered by the recovery tier, an RB-6 drop and the injury window
    /// (TI-3c), as the intake assessment sets them.
    static func levelOptions(_ state: CoachState, now: Date, calendar: Calendar) -> LevelOptions {
        let assessment = state.assessment
        var preset: CommitmentLevel
        var ceiling: CommitmentLevel
        switch assessment.risk.points {
        case 0: (preset, ceiling) = (.steady, .ambitious)
        case 1: (preset, ceiling) = (.gentle, .steady)
        default: (preset, ceiling) = (.gentle, .gentle)
        }
        ceiling = min(ceiling, assessment.recovery.tier.levelCeiling)
        if let until = assessment.recovery.levelDropUntil, until > now { ceiling = ceiling.lower }
        if injuryWindowActive(state, now: now, calendar: calendar) { ceiling = min(ceiling.lower, .steady) }
        preset = min(preset, ceiling)
        let reason = ceiling < .ambitious ? assessment.risk.largestFactor?.reason ?? RiskFactor.recoveryReduced.reason : nil
        return LevelOptions(preset: preset, ceiling: ceiling, lockedReason: reason)
    }

    /// TI-4, AD-14d: at a risk score of 2 or more, Q waits until 8 weeks have passed with no open injury report.
    static func qualityWaits(_ state: CoachState, now: Date, calendar: Calendar) -> Bool {
        guard state.assessment.risk.isHigh, !state.injuries.isEmpty else { return false }
        guard state.openInjuries.isEmpty else { return true }
        let closed = state.injuries.compactMap { report -> Date? in
            if case .closed(let date) = report.status { return date }
            return nil
        }.max()
        guard let closed, let end = calendar.date(byAdding: .weekOfYear, value: qualityWaitWeeks, to: closed) else { return false }
        return now < end
    }

    /// TI-3b: the areas listed first on the Report injury screen, most recent first: an Intense or Severe report's
    /// for 12 months, a Mild report's for 3.
    static func rememberedAreas(_ state: CoachState, now: Date, calendar: Calendar) -> [InjuryArea] {
        var latest: [InjuryArea: Date] = [:]
        for report in state.injuries {
            guard let area = report.area, area != .other else { continue }
            let start: Date
            let months: Int
            if let memory = memoryStart(report) {
                (start, months) = (memory, memoryMonths)
            } else {
                let reported = report.events.filter { if case .reported = $0.kind { true } else { false } }.map(\.date).max()
                (start, months) = (reported ?? report.reportedAt, mildMemoryMonths)
            }
            guard let end = calendar.date(byAdding: .month, value: months, to: start), now >= start, now < end else { continue }
            latest[area] = max(latest[area] ?? start, start)
        }
        return latest.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.rawValue < $1.key.rawValue }.map(\.key)
    }

    // MARK: The plan's status (AD-5 PAUSE, AD-12, AD-13b, AD-13c)

    /// The plan pauses for an injury while any report stops running, then for an illness while the episode does, and
    /// comes back (to a fatigue pause at Level 2, else active) once neither does. Heat and fatigue pauses are left
    /// as they are; a complete or stopped plan is never changed.
    static func syncPause(_ state: inout CoachState, now: Date) {
        let current: PauseReason?
        let since: Date
        switch state.status {
        case .complete, .stopped: return
        case .active: (current, since) = (nil, now)
        case .paused(let reason, let date): (current, since) = (reason, date)
        }
        let needed: PauseReason?
        if state.openInjuries.contains(where: \.stopsRunning) {
            needed = .injury
        } else if state.activeIllness?.stopsRunning == true {
            needed = .illness
        } else {
            needed = nil
        }
        if let needed {
            if current != needed { state.status = .paused(reason: needed, since: now) }
        } else if current == .injury || current == .illness {
            state.status = state.fatigue.level >= 2 ? .paused(reason: .fatigue, since: since) : .active
        }
    }

    // MARK: Ladder and walk-stage runners (AD-13a, AD-13b, AD-14c, AD-18)

    /// How the open reports shape ladder week `index`, strictest first, or nil when none does: no running while a
    /// report stops running or in the recovery plan's rest phase; the step held while Mild, in the week "Cleared"
    /// belongs to and in the Severe return's weeks; otherwise the climb back from the restart.
    static func ladderRule(_ state: CoachState, week index: Int, calendar: Calendar) -> LadderInjuryRule? {
        var rule: LadderInjuryRule?
        for report in state.openInjuries {
            let climb = LadderInjuryRule.climbBack(toStep: report.baseline.ladderStep, walkMinutes: report.baseline.walkMinutes)
            let next: LadderInjuryRule?
            switch report.mode {
            case .paused, .awaitingClearance:
                next = .paused
            case .recoveryPlan:
                next = stage(report, week: index, state: state, calendar: calendar)?.isRest == false ? climb : .paused
            case .returning:
                if case .returnWeek = stage(report, week: index, state: state, calendar: calendar) { next = .holdStep } else { next = climb }
            case .mild, .cleared:
                next = holds(report, week: index, state: state, calendar: calendar) ? .holdStep : nil
            case .closed:
                next = nil
            }
            if let next, next.strictness > (rule?.strictness ?? -1) { rule = next }
        }
        return rule
    }

    /// AD-18: a ladder runner is back once on the pre-injury step or past it, and a walk-stage runner once back at
    /// the pre-injury walks or on to running.
    static func ladderBack(_ report: InjuryReport, state: CoachState) -> Bool {
        guard let ladder = state.ladder, ladder.form != .done else { return true }
        if report.baseline.ladderForm == .walkStage {
            return ladder.form != .walkStage || ladder.walkMinutes >= (report.baseline.walkMinutes ?? 0) - 0.001
        }
        return ladder.stepIndex >= (report.baseline.ladderStep ?? 0)
    }

    // MARK: What the screens show (AD-13b, AD-13d, AD-14c, AD-14e, FB-4n)

    /// AD-13b's recovery-plan offer, for the plan as set (the default until the runner changes it).
    static func recoveryOffer(_ report: InjuryReport, state: CoachState) -> String {
        let settings = recoverySettings(report)
        let tail = "Change anything that doesn't suit you, and make it faster or slower whenever you like."
        var parts: [String] = []
        if settings.restWeeks > 0 { parts.append("\(CoachFormat.weeks(settings.restWeeks)) off running") }
        if report.baseline.isLadder, ladderActive(state) {
            let step = ladderRestartStep(report, stepsBack: settings.ladderStepsBack, state: state)
            let name = stepName(form: report.baseline.ladderForm ?? .runWalk, stepIndex: step.stepIndex, walkMinutes: step.walkMinutes)
            let back = settings.ladderStepsBack == 0 ? "we restart at \(name)" : "we restart \(stepsBackName(settings.ladderStepsBack)) back, at \(name)"
            parts.append(parts.isEmpty ? back : "then \(back)")
            return "Here's a recovery plan: \(parts.joined(separator: ", ")). \(tail)"
        }
        let usual = state.volumeUnit == .distance ? "your usual distance" : "your usual running time"
        let share = abs(settings.reducedShare - 0.5) < 0.001 ? "half" : "\(CoachFormat.percent(settings.reducedShare)) of"
        parts.append("\(CoachFormat.weeks(settings.reducedWeeks)) at \(share) \(usual)")
        let ramp = recoveryProjection(settings, report: report, state: state).plannedWeeks - settings.restWeeks - settings.reducedWeeks
        parts.append(ramp > 0 ? "then \(CoachFormat.weeks(ramp)) building back" : "then straight back to \(usual)")
        return "Here's a recovery plan: \(parts.joined(separator: ", ")). \(tail)"
    }

    /// "two steps", "one step", "4 steps".
    static func stepsBackName(_ steps: Int) -> String {
        let words = ["no", "one", "two", "three", "four", "five"]
        let count = steps >= 0 && steps < words.count ? words[steps] : "\(steps)"
        return steps == 1 ? "\(count) step" : "\(count) steps"
    }

    /// AD-14e: the runs a week the open reports let the runner swap for cross-training, if pain-free.
    static func crossTrainingSwaps(_ state: CoachState) -> CrossTrainingSwaps {
        let modes = state.openInjuries.map(\.mode)
        if modes.contains(where: { [.paused, .awaitingClearance, .recoveryPlan, .returning].contains($0) }) { return .anyRun }
        if modes.contains(where: { $0 == .mild }) { return .oneRunAWeek }
        return .none
    }

    /// FB-4n: the cadence cue is offered with an open Mild or Intense report at the knee or shin, kept unless that
    /// report got worse ("Worse", or a move up a level), and stopped by any report at the calf or Achilles or the
    /// thigh or hamstring since.
    static func cadenceCueOffered(_ state: CoachState) -> Bool {
        state.openInjuries.contains { report in
            guard let area = report.area, area.offersCadenceCue, report.level <= .intense, worseAnswers(report) == 0 else { return false }
            let movedUp = report.events.contains { event in
                if case .levelChanged(let from, let to, _) = event.kind { return to > from }
                return false
            }
            let stopped = state.injuries.contains { other in
                (other.area == .calfAchilles || other.area == .thighHamstring) && other.reportedAt >= report.reportedAt
            }
            return !movedUp && !stopped
        }
    }

    /// AD-14c: a Severe pause over 56 days re-asks intake before the return (AD-10 G4, IN-22).
    static func needsNewIntake(_ report: InjuryReport, now: Date, calendar: Calendar) -> Bool {
        report.pauseStart != nil && pauseDays(report, now: now, calendar: calendar) > newIntakeDays
    }
}
