//
//  Benchmarks.swift
//  Wind Run
//

import Foundation

/// BD-5c's benchmark comparison and FB-4m's easy-run trend: like-for-like runs only, and nothing under FB-2's 5%
/// noise counts as change.
enum Benchmarks {
    /// BD-5c, AD-6c: a benchmark 10% or more slower at equal effort, with worse fatigue, is a fatigue check.
    static let fatigueDrop = 0.10
    /// Same rough distance: within 10% when the route can't be told apart.
    static let distanceTolerance = 0.10
    /// BD-5c, FB-4m: temperatures within 5 °C.
    static let temperatureTolerance = 5.0

    /// Two runs that can be compared (BD-5c, FB-4m): both pass the data gate, treadmill only with treadmill, within
    /// 5 °C when both have a temperature (without one, the same heat answer), about the same distance and climb.
    static func alike(_ run: LoggedRun, _ other: LoggedRun, sameDistance: Bool) -> Bool {
        let check = RunDataGate.check(run, runs: [run])
        let otherCheck = RunDataGate.check(other, runs: [other])
        guard check.allowsPaceAnalysis, otherCheck.allowsPaceAnalysis, check.treadmill == otherCheck.treadmill,
              run.pace != nil, other.pace != nil else { return false }
        if let first = run.temperature, let second = other.temperature {
            if abs(first - second) > temperatureTolerance { return false }
        } else if (run.checkIn?.heat ?? .cool) != (other.checkIn?.heat ?? .cool) {
            return false
        }
        if sameDistance, abs(run.meters - other.meters) / max(other.meters, 1) > distanceTolerance { return false }
        if let track = run.track, let otherTrack = other.track,
           abs(track.climbFirstHalf + track.climbSecondHalf - otherTrack.climbFirstHalf - otherTrack.climbSecondHalf) >= RunDataGate.climbDifference {
            return false
        }
        return true
    }

    /// AD-6c's worse fatigue: a morning check above normal in the 3 days up to now, or "worse" energy on the latest
    /// weekly check-in from the 2 weeks before the run.
    static func fatigueWorse(after run: LoggedRun, state: CoachState, now: Date, calendar: Calendar) -> Bool {
        let from = calendar.startOfDay(for: run.start).addingTimeInterval(-2 * 86_400)
        if state.morningChecks.contains(where: { $0.date >= from && $0.date <= now && ($0.fatigue ?? 0) > 4 }) { return true }
        let weekly = state.weeks
            .compactMap(\.checkIn)
            .filter { $0.answeredAt <= now && $0.answeredAt >= run.start.addingTimeInterval(-14 * 86_400) }
            .max { $0.answeredAt < $1.answeredAt }
        return weekly?.energy == .worse
    }

    // MARK: FB-4m

    /// An easy run FB-4m can use: rated 2-3, and without a temperature not answered warm or hotter.
    static func trendRun(_ run: LoggedRun, state: CoachState) -> Bool {
        guard RunAnalysis.isEasyRun(run, state: state), let rpe = run.rpe, (2 ... 3).contains(rpe) else { return false }
        return run.temperature != nil || (run.checkIn?.heat ?? .cool) == .cool
    }

    /// FB-4m faster: 3 or more like-for-like easy runs in the last 2 weeks, this one among them, each at least 5%
    /// faster than the median of its own 4 weeks before. Returns the mean gain. The slower trend is family E's
    /// (the weekly review), and easy pace never raises training paces (PZ-7).
    static func fasterTrend(_ run: LoggedRun, runs: [LoggedRun], state: CoachState) -> Double? {
        guard trendRun(run, state: state) else { return nil }
        // The 2 weeks of recent runs, and the 4 weeks before each.
        let from = run.start.addingTimeInterval(-42 * 86_400)
        let candidates = runs.filter { $0.start >= from && $0.start <= run.start && trendRun($0, state: state) }
        func gain(_ recent: LoggedRun) -> Double? {
            guard let pace = recent.pace else { return nil }
            let monthBefore = recent.start.addingTimeInterval(-28 * 86_400)
            let paces = candidates
                .filter { $0.start >= monthBefore && $0.start < recent.start && alike(recent, $0, sameDistance: false) }
                .compactMap(\.pace)
                .sorted()
            guard paces.count >= 3 else { return nil }
            let median = paces[paces.count / 2]
            let fraction = (median - pace) / median
            return fraction >= RunDataGate.noise ? fraction : nil
        }
        guard let current = gain(run) else { return nil }
        let twoWeeks = run.start.addingTimeInterval(-14 * 86_400)
        let others = candidates.filter { $0.id != run.id && $0.start >= twoWeeks }.compactMap(gain)
        guard others.count >= 2 else { return nil }
        let gains = [current] + others
        return gains.reduce(0, +) / Double(gains.count)
    }
}

extension RunReviewer {
    /// BD-5c: a benchmark run against the newest like-for-like earlier one (`earlier` are previous benchmark runs).
    /// A gain is a pace 5% or more faster at the same RPE, or the same pace (within 5%) rated a point or more lower;
    /// anything else within 5% is no clear change. 10% or more slower at the same RPE with worse fatigue starts
    /// AD-6c's week of rest or easy runs (`fatigueCheck`). Without RPE on both runs there's nothing to compare.
    static func compareBenchmark(_ run: LoggedRun, earlier: [LoggedRun], state: CoachState, now: Date, calendar: Calendar) -> (notes: [CoachNote], fatigueCheck: Bool) {
        guard let pace = run.pace, let rpe = run.rpe,
              let previous = earlier
                .filter({ $0.id != run.id && $0.start < run.start && $0.rpe != nil && Benchmarks.alike(run, $0, sameDistance: true) })
                .max(by: { $0.start < $1.start }),
              let previousPace = previous.pace, let previousRPE = previous.rpe else { return ([], false) }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: previous.start), to: calendar.startOfDay(for: run.start)).day ?? 0
        let ago = CoachFormat.weeks(max(1, Int((Double(days) / 7).rounded())))
        let faster = (previousPace - pace) / previousPace
        if faster >= RunDataGate.noise, rpe <= previousRPE {
            let text = rpe == previousRPE
                ? "Same easy effort, \(RunInsights.percent(faster)) faster than \(ago) ago."
                : "\(RunInsights.percent(faster)) faster than \(ago) ago, at an easier effort."
            return ([CoachNote(.insight, text)], false)
        }
        if abs(faster) < RunDataGate.noise, rpe <= previousRPE - 1 {
            return ([CoachNote(.insight, "Same pace as \(ago) ago, at an easier effort.")], false)
        }
        // At least the same effort and 10% slower: with worse fatigue, AD-6c's easy week.
        if rpe >= previousRPE, -faster >= Benchmarks.fatigueDrop, Benchmarks.fatigueWorse(after: run, state: state, now: now, calendar: calendar) {
            return ([CoachNote(.plan, "Your check run was well off your usual at the same effort. Let's rest or run easy for a week.")], true)
        }
        if rpe == previousRPE, abs(faster) < RunDataGate.noise {
            return ([CoachNote(.insight, "Same easy effort, about the same pace as \(ago) ago.")], false)
        }
        return ([], false)
    }
}
