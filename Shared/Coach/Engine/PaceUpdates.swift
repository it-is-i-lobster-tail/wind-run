//
//  PaceUpdates.swift
//  Wind Run
//

import Foundation

/// One easy run as FB-4c reads it: how far it was faster than the easy band, and what says it wasn't easy.
struct EasyRunFact: Hashable {
    var runID: UUID
    var date: Date
    /// How much faster than the band's fast edge, when it's more than FB-2's 5% noise.
    var fast: Double?
    /// RPE 4 or more (5 or more within 48 h after leg work), or a failed talk test.
    var effortEvidence: Bool
    /// Decision-grade heart rate over the easy ceiling (PZ-12). Only ever a tip: it never moves the band.
    var heartRateEvidence: Bool
}

/// Pace changes a run makes (PZ-7, PZ-7a, PZ-8, FB-4c, FB-4d). Each change is recorded with the run that made it
/// (`RunReviewState.effects`), so reviewing the same run again, or re-planning, never applies it twice.
/// "Conditions" runs never move paces, and heart rate never does either: it stays a note on the run (PZ-12, PZ-13).
enum PaceUpdates {
    /// PZ-7: 3% slower after a hard session; 1% faster at most once per 2 weeks (HL-27).
    static let cutFactor = 1.03
    static let raiseFactor = 0.99
    static let raiseGap: TimeInterval = 14 * 86_400
    /// FB-4c: the easy band moves 15 s/km slower, and runs more than 5% faster than its fast edge count.
    static let easyShift = 15.0
    static let easyFastLine = 0.05
    /// FB-4c: an easy pace this slow is within about 1 km/h of brisk walking, so walk breaks are offered at once.
    static let walkingPace = 510.0
    /// PZ-8: logged easy pace more than 10% off the reported one replaces it.
    static let reportedLine = 0.10

    static let cutNote = CoachNote(.pace, "That session was harder than planned, so next time the paces are 3% easier.")
    static let raiseNote = CoachNote(.pace, "You've hit your targets feeling fresher than planned, so your quality paces are 1% quicker.")
    static let easySlowerNote = CoachNote(.pace, "Easy means you could chat in full sentences, so I've set your easy pace a little slower.")
    static let easyPatternTip = "Your easy runs have been on the quick side. Easy means you could chat in full sentences, so ease back a little."
    static let easyRunTip = "That was quicker than easy. Easy means you could chat in full sentences, so ease back a little next time."

    // MARK: PZ-7 and PZ-7a

    /// PZ-7's cut, once per run: a Failed session, or the down trigger on a session with a pace target. A session
    /// without one gets a third fewer reps from the planner instead (`SessionJudgement.fewerReps`). A Failed
    /// session's own line already says the paces ease, so it gets no second note. Speed Work moves down at once
    /// the same way (PZ-7a).
    static func cut(_ judgement: SessionJudgement, session: PlannedSession, state: inout CoachState) -> CoachNote? {
        guard !judgement.conditions, session.paceBand != nil, judgement.outcome == .failed || judgement.downTrigger else { return nil }
        if state.runReview.effect(.qualityCut, runID: judgement.runID) == nil {
            apply(RunEffect(kind: .qualityCut, runID: judgement.runID, date: judgement.date), to: &state)
        }
        return judgement.outcome == .failed ? nil : cutNote
    }

    /// PZ-7's raise (SW-5a in Speed Work): 2 Q in a row of any type Even and on target, or targets hit at RPE 1 or
    /// more below target in 3 of the last 4 Q. At most 1% per 2 weeks, and a Q counts toward one raise only (HL-27).
    static func raise(_ judgement: SessionJudgement, state: inout CoachState) -> CoachNote? {
        if let effect = state.runReview.effect(.qualityRaise, runID: judgement.runID) { return effect.changed ? raiseNote : nil }
        guard !judgement.conditions, judgement.outcome == .evenAndOnTarget || judgement.outcome == .completed else { return nil }
        let used = Set(state.runReview.effects.filter { $0.kind == .qualityRaise }.flatMap(\.runIDs))
        let history = state.runReview.judgements.filter { $0.date <= judgement.date }.sorted { $0.date < $1.date }
        var counted: [UUID] = []
        let lastTwo = history.suffix(2)
        if lastTwo.count == 2, lastTwo.allSatisfy({ $0.outcome == .evenAndOnTarget && !used.contains($0.runID) }) {
            counted = lastTwo.map(\.runID)
        } else {
            let hits = history.suffix(4).filter { $0.easierThanTarget && !used.contains($0.runID) }
            if hits.count >= 3 { counted = hits.map(\.runID) }
        }
        guard counted.contains(judgement.runID) else { return nil }
        if let last = state.paces.lastRaise, judgement.date.timeIntervalSince(last) < raiseGap { return nil }
        apply(RunEffect(kind: .qualityRaise, runID: judgement.runID, date: judgement.date, runIDs: counted), to: &state)
        return raiseNote
    }

    // MARK: FB-4d repeated

    /// FB-4d repeated: rep flags in 2 of the last 3 sessions of a type make quality paces 3% slower (PZ-7). When
    /// they still repeat after that cut, the next session's recoveries lengthen before any rep is cut (SW-5).
    /// `flagged` lists the runs among the type's last 3 sessions whose reps were flagged.
    static func repDrift(_ judgement: SessionJudgement, flagged: [UUID], state: inout CoachState) -> CoachNote? {
        let name = typeName(judgement.type)
        if state.runReview.effect(.repsCut, runID: judgement.runID) != nil {
            return CoachNote(.pace, "Because your reps drifted in 2 of your last 3 \(name) sessions, next time the paces are 3% easier.")
        }
        if state.runReview.advice.contains(where: { $0.kind == .lengthenRecoveries && $0.runID == judgement.runID }) {
            return CoachNote(.plan, "Because your reps are still drifting, your next \(name) session has longer recoveries.")
        }
        guard !judgement.conditions, flagged.contains(judgement.runID),
              state.runReview.effect(.qualityCut, runID: judgement.runID) == nil else { return nil }
        let cuts = state.runReview.effects.filter { effect in
            effect.kind == .repsCut && state.runReview.judgement(runID: effect.runID)?.type == judgement.type
        }
        let used = Set(cuts.flatMap(\.runIDs)).union(state.runReview.advice.filter { $0.kind == .lengthenRecoveries }.map(\.runID))
        let fresh = flagged.filter { !used.contains($0) }
        guard fresh.count >= 2 else { return nil }
        if cuts.isEmpty {
            apply(RunEffect(kind: .repsCut, runID: judgement.runID, date: judgement.date, runIDs: fresh), to: &state)
            return CoachNote(.pace, "Because your reps drifted in 2 of your last 3 \(name) sessions, next time the paces are 3% easier.")
        }
        state.runReview.advice.append(PacingAdvice(
            kind: .lengthenRecoveries,
            runID: judgement.runID,
            date: judgement.date,
            sessionKinds: [judgement.type.sessionKind],
            qualityType: judgement.type
        ))
        return CoachNote(.plan, "Because your reps are still drifting, your next \(name) session has longer recoveries.")
    }

    static func typeName(_ type: QualityType) -> String {
        switch type {
        case .threshold: "tempo"
        case .vo2max: "interval"
        case .shortReps: "short-rep"
        case .hills: "hill"
        case .racePace: "race-pace"
        }
    }

    // MARK: PZ-8

    /// PZ-8: at the third comfortable easy run (RPE 3 or less, data gate passed, not a treadmill, run-walk or
    /// "conditions" run), a logged easy pace more than 10% off the pace the runner gave replaces it. Once per plan.
    /// `comfortable` is every such run from the plan's start up to this one, oldest first.
    static func checkReportedPace(_ run: LoggedRun, comfortable: @autoclosure () -> [LoggedRun], state: inout CoachState) -> CoachNote? {
        if let effect = state.runReview.effects.first(where: { $0.kind == .easyChecked }) {
            return effect.runID == run.id ? reportedNote(effect, state: state) : nil
        }
        guard state.paces.easySource == .reported, let reported = state.intake.easyPace, reported > 0 else { return nil }
        let comfortable = comfortable()
        guard comfortable.count >= 3, comfortable[2].id == run.id else { return nil }
        let paces = comfortable.prefix(3).compactMap(\.pace).sorted()
        guard paces.count == 3 else { return nil }
        let median = paces[1]
        let changed = abs(median - reported) / reported > reportedLine
        let effect = RunEffect(
            kind: .easyChecked,
            runID: run.id,
            date: run.start,
            runIDs: comfortable.prefix(3).map(\.id),
            changed: changed,
            band: changed ? PaceBand(fast: median, slow: median * 1.10) : nil
        )
        apply(effect, to: &state)
        return reportedNote(effect, state: state)
    }

    static func reportedNote(_ effect: RunEffect, state: CoachState) -> CoachNote? {
        guard effect.changed, let band = effect.band, let reported = state.intake.easyPace, reported > 0 else { return nil }
        let difference = (band.fast - reported) / reported
        let direction = difference < 0 ? "faster" : "slower"
        return CoachNote(.pace, "Your easy runs have been about \(RunInsights.percent(abs(difference))) \(direction) than the pace you gave me, so I've set your easy pace from your runs.")
    }

    // MARK: FB-4c

    struct EasyCheck {
        /// The plan change's "because", which is also FB-1's consistency insight.
        var note: CoachNote?
        /// A tip when one run, or heart rate alone, says easy runs are too quick.
        var tip: String?
        /// How much faster than the band, for FB-1's ordering.
        var size: Double
        var question: CoachQuestion?
    }

    /// FB-4c: 2 of the last 3 easy runs more than 5% faster than the easy band, with an RPE of 4 or more (5 or more
    /// after leg work) or a failed talk test on one of them, move the band 15 s/km slower. With heart rate as the
    /// only sign it's a tip, and so is one fast run (FB-1). Starters, Novices and runners whose easy pace is close to
    /// walking are offered walk breaks at once; others when easy runs are still too fast 2 weeks later.
    /// `recent` is the last 3 comparable easy runs, oldest first, ending with this one.
    static func easyTooFast(_ run: LoggedRun, recent: [EasyRunFact], state: inout CoachState) -> EasyCheck {
        var check = EasyCheck(size: 0)
        guard let current = recent.last, current.runID == run.id, let fast = current.fast else { return check }
        check.size = fast
        if state.runReview.effect(.easySlowed, runID: run.id) != nil {
            check.note = easySlowerNote
            check.question = state.runReview.offer(.walkBreaks, runID: run.id)?.question
            return check
        }
        let used = Set(state.runReview.effects.filter { $0.kind == .easySlowed }.flatMap(\.runIDs))
        let pattern = recent.filter { $0.fast != nil && !used.contains($0.runID) }
        if pattern.count >= 2, pattern.contains(where: \.effortEvidence) {
            let earlier = state.runReview.effects.filter { $0.kind == .easySlowed && $0.date < run.start }
            apply(RunEffect(kind: .easySlowed, runID: run.id, date: run.start, runIDs: pattern.map(\.runID)), to: &state)
            check.note = easySlowerNote
            let alreadyOffered = state.runReview.offers.contains { $0.kind == .walkBreaks } || state.runReview.walkBreaks
            let closeToWalking = state.assessment.tier <= .novice || (state.paces.easy?.fast ?? 0) >= walkingPace
            let stillFast = earlier.contains { run.start.timeIntervalSince($0.date) >= 14 * 86_400 }
            if !alreadyOffered, closeToWalking || stillFast {
                state.runReview.offers.append(RunOffer(kind: .walkBreaks, runID: run.id, date: run.start, question: .walkBreaks))
                check.question = .walkBreaks
            }
        } else if pattern.count >= 2, pattern.contains(where: \.heartRateEvidence) {
            check.tip = easyPatternTip
        } else if current.effortEvidence || current.heartRateEvidence {
            check.tip = easyRunTip
        }
        return check
    }

    // MARK: Applying

    /// Applies a pace change and records it with its run.
    static func apply(_ effect: RunEffect, to state: inout CoachState) {
        change(effect, paces: &state.paces)
        state.runReview.effects.removeAll { $0.key == effect.key }
        state.runReview.effects.append(effect)
    }

    /// The change itself, also used to put a change back after a baseline restore.
    static func change(_ effect: RunEffect, paces: inout TrainingPaces) {
        guard effect.changed else { return }
        switch effect.kind {
        case .qualityCut, .repsCut:
            paces.qualityFactor *= cutFactor
        case .qualityRaise:
            paces.qualityFactor *= raiseFactor
            paces.lastRaise = max(paces.lastRaise ?? .distantPast, effect.date)
        case .easyChecked:
            if let band = effect.band {
                paces.easy = band
                paces.easySource = .logged
            }
        case .easySlowed:
            paces.easy = paces.easy?.shifted(by: easyShift)
        }
    }
}
