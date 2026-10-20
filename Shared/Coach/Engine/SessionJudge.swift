//
//  SessionJudge.swift
//  Wind Run
//

import Foundation

/// FB-4g: every Q is judged on pace and RPE, first matching row wins. Heart rate never changes the row, and the
/// internal labels are never shown (FB-7).
enum SessionJudge {
    /// FB-4g's pace line, the same 3% as FB-4d's rep band and family E.
    static let paceLine = 0.03
    /// Under 75% of the work done is Failed.
    static let minimumCompletion = 0.75

    /// The judgement of a run matched to a Q, or nil when the session isn't one (a race, a test, a Q made easy).
    static func judge(_ run: LoggedRun, session: PlannedSession, week: Int, analysis: RunAnalysisResult, state: CoachState) -> SessionJudgement? {
        guard session.isQuality, let dose = session.dose, session.kind != .race, session.kind != .test else { return nil }
        let target = session.effort.targetRPE
        let rpe = run.rpe
        // "Conditions" sessions, and runs whose pace can't be trusted, go by RPE and completion only.
        let conditions = analysis.conditions || !analysis.check.allowsPaceAnalysis
        let work = RunAnalysis.workSteps(run)
        let done = completion(run, session: session, dose: dose, work: work)
        let stopped = [CutShortReason.tired, .unwellInHeat, .somethingHurt, .feltIll].contains { $0 == run.checkIn?.cutShort }
        let repCut = work.contains(where: \.cut) || (!dose.continuous && dose.reps > 1 && !work.isEmpty && work.count < dose.reps)
        let targetPace = session.paceBand?.middle
        let delta: Double? = conditions ? nil : targetPace.flatMap { target in workPace(work).map { ($0 - target) / target } }
        let reps = conditions ? nil : analysis.reps
        let faded = !conditions && (analysis.fade?.row == .marked || analysis.tempoFade != nil || reps?.lastSlow != nil)
        let previous = state.runReview.judgements
            .filter { $0.type == dose.type && $0.runID != run.id && $0.date < run.start }
            .max { $0.date < $1.date }

        let notFinished = stopped || done < minimumCompletion || repCut
        let outcome: SessionOutcome
        if stopped || done < minimumCompletion || (reps?.overFiveSlow ?? 0) >= 2 || (rpe ?? 0) >= target + 3 {
            outcome = .failed
        } else if repCut || rpe == target + 2 || faded || (delta ?? 0) > paceLine {
            outcome = previous?.outcome == .struggled ? .failed : .struggled
        } else if !conditions, targetPace != nil, delta != nil, !(reps?.any ?? false),
                  analysis.fade?.row != .mild, let rpe, session.effort.rpeRange.contains(rpe) {
            outcome = .evenAndOnTarget
        } else {
            outcome = .completed
        }
        let downTrigger = notFinished || (rpe ?? 0) >= target + 2
        let onTarget = delta.map { $0 <= paceLine } ?? false
        return SessionJudgement(
            runID: run.id,
            sessionID: session.id,
            date: run.start,
            weekIndex: week,
            type: dose.type,
            outcome: outcome,
            downTrigger: downTrigger,
            fewerReps: (downTrigger || outcome == .failed) && !conditions && targetPace == nil,
            easierThanTarget: onTarget && (outcome == .completed || outcome == .evenAndOnTarget) && (rpe.map { $0 <= target - 1 } ?? false),
            slow: (delta ?? 0) > paceLine,
            faded: faded,
            conditions: conditions
        )
    }

    /// Work done ÷ planned work: the work steps when the run has them, else moving time against the session.
    static func completion(_ run: LoggedRun, session: PlannedSession, dose: QualityDose, work: [LoggedStep]) -> Double {
        if !work.isEmpty, dose.workSeconds > 0 {
            return min(1, work.reduce(0) { $0 + $1.seconds } / dose.workSeconds)
        }
        guard session.target.seconds > 0 else { return 1 }
        return min(1, run.movingSeconds / session.target.seconds)
    }

    /// The work's average pace in seconds per km, or nil without step distances.
    static func workPace(_ work: [LoggedStep]) -> Double? {
        let measured = work.filter { $0.meters > 0 && $0.seconds > 0 }
        let meters = measured.reduce(0) { $0 + $1.meters }
        guard meters > 0 else { return nil }
        return measured.reduce(0) { $0 + $1.seconds } / meters * 1_000
    }

    /// A down-step: Failed, or PZ-7's down trigger (FB-4g, PZ-7: a second one in a row starts the fatigue check).
    static func isDownStep(_ judgement: SessionJudgement) -> Bool {
        judgement.outcome == .failed || judgement.downTrigger
    }

    /// The judgement before this one for the same type.
    static func previous(_ judgement: SessionJudgement, in judgements: [SessionJudgement]) -> SessionJudgement? {
        judgements
            .filter { $0.type == judgement.type && $0.runID != judgement.runID && $0.date < judgement.date }
            .max { $0.date < $1.date }
    }
}
