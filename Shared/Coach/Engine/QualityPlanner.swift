//
//  QualityPlanner.swift
//  Wind Run
//

import Foundation

/// Quality sessions: the Q gate, how many a week, which types and at what dose (HL-7, HL-12, HL-13, CL-1, SW-4, SW-5, EV-2).
enum QualityPlanner {
    // MARK: Ladders (SW-5)

    /// One rung of a session ladder: reps × minutes with a recovery, or one continuous piece.
    struct Rung: Hashable {
        var reps: Int
        var repMinutes: Double
        var recoveryMinutes: Double
        var continuous: Bool = false

        var workMinutes: Double { Double(reps) * repMinutes }
    }

    /// The ladder for a type. Runners 50+ do reps before continuous threshold and 4-6 min VO2max reps (SW-2b).
    static func ladder(for type: QualityType, age: Int, runsPerWeek: Int) -> [Rung] {
        switch type {
        case .threshold:
            var rungs = [
                Rung(reps: 2, repMinutes: 5, recoveryMinutes: 1),
                Rung(reps: 3, repMinutes: 5, recoveryMinutes: 1),
                Rung(reps: 4, repMinutes: 5, recoveryMinutes: 1),
                Rung(reps: 3, repMinutes: 8, recoveryMinutes: 1.5),
                Rung(reps: 2, repMinutes: 12, recoveryMinutes: 2.5),
            ]
            if age < 50 { rungs.append(Rung(reps: 1, repMinutes: 20, recoveryMinutes: 0, continuous: true)) }
            rungs.append(Rung(reps: 3, repMinutes: 10, recoveryMinutes: 2))
            if runsPerWeek >= 5 { rungs.append(Rung(reps: 4, repMinutes: 10, recoveryMinutes: 2)) }
            return rungs
        case .vo2max:
            if age >= 50 {
                return [
                    Rung(reps: 2, repMinutes: 5, recoveryMinutes: 3),
                    Rung(reps: 3, repMinutes: 4, recoveryMinutes: 3),
                    Rung(reps: 3, repMinutes: 5, recoveryMinutes: 3),
                    Rung(reps: 4, repMinutes: 4, recoveryMinutes: 3),
                    Rung(reps: 4, repMinutes: 5, recoveryMinutes: 3),
                ]
            }
            return [
                Rung(reps: 5, repMinutes: 2, recoveryMinutes: 2),
                Rung(reps: 4, repMinutes: 3, recoveryMinutes: 2.5),
                Rung(reps: 5, repMinutes: 3, recoveryMinutes: 2.5),
                Rung(reps: 6, repMinutes: 3, recoveryMinutes: 2.5),
                Rung(reps: 5, repMinutes: 4, recoveryMinutes: 3),
            ]
        case .shortReps:
            return [
                Rung(reps: 2, repMinutes: 5, recoveryMinutes: 3),
                Rung(reps: 3, repMinutes: 5, recoveryMinutes: 3),
                Rung(reps: 4, repMinutes: 5, recoveryMinutes: 3),
            ]
        case .hills:
            return [
                Rung(reps: 8, repMinutes: 1.25, recoveryMinutes: 1.5),
                Rung(reps: 10, repMinutes: 1.25, recoveryMinutes: 1.5),
                Rung(reps: 10, repMinutes: 1.5, recoveryMinutes: 1.75),
                Rung(reps: 12, repMinutes: 1.5, recoveryMinutes: 1.75),
                Rung(reps: 10, repMinutes: 2, recoveryMinutes: 2.25),
            ]
        case .racePace:
            let cap = runsPerWeek >= 5 ? 40.0 : 30.0
            return stride(from: 10.0, through: cap, by: 5).map { Rung(reps: 1, repMinutes: $0, recoveryMinutes: 0, continuous: true) }
        }
    }

    static func dose(_ type: QualityType, step: Int, age: Int, runsPerWeek: Int) -> QualityDose {
        let rungs = ladder(for: type, age: age, runsPerWeek: runsPerWeek)
        let rung = rungs[step.clamped(to: 0 ... rungs.count - 1)]
        return QualityDose(
            type: type,
            step: step.clamped(to: 0 ... rungs.count - 1),
            reps: rung.reps,
            repSeconds: rung.repMinutes * 60,
            recoverySeconds: rung.recoveryMinutes * 60,
            continuous: rung.continuous
        )
    }

    /// The first dose of a type: the first rung, or for a type new in the plan, the highest rung at or
    /// under 50% of the current Q's work minutes, never above the first rung (HL-13).
    static func firstDose(_ type: QualityType, current: QualityDose?, age: Int, runsPerWeek: Int) -> QualityDose {
        dose(type, step: 0, age: age, runsPerWeek: runsPerWeek)
    }

    /// One step up the ladder, capped at its top (HL-13: one step a week at most).
    static func stepped(_ dose: QualityDose, age: Int, runsPerWeek: Int) -> QualityDose {
        self.dose(dose.type, step: dose.step + 1, age: age, runsPerWeek: runsPerWeek)
    }

    /// The same session at two thirds of its work, after a STEP BACK or a cleared Mild report (AD-6, AD-14a).
    static func twoThirds(_ dose: QualityDose) -> QualityDose {
        var dose = dose
        if dose.continuous || dose.reps <= 1 {
            dose.repSeconds = (dose.repSeconds * 2 / 3).rounded(toMultipleOf: 60)
        } else {
            dose.reps = max(1, Int((Double(dose.reps) * 2 / 3).rounded()))
        }
        return dose
    }

    /// The highest rung at or under `share` of a dose's work, never above its own step (FB-4g: a quarter less after
    /// Failed, a third fewer reps after PZ-7's down trigger). Below the first rung, the dose itself shrinks.
    static func cut(_ dose: QualityDose, to share: Double, age: Int, runsPerWeek: Int) -> QualityDose {
        let limit = dose.workSeconds * share / 60 + 0.001
        let rungs = ladder(for: dose.type, age: age, runsPerWeek: runsPerWeek)
        if let step = rungs.indices.last(where: { $0 <= dose.step && rungs[$0].workMinutes <= limit }) {
            return self.dose(dose.type, step: step, age: age, runsPerWeek: runsPerWeek)
        }
        var cut = dose
        if cut.continuous || cut.reps <= 1 {
            cut.repSeconds = max(60, (cut.repSeconds * share).rounded(toMultipleOf: 60))
        } else {
            cut.reps = max(1, Int((Double(cut.reps) * share).rounded(.down)))
        }
        return cut
    }

    // MARK: How many (HL-7, CL-1)

    /// CL-1's Q target for the tier and level.
    static func levelTarget(tier: RunnerTier, level: CommitmentLevel) -> Int {
        switch (level, tier) {
        case (_, .starter): 0
        case (.gentle, .novice): 0
        case (.gentle, _): 1
        case (.steady, .experienced): 2
        case (.steady, _): 1
        case (.ambitious, .novice): 1
        case (.ambitious, _): 2
        }
    }

    /// HL-7's cap: min(2, floor(runs ÷ 2)); 1 at 65+, risk score ≥2, the Low tier, or ≥2 leg days plus another hard session.
    static func hardCap(runs: Int, assessment: RunnerAssessment) -> Int {
        var cap = min(2, runs / 2)
        let recovery = assessment.recovery
        if assessment.age >= 65 || assessment.risk.isHigh || recovery.tier == .low
            || (recovery.legDaysPerWeek >= 2 && recovery.hardSessionsPerWeek > recovery.legDaysPerWeek) {
            cap = min(cap, 1)
        }
        return cap
    }

    /// Q this week: the level's target, the hard cap and the second-Q rule (CL-1).
    static func count(state: CoachState, runs: Int, weekIndex: Int) -> Int {
        let assessment = state.assessment
        let target = levelTarget(tier: assessment.tier, level: state.level)
        var count = min(target, hardCap(runs: runs, assessment: assessment))
        if count >= 2 {
            let needed: Int
            switch state.level {
            case .gentle: needed = Int.max
            case .steady: needed = 6
            case .ambitious: needed = 3
            }
            if runs < 4 || !state.openInjuries.isEmpty || state.quality.cleanWeeksAtOneQ < needed || (state.level == .ambitious && weekIndex < 3) {
                count = 1
            }
        }
        return count
    }

    // MARK: The Q gate (HL-12)

    /// Why Q isn't allowed yet, or nil when the gate is open.
    static func gateBlocker(state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> String? {
        if state.quality.gateMetOn != nil, state.openInjuries.isEmpty { return nil }
        let assessment = state.assessment
        if !assessment.runs30Minutes && !ranThirtyMinutes(runs) {
            return "you need to run 30 minutes non-stop first"
        }
        if assessment.overlays.earlyWindow {
            return "your first 12 weeks and 200 km (124 mi) of running build the base speed work needs"
        }
        let weeksNeeded = assessment.age >= 50 ? 10 : 8
        if steadyWeeks(state: state, runs: runs, now: now, calendar: calendar) < weeksNeeded {
            return "a speed block needs \(weeksNeeded) straight weeks of 3 or more runs first"
        }
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        if state.injuries.contains(where: { !$0.status.isClosed || ($0.status.closedDate ?? .distantPast) > weekAgo }) {
            return "you need 7 days with no injury report open first"
        }
        let easyIDs = easyRunIDs(in: state)
        let lastEasy = runs.filter { easyIDs.contains($0.id) }.sorted { $0.start < $1.start }.suffix(3)
        if lastEasy.filter({ ($0.rpe ?? 99) <= 3 }).count < 2 {
            return "your easy runs need to feel easy first (effort 3 or less)"
        }
        return nil
    }

    static func ranThirtyMinutes(_ runs: [LoggedRun]) -> Bool {
        runs.contains { run in
            if let nonStop = run.track?.longestNonStopSeconds { return nonStop >= 30 * 60 }
            return (run.walkingSeconds ?? 0) == 0 && run.movingSeconds >= 30 * 60
        }
    }

    /// Runs matched to planned easy or long runs.
    static func easyRunIDs(in state: CoachState) -> Set<UUID> {
        var ids = Set<UUID>()
        for record in state.weeks {
            for session in record.plan.sessions where session.kind == .easy || session.kind == .long {
                if case .done(let runID) = session.status { ids.insert(runID) }
            }
        }
        return ids
    }

    /// Straight weeks at ≥3 runs with ≥90% done, credited from intake (SW HL-12 detail 1): ≥3 runs a week
    /// for the last 4 weeks and 3 months or more of history counts the 8 weeks as met.
    static func steadyWeeks(state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> Int {
        let intake = state.intake
        let credited = (intake.lastFourWeeks?.runsPerWeek ?? 0) >= 3 && (intake.history ?? .notYet) >= .threeToTwelveMonths
            ? 10 : ((intake.history ?? .notYet) >= .oneToTwoYears && (intake.lastFourWeeks?.runsPerWeek ?? 0) >= 2 ? 10 : 0)
        var streak = 0
        for record in state.weeks.reversed() {
            guard let review = record.review else { continue }
            let runsDone = record.plan.runs.filter { if case .done = $0.status { return true } else { return false } }.count
            if runsDone >= 3 && review.completion >= 0.9 {
                streak += 1
            } else {
                return streak
            }
        }
        return streak + credited
    }

    // MARK: Which types (SW-4, EV-2)

    /// The Q types for a week, the key one first.
    static func types(count: Int, state: CoachState, weekIndex: Int, phase: TrainingPhase?) -> [QualityType] {
        guard count > 0 else { return [] }
        let goal = state.goal
        let age = state.assessment.age
        let shortRunner = state.cycle.runsPerWeek <= 3
        let lastType = state.quality.recentTypes.last
        let noVO2 = age >= 60 && state.assessment.monthsRunning < 6
        func vo2() -> QualityType { noVO2 ? .threshold : (shortRunner && goal.distance <= .fiveK ? .vo2max : .vo2max) }

        switch goal.flavor {
        case .buildDistance:
            return []
        case .speedWork:
            if goal.distance == .halfMarathon {
                return count == 1 ? [.threshold] : [.threshold, (weekIndex % 2 == 0 && !noVO2) ? .vo2max : .threshold]
            }
            if count >= 2 { return [.threshold, vo2()] }
            return [lastType == .threshold ? vo2() : .threshold]
        case .event:
            if phase == .specific, goal.hasTimeGoal, state.paces.racePace != nil {
                return count >= 2 ? [.racePace, goal.distance.isUpToTenK ? vo2() : .threshold] : [.racePace]
            }
            switch goal.distance {
            case .mile, .fiveK, .tenK:
                return Array([vo2(), .threshold].prefix(count))
            case .halfMarathon:
                return Array([.threshold, vo2()].prefix(count))
            case .marathon:
                return [.threshold]
            }
        }
    }
}

extension InjuryStatus {
    var closedDate: Date? {
        switch self {
        case .closed(let date): date
        case .cleared(let date): date
        case .open: nil
        }
    }
}
