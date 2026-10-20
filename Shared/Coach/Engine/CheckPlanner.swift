//
//  CheckPlanner.swift
//  Wind Run
//

import Foundation

/// Fitness checks on each flavor's schedule: PZ-3's app tests and BD-5c's benchmark runs (PZ-3, BD-5c, EV-10,
/// SW-7a, AD-6d). Speed Work's blocks place their own tests (SpeedWorkPlanner).
enum CheckPlanner {
    /// No test in the early window (HL-11), for runners 60+ with under 6 months of running (HL-13, SW-2b), while
    /// an injury report is open (SW-3b), or before the Q gate (HL-12, EV-10).
    static func canTest(_ context: PlanningContext) -> Bool {
        let state = context.state
        let assessment = state.assessment
        guard !assessment.overlays.earlyWindow, state.openInjuries.isEmpty,
              !(assessment.age >= 60 && assessment.monthsRunning < 6) else { return false }
        return QualityPlanner.gateBlocker(state: state, runs: context.runs, now: context.now, calendar: context.calendar) == nil
    }

    /// PZ-3: a controlled test, capped at RPE 8 and marked low precision, at 60+, under 12 weeks of running, or
    /// with an illness still open. The day's weather and course decide the rest before the start.
    static func controlledOnly(_ state: CoachState) -> Bool {
        state.assessment.age >= 60
            || state.assessment.monthsRunning * CoachLimits.weeksPerMonth < 12
            || state.activeIllness != nil
    }

    /// The test's work: 12 minutes for 1 mile to 10K goals, 5 km for half and marathon goals (PZ-3).
    static func testGoal(for distance: RaceDistance) -> StepGoal {
        distance >= .halfMarathon ? .distance(meters: 5_000) : .time(seconds: 12 * 60)
    }

    /// The plan week of the last test or benchmark that was run or is still planned.
    static func lastCheckWeek(_ state: CoachState, before index: Int) -> Int? {
        state.weeks.last { record in
            record.plan.index < index && record.plan.sessions.contains { session in
                guard session.kind == .test || session.isBenchmark else { return false }
                switch session.status {
                case .done, .planned: return true
                case .missed, .dropped: return false
                }
            }
        }?.plan.index
    }

    /// The first plan week after calibration (TI-5).
    static func calibrationEnd(_ state: CoachState) -> Int {
        state.assessment.start.calibrates ? Progression.calibrationWeeks + WeekPlanner.extraCalibrationWeeks(state) : 0
    }

    /// Adds the week's test or benchmark in Build Distance and event plans.
    static func addCheck(_ targets: inout WeekTargets, context: PlanningContext) {
        let state = context.state
        guard state.goal.flavor != .speedWork, targets.check == nil, state.ladder == nil || state.ladder?.form == .done,
              context.weekIndex >= calibrationEnd(state) else { return }
        switch targets.kind {
        case .loading, .hold, .stepBack, .ease: break
        default: return
        }
        if state.goal.flavor == .event, state.goal.hasTimeGoal {
            addEventTest(&targets, context: context)
        } else {
            addBenchmark(&targets, context: context)
        }
    }

    /// BD-5c: every 4-6 weeks one easy run is a benchmark, the first right after calibration as the baseline;
    /// two "too easy" weeks bring the next one forward (AD-6d). Event plans without a time goal use the same
    /// schedule (EV-10), with none in the taper.
    static func addBenchmark(_ targets: inout WeekTargets, context: PlanningContext) {
        let state = context.state
        let index = context.weekIndex
        if let phase = targets.phase, [.taper, .raceWeek, .recovery].contains(phase) { return }
        let easyRuns = targets.runs - targets.quality.count - (targets.longRun == nil ? 0 : 1)
        guard easyRuns >= 1 else { return }
        let due: Bool
        if let last = lastCheckWeek(state, before: index) {
            let forward = (state.quality.retestWeek ?? .max) <= index && index - last >= 2
            due = index - last >= 5 || forward
        } else {
            due = true
        }
        guard due else { return }
        targets.check = .benchmark
    }

    /// EV-10 with a time goal: a PZ-3 test replaces that week's Q in the step-back week closest to plan weeks 8,
    /// 16, 24 and so on after calibration (the earlier one on a tie), in the last step-back week before the anchor
    /// turns 26 weeks old, and in the first week with a Q after a G3+ gap or an injury return. None before the Q
    /// gate or in the early window, the specific phase (the tune-up race is the benchmark) or the taper.
    static func addEventTest(_ targets: inout WeekTargets, context: PlanningContext) {
        let state = context.state
        guard let phase = targets.phase, [.base, .build, .speedBlock].contains(phase), canTest(context) else { return }
        let index = context.weekIndex
        let cycleLength = WeekPlanner.cycle(for: state, now: context.now, calendar: context.calendar).count
        var due = false
        if state.quality.retestDue == true, !targets.quality.isEmpty {
            due = true
        } else if targets.kind == .stepBack {
            let calibrationEnd = calibrationEnd(state)
            let week = index - calibrationEnd + 1
            let target = max(1, Int((Double(week) / 8).rounded())) * 8
            let lastWeek = lastCheckWeek(state, before: index).map { $0 - calibrationEnd + 1 } ?? .min
            if Double(week) >= Double(target) - Double(cycleLength) / 2, lastWeek <= target - 4 {
                due = true
            }
            if !due, let anchor = state.paces.anchor,
               let nextStepBack = context.calendar.date(byAdding: .day, value: 7 * cycleLength, to: context.weekStart),
               (context.calendar.dateComponents([.day], from: anchor.date, to: nextStepBack).day ?? 0) > 26 * 7 {
                due = true
            }
        }
        guard due else { return }
        targets.quality = Array(targets.quality.dropFirst())
        targets.strides = 0
        targets.check = .test(controlled: controlledOnly(state))
        targets.notes.append(CoachNote(.plan, "This week's hard session is a test, so your paces and race forecast use your fitness now. Start steady and build."))
    }

    /// Sets or clears the retest that follows a break or an injury return (SW-3b, EV-10, AD-14d), and clears a
    /// brought-forward check once one is planned.
    static func track(_ state: inout CoachState, targets: WeekTargets, index: Int) {
        let goal = state.goal
        if goal.flavor == .speedWork || (goal.flavor == .event && goal.hasTimeGoal) {
            if targets.kind == .ramp, let tier = state.gap?.tier, tier >= (goal.flavor == .speedWork ? .g2 : .g3) {
                state.quality.retestDue = true
            }
            if targets.kind == .recovery || targets.kind == .injuryReturn {
                state.quality.retestDue = true
            }
            if case .test = targets.check {
                state.quality.retestDue = nil
            }
        }
        if targets.check != nil, (state.quality.retestWeek ?? .max) <= index {
            state.quality.retestWeek = nil
        }
    }
}
