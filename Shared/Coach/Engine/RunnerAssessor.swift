//
//  RunnerAssessor.swift
//  Wind Run
//

import Foundation

/// Turns intake answers into the runner's tier, overlays, recovery tier, risk score, levels and
/// starting numbers (TI-1 to TI-5, RB-2, RB-6, CL-3, HL-7, HL-9, IN-21).
enum RunnerAssessor {
    /// A slow easy pace for converting answers when the runner gave none (IN-21's cautious side).
    static let fallbackPace: Double = 450

    static func assess(_ intake: CoachIntake, injuries: [InjuryReport] = [], now: Date, calendar: Calendar) -> RunnerAssessment {
        let age = intake.age(on: now, calendar: calendar) ?? 18
        let history = intake.history ?? .notYet
        let months = intake.monthsRunning ?? history.lowMonths
        let breakWeeks = intake.breakBeganWeeksAgo ?? 0
        let onBreak = breakWeeks >= 4
        let longBreak = breakWeeks >= 13
        let recent = intake.lastFourWeeks
        let before = intake.beforeBreak
        let runs30 = intake.runs30Minutes ?? false
        let pace = intake.easyPace
        let convertPace = pace ?? fallbackPace

        // TI-1: the lowest tier the runner fits. A Returning runner whose break began under 13 weeks ago is tiered
        // on the weeks before it.
        let tieringRuns = onBreak && !longBreak ? (before?.runsPerWeek ?? recent?.runsPerWeek ?? 0) : (recent?.runsPerWeek ?? 0)
        let tier: RunnerTier
        if !runs30 || history == .notYet || longBreak {
            tier = .starter
        } else if months < 12 || tieringRuns <= 2 {
            tier = .novice
        } else if history == .overTwoYears && tieringRuns >= 4 && (intake.racedLastYear || intake.sessionsLastYear || intake.sessionsForAYearOrMore) {
            tier = .experienced
        } else {
            tier = .regular
        }

        // RB-2: recovery flags from other training (a skipped IN-10 is F1) and work.
        let activities = intake.otherTraining ?? []
        let hardSessions = activities.filter { $0.activityClass == .hard }.reduce(0) { $0 + $1.sessionsPerWeek }
        let vigorousMinutes = activities.filter { $0.effort >= 5 }.reduce(0.0) { $0 + Double($1.sessionsPerWeek) * $1.minutes }
        let legDays = activities.filter(\.isLegSession).reduce(0) { $0 + $1.sessionsPerWeek }
        var recovery = RecoveryAssessment(
            otherTrainingFlag: intake.otherTraining == nil || hardSessions >= 2 || vigorousMinutes >= 180,
            workFlag: intake.physicalWork == true,
            hardSessionsPerWeek: hardSessions,
            legDaysPerWeek: legDays
        )
        // RB-6: new or doubled hard training, or heavy-leg or vigorous work ≥3 times a week, drops the level for 8 weeks.
        let heavyOrVigorous = activities.filter { ($0.isLegSession && $0.heavy) || $0.activityClass == .hard }.reduce(0) { $0 + $1.sessionsPerWeek }
        if activities.contains(where: { $0.activityClass == .hard && $0.newOrDoubled }) || heavyOrVigorous >= 3 {
            recovery.levelDropUntil = calendar.date(byAdding: .weekOfYear, value: 8, to: now)
        }

        // TI-3: overlays. Early-window history: months × 4.3 × V0 (pre-break V0 after a break), at most 200 km.
        let creditVolume = (onBreak ? before?.weeklyLow : recent?.weeklyLow)?.value(in: .distance, pace: convertPace) ?? 0
        let creditedWeeks = months * CoachLimits.weeksPerMonth
        let creditedMeters = min(CoachLimits.earlyWindowMeters, creditedWeeks * creditVolume)
        let windowOver = creditedWeeks >= CoachLimits.earlyWindowWeeks && creditedMeters >= CoachLimits.earlyWindowMeters
        let returning = onBreak || (history > .notYet && (recent?.runsPerWeek ?? 0) < 2)
        let overlays = RunnerOverlays(
            earlyWindow: tier <= .novice && !windowOver,
            creditedWeeks: creditedWeeks,
            creditedMeters: creditedMeters,
            returning: returning,
            trained: intake.racedLastYear && intake.sessionsForAYearOrMore,
            firstTimer: intake.finished != .yesRecently
        )

        // TI-4: the risk score.
        var factors: [RiskFactor] = []
        let yearAgo = calendar.date(byAdding: .month, value: -12, to: now) ?? now
        if injuries.contains(where: { $0.everIntenseOrSevere && $0.reportedAt >= yearAgo }) { factors.append(.recentInjury) }
        if tier <= .novice, let bmi = intake.bmi, bmi >= 30 { factors.append(.bmi) }
        if months < 12 { factors.append(.underOneYear) }
        let weeklyKm = (recent?.weeklyLow.value(in: .distance, pace: convertPace) ?? 0) / 1_000
        if age >= 65 || (age >= 50 && (months < 12 || weeklyKm < 20)) { factors.append(.age) }
        switch recovery.tier {
        case .normal: break
        case .reduced: factors.append(.recoveryReduced)
        case .low: factors.append(.recoveryLow)
        }
        let risk = RiskScore(factors: factors)

        // CL-3: preset and ceiling from the risk score, lowered by the recovery tier, RB-6 and the injury window.
        var preset: CommitmentLevel
        var ceiling: CommitmentLevel
        switch risk.points {
        case 0: (preset, ceiling) = (.steady, .ambitious)
        case 1: (preset, ceiling) = (.gentle, .steady)
        default: (preset, ceiling) = (.gentle, .gentle)
        }
        ceiling = min(ceiling, recovery.tier.levelCeiling)
        if let until = recovery.levelDropUntil, until > now { ceiling = ceiling.lower }
        let windowStart = calendar.date(byAdding: .weekOfYear, value: -12, to: now) ?? now
        if injuries.contains(where: { $0.everIntenseOrSevere && ($0.firstRunBack ?? $0.reportedAt) >= windowStart }) {
            ceiling = min(ceiling.lower, .steady)
        }
        preset = min(preset, ceiling)
        let lockedReason = ceiling < .ambitious ? risk.largestFactor?.reason ?? RiskFactor.recoveryReduced.reason : nil

        // TI-2: the starter entry.
        var entry: StarterEntry?
        let nonStop = intake.longestNonStop ?? .underOneMinute
        if tier == .starter && !(intake.runs30Minutes == true && onBreak) {
            let function = intake.dailyFunction ?? (intake.runs30Minutes == true ? .good : .poor)
            let newAt65 = age >= 65 && (history == .notYet || onBreak)
            if (nonStop == .underOneMinute && intake.walksBriskly30 != true) || function == .poor || newAt65 {
                entry = .walkStage(minutes: 10)
            } else if nonStop <= .oneToFive && risk.isHigh {
                entry = .shortRunWalk
            } else if nonStop <= .oneToFive {
                entry = .ladder(step: RunWalkStep.ladderIndex(minutes: 1))
            } else if nonStop == .fiveToFifteen {
                entry = .ladder(step: RunWalkStep.ladderIndex(minutes: 4.5))
            } else {
                entry = .ladder(step: RunWalkStep.ladderIndex(minutes: 15))
            }
        }

        // The volume unit and V0 (TI-5, IN-21).
        let weekly = (onBreak ? before : recent) ?? recent
        let unit: VolumeUnit
        if entry != nil {
            unit = .time
        } else if pace == nil, weekly?.weeklyLow.unit == .time || weekly?.longest?.unit == .time {
            unit = .time
        } else if weekly == nil, pace == nil {
            unit = .time
        } else {
            unit = .distance
        }
        let v0 = recent?.weeklyLow.value(in: unit, pace: convertPace) ?? 0
        let reported = recent?.longest.flatMap { $0.value(in: unit, pace: convertPace) }
        let planning = reported.map { min(0.9 * $0, 0.5 * v0) } ?? 0.5 * v0

        // HL-9: runs a week, at most.
        let offered = intake.runDays.count
        var runsCap = tier.runsCap
        if tier == .regular, (recent?.runsPerWeek ?? 0) >= 5, recent?.fiveRunsForThreeMonths == true, age < 50 { runsCap = 5 }
        if risk.isHigh || recovery.tier == .low { runsCap = min(runsCap, 3) }
        if intake.goal.distance == .marathon, intake.finished != .yesRecently, (recent?.runsPerWeek ?? 0) < 4 { runsCap = min(runsCap, 3) }
        runsCap = min(runsCap, offered)
        let habit = offered < 2

        let current = entry != nil ? 3 : max(1, recent?.runsPerWeek ?? (before?.runsPerWeek ?? 2))
        let runsPerWeek = habit ? 1 : max(2, min(current, runsCap))

        // HL-7: Q per 7 days.
        var qCap = min(2, runsPerWeek / 2)
        if age >= 65 || risk.isHigh || recovery.tier == .low || (legDays >= 2 && hardSessions > legDays) { qCap = min(qCap, 1) }

        // HL-6, HL-14: a run length the runner already sustains, when it is above 2/3 of the long run.
        var sustained: Double?
        if let recent, recent.runsPerWeek >= 2, v0 > 0 {
            let usual = max(0, v0 - (reported ?? planning)) / Double(recent.runsPerWeek - 1)
            if usual > planning * CoachLimits.otherRunShare { sustained = usual }
        }

        let start = StartingPoint(
            volumeUnit: unit,
            v0: v0,
            reportedLongest: reported.map { Load($0, in: unit, pace: pace) },
            planningLongest: Load(planning, in: unit, pace: pace),
            runsPerWeek: runsPerWeek,
            currentQ: recent?.hardSessionsPerWeek ?? 0,
            sustainedRunLength: sustained,
            calibrates: entry == nil,
            preBreakVolume: before?.weeklyLow.value(in: unit, pace: convertPace),
            preBreakLongest: before?.longest.flatMap { $0.value(in: unit, pace: convertPace) }.map { Load($0, in: unit, pace: pace) }
        )

        return RunnerAssessment(
            assessedAt: now,
            age: age,
            tier: tier,
            overlays: overlays,
            starterEntry: entry,
            recovery: recovery,
            risk: risk,
            levels: LevelOptions(preset: preset, ceiling: ceiling, lockedReason: lockedReason),
            start: start,
            habitMode: habit,
            runsCap: max(1, runsCap),
            qCap: qCap,
            monthsRunning: months,
            runs30Minutes: runs30
        )
    }
}

extension NonStopBand: Comparable {
    static func < (lhs: NonStopBand, rhs: NonStopBand) -> Bool { lhs.lowMinutes < rhs.lowMinutes }
}
