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
        let loads = ExtraRuns.RunLoads(runs: runs, state: state, calendar: calendar)
        let weekRuns = loads.usable
            .filter { reviewed.contains($0.id) && $0.start >= from && $0.start < to && $0.start <= now }
            .sorted { $0.start < $1.start }
        for run in weekRuns {
            let extra = state.runReview.extraRunIDs.contains(run.id)
            keep(ExtraRuns.apply(run, extra: extra, state: &state, runs: runs, loads: loads, now: now, calendar: calendar), in: &state)
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
            return !ran(advice.sessionKinds, type: nil, after: advice.date, before: day, except: session.id, state: state, calendar: calendar)
        }
    }

    /// Whether a session of these kinds (of this Q type, when given) was done or is still planned after `date` and
    /// before `day`. A Q made easy is an easy run, not its kind.
    static func ran(_ kinds: [SessionKind], type: QualityType?, after date: Date, before day: Date, except sessionID: UUID?, state: CoachState, calendar: Calendar) -> Bool {
        state.weeks.contains { record in
            record.plan.sessions.contains { other in
                guard other.id != sessionID, kinds.contains(other.kind),
                      other.madeEasy == nil || !other.kind.isQuality else { return false }
                if let type, other.dose?.type != type { return false }
                let otherDay = state.date(of: other, in: record.plan, calendar: calendar)
                guard otherDay > date, otherDay < day else { return false }
                switch other.status {
                case .done, .planned: return true
                case .missed, .dropped: return false
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

    // MARK: In the plan

    /// AD-6c's easy week: rest or easy runs of 30 min at most, for 7 days after the benchmark.
    static let easyWeekDays = 7
    static let easyWeekRunSeconds: Double = 30 * 60
    /// FB-4g: the next session of a type after a Failed one runs a quarter less.
    static let failedShare = 0.75
    /// PZ-7's down trigger with no pace target: a third fewer reps.
    static let fewerRepsShare = 2.0 / 3
    /// FB-4a, FB-4f: a tempo split into 5-min reps with HL-13's threshold-rep recovery, 1 min jog per 5 min.
    static let splitRepSeconds: Double = 5 * 60
    static let splitRecoverySeconds: Double = 60
    /// FB-4d, SW-5: recoveries half as long again before any rep is cut, VO2max jogs at most 3 min.
    static let longerRecoveries = 1.5
    static let longestIntervalRecovery: Double = 3 * 60
    /// FB-4f on a tempo already in reps: 3% easier.
    static let easierTempo = 0.03

    /// FB-4g and FB-4a in a week's targets before it is laid out. The next Q of a type after a Failed session runs
    /// a quarter less, and after a Struggled one the same again (a third fewer reps after PZ-7's down trigger with no
    /// pace target), never more than the planner chose. In Build Distance a held long-run step keeps the next loading
    /// week's long run at its current length.
    static func shape(_ targets: inout WeekTargets, context: PlanningContext) {
        let state = context.state
        let calendar = context.calendar
        for index in targets.quality.indices {
            let dose = targets.quality[index]
            guard let current = state.quality.dose(for: dose.type),
                  let judgement = state.runReview.judgements.filter({ $0.type == dose.type }).max(by: { $0.date < $1.date }),
                  judgement.date < context.weekStart,
                  !ran([dose.type.sessionKind], type: dose.type, after: calendar.startOfDay(for: judgement.date), before: context.weekStart, except: judgement.sessionID, state: state, calendar: calendar)
            else { continue }
            let next: QualityDose
            switch judgement.outcome {
            case .failed:
                next = QualityPlanner.cut(current, to: failedShare, age: state.assessment.age, runsPerWeek: targets.runs)
            case .struggled:
                next = judgement.fewerReps ? QualityPlanner.cut(current, to: fewerRepsShare, age: state.assessment.age, runsPerWeek: targets.runs) : current
            case .evenAndOnTarget, .completed:
                continue
            }
            if next.workSeconds < dose.workSeconds { targets.quality[index] = next }
        }
        if state.goal.flavor == .buildDistance, targets.kind == .loading, targets.isNewLongest,
           holdsLongRunStep(week: context.weekIndex, state: state, calendar: calendar) {
            targets.isNewLongest = false
            if let long = targets.longRun { targets.longRun = long.capped(at: context.longest) }
        }
    }

    /// What run reviews change in a week's laid-out sessions, keeping each on its day and kind so its ID stays the
    /// same: FB-4a and FB-4f's tempo split into 5-min reps (3% easier when it's reps already), FB-4d's longer
    /// recoveries, FB-4c's walk breaks on easy runs and AD-6c's easy week. Returns the week's notes.
    static func finish(_ sessions: inout [PlannedSession], context: PlanningContext) -> [CoachNote] {
        let state = context.state
        let calendar = context.calendar
        let pace = context.easyPace ?? Scheduler.fallbackEasyPace
        var notes: [CoachNote] = []
        for index in sessions.indices where sessions[index].status.isPlanned {
            let session = sessions[index]
            let day = calendar.date(byAdding: .day, value: session.dayOffset, to: context.weekStart) ?? context.weekStart
            if session.isQuality, let dose = session.dose {
                sessions[index] = adviseQuality(session, dose: dose, on: day, context: context)
            }
            if state.runReview.walkBreaks, session.kind == .easy, session.madeEasy == nil, !session.isBenchmark, session.blocks.isEmpty {
                // EF-4's ratio: a minute's walk after each easy kilometre.
                let seconds = session.target.seconds > 0 ? session.target.seconds : session.target.meters / 1_000 * pace
                sessions[index].blocks = Scheduler.runWalkBlocks(.runWalk(runSeconds: pace.rounded(), walkSeconds: 60), seconds: seconds)
            }
        }
        if let until = state.runReview.easyUntil,
           let from = calendar.date(byAdding: .day, value: -(easyWeekDays + 1), to: until) {
            var eased = false
            for index in sessions.indices where sessions[index].status.isPlanned {
                let day = calendar.date(byAdding: .day, value: sessions[index].dayOffset, to: context.weekStart) ?? context.weekStart
                guard day > from, day < until else { continue }
                eased = ease(&sessions[index], pace: pace) || eased
            }
            if eased, let last = calendar.date(byAdding: .day, value: -1, to: until) {
                notes.append(CoachNote(.plan, "Easy running only until \(Weekday(of: last, calendar: calendar).name): 30 minutes at most, or rest, while your legs recover."))
            }
        }
        return notes
    }

    /// FB-4a, FB-4f and FB-4d on one Q: rebuilt from the changed dose when its shape changes.
    static func adviseQuality(_ session: PlannedSession, dose: QualityDose, on day: Date, context: PlanningContext) -> PlannedSession {
        let kinds = Set(advice(for: session, on: day, state: context.state, calendar: context.calendar).map(\.kind))
        var dose = dose
        var changed = false
        var easier = false
        if kinds.contains(.splitIntoReps) || kinds.contains(.tempoAsReps), dose.type == .threshold || dose.type == .racePace {
            if dose.continuous || dose.reps <= 1 {
                dose.reps = max(2, Int((dose.workSeconds / splitRepSeconds).rounded()))
                dose.repSeconds = splitRepSeconds
                dose.recoverySeconds = splitRecoverySeconds
                dose.continuous = false
                changed = true
            } else if kinds.contains(.tempoAsReps) {
                easier = true
            }
        }
        if kinds.contains(.lengthenRecoveries), !dose.continuous, dose.reps > 1 {
            var longer = dose.recoverySeconds * longerRecoveries
            if dose.type == .vo2max { longer = min(longer, max(dose.recoverySeconds, longestIntervalRecovery)) }
            changed = changed || longer > dose.recoverySeconds
            dose.recoverySeconds = longer.rounded(toMultipleOf: 15)
        }
        var session = session
        if changed {
            // A small week's Q keeps its shorter warm-up and cool-down.
            var compact = false
            if case .time(let seconds)? = session.blocks.first?.steps.first(where: { $0.kind == .warmup })?.goal {
                compact = seconds < Scheduler.warmUpSeconds
            }
            var rebuilt = Scheduler.qualitySession(dose, day: session.dayOffset, context: context, unit: context.unit, compact: compact)
            rebuilt.isKey = session.isKey
            session = rebuilt
        }
        if easier {
            session.paceBand = session.paceBand?.slower(by: easierTempo)
            for block in session.blocks.indices {
                for step in session.blocks[block].steps.indices where session.blocks[block].steps[step].kind == .work {
                    session.blocks[block].steps[step].pace = session.blocks[block].steps[step].pace?.slower(by: easierTempo)
                }
            }
        }
        return session
    }

    /// AD-6c on one session: a Q, test or long run becomes an easy run, and every run is 30 min at most. The race is
    /// left as it is. True when the session changed.
    static func ease(_ session: inout PlannedSession, pace: Double) -> Bool {
        guard session.kind.isRun, session.kind != .race, session.kind != .runWalk, session.kind != .walk else { return false }
        let before = session
        if session.isQuality || session.kind == .test {
            Scheduler.makeEasy(&session, reason: .adaptation, pace: pace)
            session.appTest = nil
        } else if session.kind == .long {
            session.madeEasy = .adaptation
            session.isNewLongest = false
            session.blocks = []
        }
        session.benchmark = nil
        session.strides = 0
        session.target = session.target.capped(at: Load(easyWeekRunSeconds, in: .time, pace: pace))
        return session != before
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
            return RunDataGate.check(run, duplicate: false).gate == .passes && !hotOrHilly(run, state: state)
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
