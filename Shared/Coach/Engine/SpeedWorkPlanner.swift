//
//  SpeedWorkPlanner.swift
//  Wind Run
//

import Foundation

/// Speed Work's calendar: Build Distance weeks until the distance is ready and the Q gate opens, then 8-week
/// blocks (6 in the Reduced or Low recovery tier) that end in a retest, with a volume cycle between blocks
/// (SW-1b, SW-2a, SW-3a, SW-3b, SW-6, SW-7a, PZ-2a, PZ-3a).
enum SpeedWorkPlanner {
    /// SW-3a: 8 weeks, or 6 in the Reduced or Low recovery tier.
    static func blockLength(_ state: CoachState) -> Int {
        state.assessment.recoveryTier.stepsBackEveryThird ? 6 : 8
    }

    /// Block weeks 4 and 8 are step-backs, or 3 and 6 in the 6-week form.
    static func isStepBack(blockWeek: Int, length: Int) -> Bool {
        blockWeek % (length == 6 ? 3 : 4) == 0
    }

    /// SW-6: the volume cycle is required at ≤15 km a week with a goal of 10K or longer; otherwise it runs only
    /// while volume is below HL-14's ceiling.
    static func needsVolumeCycle(_ state: CoachState, volume: Double, pace: Double?) -> Bool {
        let meters = Load(volume, in: state.volumeUnit, pace: pace).meters
        if meters <= 15_000, state.goal.distance >= .tenK { return true }
        return volume < WeekPlanner.volumeCeiling(state, pace: pace) * 0.999
    }

    /// The phase a Speed Work week outside a block is in: the volume cycle, or Build Distance base weeks before
    /// the first block.
    static func phase(_ context: PlanningContext) -> TrainingPhase? {
        let state = context.state
        guard state.goal.flavor == .speedWork else { return nil }
        if state.quality.blockWeek != nil { return .speedBlock }
        if state.quality.volumeCycle == true { return .volumeCycle }
        return state.quality.blocksDone == 0 ? .base : nil
    }

    /// Whether a block may start: the distance is ready (SW-1b), the Q gate is open (HL-12), the level gives a Q
    /// (CL-1a) and no injury report is open (SW-2a, HL-15).
    static func canStartBlock(_ context: PlanningContext) -> Bool {
        let state = context.state
        guard state.openInjuries.isEmpty, WeekPlanner.distanceReady(context),
              QualityPlanner.gateBlocker(state: state, runs: context.runs, now: context.now, calendar: context.calendar) == nil else { return false }
        return QualityPlanner.count(state: state, runs: state.cycle.runsPerWeek, weekIndex: context.weekIndex) > 0
    }

    /// The anchor in force is missing or older than `weeks` at `date` (PZ-2, PZ-2a).
    static func anchorStale(_ state: CoachState, weeks: Int, at date: Date, calendar: Calendar) -> Bool {
        guard let anchor = state.paces.anchor else { return true }
        let days = calendar.dateComponents([.day], from: anchor.date, to: date).day ?? 0
        return days > weeks * 7
    }

    /// The week's targets while Speed Work runs blocks, or nil for the weeks the outcome rules plan (base weeks
    /// before the first block and SW-6's volume cycle).
    static func weekTargets(_ context: PlanningContext, cycle: inout CycleState) -> WeekTargets? {
        let state = context.state
        guard state.goal.flavor == .speedWork else { return nil }
        let quality = state.quality
        if let done = quality.blockWeek {
            return blockWeekTargets(done + 1, length: quality.blockLength, context: context, cycle: &cycle)
        }
        guard canStartBlock(context), quality.volumeCycle != true else { return nil }

        // After a G2+ gap or an Intense or Severe report, the first Q back is the retest, in a week where volume
        // holds (SW-3b).
        if quality.retestDue == true, CheckPlanner.canTest(context) {
            var targets = holdTargets(context, cycle: &cycle)
            targets.quality = []
            targets.strides = 0
            targets.check = .test(controlled: CheckPlanner.controlledOnly(state))
            targets.notes.append(CoachNote(.plan, "This week's hard session is a test, so your paces start from where you are now. Start steady and build."))
            return targets
        }

        // A block starts the week after a step-back. Before the first one, calibration is followed by one level
        // cycle, and the 3 weeks before the step-back must be steady (HL-3); when readiness turns Green
        // mid-cycle, the step-back comes after the cycle's second loading week (SW-1b, SW-3a).
        let previous = context.previousWeek
        let afterStepBack = previous.map { [.stepBack, .adaptiveStepBack].contains($0.plan.kind) } ?? false
        if quality.blocksDone > 0, afterStepBack || cycle.loadingInRow == 0 {
            return blockWeekTargets(1, length: blockLength(state), context: context, cycle: &cycle)
        }
        if afterStepBack {
            return steadyVolume(context) ? blockWeekTargets(1, length: blockLength(state), context: context, cycle: &cycle) : nil
        }
        guard cycle.loadingInRow >= 2 else { return nil }
        var (targets, _) = WeekPlanner.stepBackTargets(context, cycle: &cycle, base: WeekPlanner.lastLoading(context)?.base ?? state.v0, adaptive: false, notes: [])
        targets.phase = .base
        targets.quality = []
        targets.notes = [CoachNote(.plan, "This is a lighter week before your first speed block starts, so you begin it fresh.")]
        // PZ-2a: an anchor that would be over 12 weeks old in the block's first week is retested here.
        if let nextWeek = context.calendar.date(byAdding: .day, value: 7, to: context.weekStart),
           state.paces.anchor != nil, anchorStale(state, weeks: 12, at: nextWeek, calendar: context.calendar), CheckPlanner.canTest(context) {
            targets.check = .test(controlled: CheckPlanner.controlledOnly(state))
            targets.strides = 0
        }
        return targets
    }

    /// HL-3: the 3 weeks before a block, step-backs aside, are each within 10% of their mean volume.
    static func steadyVolume(_ context: PlanningContext) -> Bool {
        let weeks = context.state.weeks
            .filter { $0.plan.index < context.weekIndex && ![.stepBack, .adaptiveStepBack].contains($0.plan.kind) }
            .suffix(3)
            .map { $0.review?.doneVolume ?? $0.plan.plannedVolume }
        guard weeks.count == 3 else { return false }
        let mean = weeks.reduce(0, +) / 3
        return mean > 0 && weeks.allSatisfy { abs($0 - mean) <= 0.1 * mean }
    }

    /// The same targets as last week: a HOLD inside the safe zone.
    static func holdTargets(_ context: PlanningContext, cycle: inout CycleState) -> WeekTargets {
        let state = context.state
        let previous = context.previousWeek
        let volume = previous.map { min($0.plan.plannedVolume, $0.review?.doneVolume ?? $0.plan.plannedVolume) } ?? state.v0
        let long = (previous?.plan.longRun ?? cycle.lastLoadingLongRun).capped(at: context.longest)
        cycle.loadingInRow += 1
        return WeekTargets(kind: .hold, phase: phase(context), volume: max(volume, 0), longRun: long, runs: cycle.runsPerWeek, notes: [])
    }

    /// One block week (SW-3a), with the week's outcome changing only its content (SW-3b).
    static func blockWeekTargets(_ blockWeek: Int, length: Int, context: PlanningContext, cycle: inout CycleState) -> WeekTargets {
        let state = context.state
        let assessment = state.assessment
        let previous = context.previousWeek
        let outcome = previous?.review?.outcome ?? .progress
        let base = WeekPlanner.lastLoading(context)?.base ?? state.v0
        let held = (cycle.lastLoadingLongRun.amount(in: context.unit) > 0 ? cycle.lastLoadingLongRun : context.longest).capped(at: context.longest)
        let mild = !state.openInjuries.isEmpty
        var notes: [CoachNote] = []
        if blockWeek == 1 {
            notes.append(CoachNote(.plan, "Your speed block starts: \(length) weeks with steady distance and one step up in your sessions each week, then a test."))
        }

        // The step-back weeks, the last with the retest (SW-3a, SW-7a).
        if isStepBack(blockWeek: blockWeek, length: length) {
            var (targets, _) = WeekPlanner.stepBackTargets(context, cycle: &cycle, base: base, adaptive: false, notes: notes)
            targets.phase = .speedBlock
            targets.blockWeek = blockWeek
            let last = blockWeek == length
            let broughtForward = (state.quality.retestWeek ?? .max) <= context.weekIndex
            if (last || broughtForward), !mild, CheckPlanner.canTest(context) {
                targets.quality = []
                targets.strides = 0
                targets.check = .test(controlled: CheckPlanner.controlledOnly(state))
                targets.notes.append(CoachNote(.plan, last
                    ? "Block done. This week's session is a test, so your paces and goal check start from your new fitness."
                    : "Your test comes early this block, so we can see whether your paces should change."))
            } else if mild {
                targets.qualityMadeEasy = .mildInjury
                targets.strides = 0
            }
            return targets
        }

        // An adaptive STEP BACK or fatigue week inside the block: no Q, and the Q comes back at 2/3 dose the
        // week after (SW-3b, AD-6). The calendar runs on.
        if outcome == .stepBack {
            var (stepBack, next) = WeekPlanner.outcomeTargets(context, cycle: cycle)
            cycle = next
            stepBack.phase = .speedBlock
            stepBack.blockWeek = blockWeek
            stepBack.quality = []
            return stepBack
        }

        // Load weeks: volume held at W4max, the long run held at or under P-L30, one Q step a week.
        var volume = context.w4max > 0 ? context.w4max : base
        let count = QualityPlanner.count(state: state, runs: cycle.runsPerWeek, weekIndex: context.weekIndex)
        let types = QualityPlanner.types(count: count, state: state, weekIndex: context.weekIndex, phase: .speedBlock)
        let afterStepBack = previous?.plan.kind == .adaptiveStepBack || previous?.plan.kind == .fatigueEasy
        var doses: [QualityDose] = []
        var newType = false
        for type in types {
            guard let current = state.quality.dose(for: type) else {
                newType = true
                doses.append(QualityPlanner.firstDose(type, current: state.quality.doses.last, age: assessment.age, runsPerWeek: cycle.runsPerWeek))
                continue
            }
            if afterStepBack {
                doses.append(QualityPlanner.twoThirds(current))
            } else if outcome == .progress {
                doses.append(QualityPlanner.stepped(current, age: assessment.age, runsPerWeek: cycle.runsPerWeek))
            } else {
                // HOLD repeats the last dose; EASE runs it as an easy run of the same minutes.
                doses.append(current)
            }
        }
        // The first block week without a valid anchor carries the test in place of the Q (PZ-3a), unless a test
        // ran in the last two weeks. A Q type that waits for next week doesn't cut this week's volume.
        let recentTest = CheckPlanner.lastCheckWeek(state, before: context.weekIndex).map { context.weekIndex - $0 <= 2 } ?? false
        let test = blockWeek == 1 && !recentTest && !mild && CheckPlanner.canTest(context)
            && anchorStale(state, weeks: 26, at: context.weekStart, calendar: context.calendar)
        if test, !doses.isEmpty {
            doses.removeFirst()
            newType = types.dropFirst().contains { state.quality.dose(for: $0) == nil }
        }
        if newType { volume = min(volume, 0.9 * context.w4max) }
        if outcome != .progress, let note = previous?.review?.note { notes.append(note) }
        if outcome == .ease { volume *= 0.9 }

        var targets = WeekTargets(
            kind: outcome == .ease ? .ease : .loading,
            cycleWeek: .heldLongRun,
            phase: .speedBlock,
            blockWeek: blockWeek,
            volume: volume,
            longRun: held,
            runs: cycle.runsPerWeek,
            quality: doses,
            qualityMadeEasy: outcome == .ease ? .adaptation : nil,
            notes: notes
        )
        cycle.loadingInRow += 1
        if test {
            targets.check = .test(controlled: CheckPlanner.controlledOnly(state))
            targets.notes.append(CoachNote(.plan, "This week's first hard session is a test, so your sessions use paces from your fitness now."))
        }
        if mild {
            targets.qualityMadeEasy = .mildInjury
        }
        if newType, !mild {
            targets.notes.append(CoachNote(.plan, "This week adds speed, so your distance stays the same. I never raise both in one week."))
        }
        return targets
    }

    /// Moves the block calendar on once a week's targets are set, whichever rule shaped the week. A re-plan
    /// starts again from the week's baseline, so this runs once per planned week.
    static func advance(_ state: inout CoachState, targets: inout WeekTargets, context: PlanningContext) {
        guard state.goal.flavor == .speedWork else { return }
        var quality = state.quality
        let index = context.weekIndex

        if let blockWeek = targets.blockWeek, targets.phase == .speedBlock {
            if blockWeek == 1 {
                quality.blockStartWeek = index
                quality.blockLength = blockLength(state)
                quality.volumeCycle = nil
            }
            quality.blockWeek = blockWeek
        } else if let done = quality.blockWeek {
            let gapTier = state.gap?.tier
            let seriousInjury = state.openInjuries.contains { $0.level >= .intense }
            switch targets.kind {
            case .recovery, .injuryReturn:
                endBlock(&quality, retest: true)
            case .paused where seriousInjury:
                endBlock(&quality, retest: true)
            case .ramp where (gapTier ?? .g0) >= .g2:
                endBlock(&quality, retest: true)
            case .ramp, .illnessReturn, .paused:
                // G1 gaps and illness pause the calendar (SW-3b).
                break
            default:
                // Busy weeks and other outcomes change the content; the calendar runs on (SW-3b).
                quality.blockWeek = done + 1
                targets.blockWeek = done + 1
                targets.phase = .speedBlock
            }
        }

        if let blockWeek = quality.blockWeek, blockWeek >= quality.blockLength {
            // The block is done; the volume cycle follows where SW-6 calls for it.
            quality.blocksDone += 1
            quality.blockWeek = nil
            quality.blockStartWeek = nil
            let volume = WeekPlanner.lastLoading(context)?.base ?? state.v0
            quality.volumeCycle = needsVolumeCycle(state, volume: volume, pace: context.easyPace) ? true : nil
        }
        if quality.volumeCycle == true, targets.kind == .stepBack, targets.blockWeek == nil {
            // The volume cycle ends with its step-back; the next block follows it.
            quality.volumeCycle = nil
        }
        if case .test = targets.check, quality.retestDue == true, quality.blockWeek == nil, targets.blockWeek == nil {
            // The retest after a break is followed by SW-6, then a new block (SW-3b). CheckPlanner.track clears
            // the retest once this week is recorded.
            let volume = WeekPlanner.lastLoading(context)?.base ?? state.v0
            quality.volumeCycle = needsVolumeCycle(state, volume: volume, pace: context.easyPace) ? true : nil
        }
        state.quality = quality
    }

    static func endBlock(_ quality: inout QualityState, retest: Bool) {
        quality.blockWeek = nil
        quality.blockStartWeek = nil
        if retest { quality.retestDue = true }
    }
}
