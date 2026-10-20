//
//  RunReviewerPlan.swift
//  Wind Run
//

import Foundation

/// What run reviews hand the planner and the weekly review: AD-8's changes made again on a re-planned week, the run
/// facts a plan baseline restore would lose, FB-4's advice for the next sessions, and a week's run signals for the
/// weekly decision (Applying AD-4).
extension RunReviewer {
    // MARK: After a re-plan

    /// AD-8's changes made again on plan week `index` after it was planned or laid out again: the reviewed runs of
    /// that week and the week before, oldest first. Only sessions from today on change, and applying the changes
    /// again changes nothing.
    static func adjustPlan(_ state: CoachState, week index: Int, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachState {
        var state = state
        let from = state.weekStart(max(0, index - 1), calendar: calendar)
        let to = state.weekStart(index + 1, calendar: calendar)
        let reviewed = Set(state.runReview.reviewedRunIDs)
        let weekRuns = RunDataGate.usableRuns(runs)
            .filter { reviewed.contains($0.id) && $0.start >= from && $0.start < to && $0.start <= now }
            .sorted { $0.start < $1.start }
        for run in weekRuns {
            let extra = state.runReview.extraRunIDs.contains(run.id)
            keep(ExtraRuns.apply(run, extra: extra, state: &state, runs: runs, now: now, calendar: calendar), in: &state)
        }
        return state
    }

    /// Puts back, after a plan baseline was restored into `state`, what run reviews changed since the baseline was
    /// taken: the Q outcomes (FB-4g), retests asked for (FB-4g, FB-4l, FB-4m), planned slots (AD-8) and, with
    /// `paces` (a full restore), the pace changes (PZ-7, PZ-8, FB-4c, FB-4d). A change the baseline holds whose run
    /// is gone is taken back. Planning restores only the cycle and the Q state, so it passes `paces: false`.
    static func restoreRunFacts(into state: inout CoachState, week index: Int, since baseline: PlanBaseline, paces: Bool) {
        syncQuality(&state)
        // A baseline from before run reviews kept their changes: nothing to compare with.
        guard let kept = baseline.runEffects.map(Set.init) else { return }
        let requests = state.runReview.retestRequests
        for key in kept where key.hasPrefix("retest|") && !requests.contains(where: { $0.key == key }) {
            guard let due = key.split(separator: "|").last.flatMap({ Int($0) }), state.quality.retestWeek == due,
                  !requests.contains(where: { $0.dueWeek == due && kept.contains($0.key) }) else { continue }
            state.quality.retestWeek = nil
        }
        for request in requests where !kept.contains(request.key) && index <= request.dueWeek {
            state.quality.retestWeek = min(state.quality.retestWeek ?? .max, request.dueWeek)
        }
        for change in state.runReview.slotChanges where !kept.contains(change.key) {
            state.cycle.runsPerWeek = max(state.cycle.runsPerWeek, change.runsPerWeek)
            state.cycle.lastRunAddedWeek = max(state.cycle.lastRunAddedWeek ?? change.week, change.week)
        }
        guard paces else { return }
        let effects = Set(state.runReview.effects.map(\.key))
        for effect in state.runReview.effects where !kept.contains(effect.key) {
            PaceUpdates.change(effect, paces: &state.paces)
        }
        var raiseGone = false
        for key in kept where !effects.contains(key) {
            let parts = key.split(separator: "|")
            guard parts.count == 2, let kind = RunEffectKind(rawValue: String(parts[0])) else { continue }
            invert(kind, changed: true, paces: &state.paces)
            raiseGone = raiseGone || kind == .qualityRaise
        }
        if raiseGone { resetLastRaise(&state) }
    }

    // MARK: Advice for the planner

    /// FB-4's pacing advice for a planned session on `day`: each advice applies to the first session of its kinds
    /// after its run, so advice is used up once a session of its kinds was done or planned between the two. A Q made
    /// easy is an easy run, not its kind.
    static func advice(for session: PlannedSession, on day: Date, state: CoachState, calendar: Calendar) -> [PacingAdvice] {
        guard session.madeEasy == nil || !session.kind.isQuality else { return [] }
        return state.runReview.advice.filter { advice in
            guard advice.sessionKinds.contains(session.kind), advice.date < day else { return false }
            if let type = advice.qualityType, session.dose?.type != type { return false }
            return !state.weeks.contains { record in
                record.plan.sessions.contains { other in
                    guard other.id != session.id, advice.sessionKinds.contains(other.kind),
                          other.madeEasy == nil || !other.kind.isQuality else { return false }
                    let otherDay = state.date(of: other, in: record.plan, calendar: calendar)
                    guard otherDay > advice.date, otherDay < day else { return false }
                    switch other.status {
                    case .done, .planned: return true
                    case .missed, .dropped: return false
                    }
                }
            }
        }
    }

    /// FB-4a in Build Distance: a fade without a fast start in 2 of the last 3 long runs holds the next loading
    /// week's long-run step, once. True for plan week `index` when no loading week came between the advice and it.
    static func holdsLongRunStep(week index: Int, state: CoachState, calendar: Calendar) -> Bool {
        let start = state.weekStart(index, calendar: calendar)
        return state.runReview.advice.contains { advice in
            guard advice.kind == .holdLongRunStep, advice.date < start else { return false }
            let adviceWeek = state.weekIndex(on: advice.date, calendar: calendar)
            return !state.weeks.contains { $0.plan.index > adviceWeek && $0.plan.index < index && $0.plan.kind == .loading }
        }
    }

    // MARK: The weekly review

    /// What plan week `index`'s runs add to the weekly review (Applying AD-4, AD-8, FB-4g), worked out from the runs
    /// at each call. Runs flagged by FB-2, hot runs and hill runs feed no family. `resting` is HealthKit's resting
    /// heart rate, read on the device like the runs' heart rate, for PZ-13's flag.
    static func weekSignals(
        week index: Int,
        state: CoachState,
        runs: [LoggedRun],
        calendar: Calendar,
        resting: [RestingHeartRate] = [],
        heartRateSettings: HeartRateSettings = .off
    ) -> RunWeekSignals {
        let start = state.weekStart(index, calendar: calendar)
        let end = state.weekStart(index + 1, calendar: calendar)
        let usable = RunDataGate.usableRuns(runs)
        let weekRuns = usable.filter { $0.start >= start && $0.start < end }.sorted { $0.start < $1.start }

        // Family E: an FB-3 "Tired" answer on a run not already marked cut short (that mark is counted already).
        let tired = weekRuns.filter { run in
            guard let checkIn = run.checkIn, checkIn.cutShort == nil, checkIn.whatHappened == .tired else { return false }
            return RunDataGate.check(run, runs: runs).gate == .passes && !hotOrHilly(run, state: state)
        }.count

        // Family H: FB-4l's higher heart rate at the same easy pace, as of the week's last decision-grade easy run,
        // or PZ-13's resting-HR flag on a day of the week.
        var heartRate = false
        if let last = weekRuns.last(where: { coachingHeartRate($0, runs: runs) && HeartRateRules.easyWindow($0, state: state) != nil }) {
            heartRate = HeartRateRules.paceAtHeartRate(after: last, runs: usable, state: state, calendar: calendar).higher
        }
        if !heartRate, !resting.isEmpty {
            heartRate = (0 ..< 7).contains { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: start), day < end else { return false }
                return HeartRateRules.restingRaised(resting, settings: heartRateSettings, on: day, calendar: calendar)
            }
        }

        // AD-8: extra runs left the week more than 10% over plan.
        var overPlan = false
        if let week = state.weeks.first(where: { $0.plan.index == index })?.plan, week.plannedVolume > 0,
           weekRuns.contains(where: { state.runReview.extraRunIDs.contains($0.id) }) {
            let sessions = LoadMetrics.sessions(from: usable)
            let done = LoadMetrics.volume(from: start, to: end, sessions: sessions, unit: week.volumeUnit, pace: state.paces.easyPace)
            overPlan = done > ExtraRuns.overPlanLine * week.plannedVolume + 1e-6
        }

        // FB-4g, PZ-7: a down-step this week right after one for the same Q type.
        let judgements = state.runReview.judgements.filter { !$0.conditions }
        let secondDownStep = judgements.contains { judgement in
            guard judgement.date >= start, judgement.date < end, SessionJudge.isDownStep(judgement),
                  let previous = SessionJudge.previous(judgement, in: state.runReview.judgements) else { return false }
            return !previous.conditions && SessionJudge.isDownStep(previous)
        }
        return RunWeekSignals(extraEffortFlags: tired, heartRateNegative: heartRate, overPlan: overPlan, secondDownStep: secondDownStep)
    }
}
