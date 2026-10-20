//
//  Progression.swift
//  Wind Run
//

import Foundation

/// The path math that the feasibility check, the week planner and the injury review share (CL-1, CL-2, RC-4, RC-5).
enum Progression {
    /// Calibration weeks before the level's cycle starts (TI-5).
    static let calibrationWeeks = 2
    /// A time goal's speed block (RC-4 step 5).
    static let speedBlockWeeks = 4

    /// New-longest (N) weeks to take the long run from `start` to `target` at 10% each (RC-4 step 3).
    static func newLongestWeeks(from start: Double, to target: Double) -> Int {
        guard start > 0, target > start else { return 0 }
        return Int((log(target / start) / log(CoachLimits.sessionGrowth) - 1e-9).rounded(.up))
    }

    /// Loading (N or H) weeks to take the weekly volume from `start` to `target` at the level's rate (RC-4 step 4).
    static func loadingWeeks(from start: Double, to target: Double, rate: Double) -> Int {
        guard start > 0, target > start, rate > 0 else { return 0 }
        return Int((log(target / start) / log(1 + rate) - 1e-9).rounded(.up))
    }

    /// Weeks on `cycle`, starting at `position`, until `count` weeks that `counts` have passed, the last one included.
    static func weeksToPlace(_ count: Int, on cycle: [CycleWeek], from position: Int = 0, counting counts: (CycleWeek) -> Bool) -> Int {
        guard count > 0, !cycle.isEmpty, cycle.contains(where: counts) else { return 0 }
        var placed = 0
        var weeks = 0
        while placed < count {
            if counts(cycle[(position + weeks) % cycle.count]) { placed += 1 }
            weeks += 1
        }
        return weeks
    }

    /// Weeks to place `count` N weeks (the long-run path).
    static func longRunPathWeeks(newLongest count: Int, on cycle: [CycleWeek], from position: Int = 0) -> Int {
        weeksToPlace(count, on: cycle, from: position) { $0 == .newLongest }
    }

    /// Weeks to place `count` loading weeks (the volume path).
    static func volumePathWeeks(loading count: Int, on cycle: [CycleWeek], from position: Int = 0) -> Int {
        weeksToPlace(count, on: cycle, from: position) { $0.isLoading }
    }

    /// The long run after `weeks` weeks on the cycle: ×1.10 for each N week, capped at `ceiling` (HL-5).
    static func projectedLongRun(from start: Double, weeks: Int, on cycle: [CycleWeek], from position: Int = 0, ceiling: Double = .infinity) -> Double {
        guard !cycle.isEmpty, weeks > 0 else { return min(start, ceiling) }
        let count = (0 ..< weeks).filter { cycle[(position + $0) % cycle.count] == .newLongest }.count
        return min(start * pow(CoachLimits.sessionGrowth, Double(count)), ceiling)
    }

    /// The weekly volume of the last loading week after `weeks` weeks on the cycle: × (1 + rate) for each loading week.
    static func projectedVolume(from start: Double, weeks: Int, on cycle: [CycleWeek], from position: Int = 0, rate: Double, ceiling: Double = .infinity) -> Double {
        guard !cycle.isEmpty, weeks > 0 else { return min(start, ceiling) }
        let count = (0 ..< weeks).filter { cycle[(position + $0) % cycle.count].isLoading }.count
        return min(start * pow(1 + rate, Double(count)), ceiling)
    }

    /// The taper's length in weeks before an event (EV-1): 1 for 5K and 10K, 2 for the half, 3 for the marathon.
    static func taperWeeks(for distance: RaceDistance) -> Int {
        distance.taperDays / 7
    }

    /// RC-5's earliest Green weeks on the long-run path: calibration, the N weeks placed on the cycle, and the taper.
    static func earliestLongRunWeeks(from start: Double, to target: Double, cycle: [CycleWeek], calibrates: Bool, taperWeeks: Int) -> Int? {
        guard target > 0 else { return nil }
        let build = longRunPathWeeks(newLongest: newLongestWeeks(from: start, to: target), on: cycle)
        if build == 0 { return nil }
        return build + (calibrates ? calibrationWeeks : 0) + taperWeeks
    }

    /// RC-4 step 8: likely = round(1.15 × earliest).
    static func likelyWeeks(earliest: Int) -> Int {
        Int((1.15 * Double(earliest)).rounded())
    }

    /// RC-4 step 7: max(2, ceil(build ÷ 6)), plus 1 per 6 build weeks in the Low recovery tier.
    static func bufferWeeks(buildWeeks: Int, recovery: RecoveryTier) -> Int {
        let sixes = Int((Double(max(0, buildWeeks)) / 6).rounded(.up))
        let extra = recovery == .low ? max(0, buildWeeks) / 6 : 0
        return max(2, sixes) + extra
    }
}
