//
//  LoadMetrics.swift
//  Wind Run
//

import Foundation

/// Runs less than 15 minutes apart, merged into one session (Terms).
struct RunSessionLoad: Hashable {
    var start: Date
    var end: Date
    var runIDs: [UUID]
    /// Distance, or 0 when no run in the session measured one.
    var meters: Double
    /// Moving time, walking inside the runs included (Terms).
    var seconds: Double
    /// Moving time less walking, which run-walk plans count as volume.
    var runningSeconds: Double

    var load: Load { Load(meters: meters, seconds: seconds) }

    /// The session's volume in a plan's unit. A run without distance counts in a distance plan
    /// at `pace` (seconds per km), or not at all without one.
    func volume(in unit: VolumeUnit, pace: Double?) -> Double {
        switch unit {
        case .distance:
            if meters > 0 { return meters }
            guard let pace, pace > 0 else { return 0 }
            return runningSeconds / pace * 1_000
        case .time:
            return runningSeconds
        }
    }
}

/// What intake reported, used until the logs can stand on their own (TI-5, HL-17).
struct LoadSeed: Codable, Hashable {
    /// The plan's first day. The seed's long run counts for the 30 days from here.
    var date: Date
    /// The planning P-L30: min(0.9 × reported longest, 0.5 × V0).
    var longest: Load
    /// Logged runs count in full up to the reported longest in the seed's 30 days (TI-5).
    var reportedLongest: Load?
    /// V0 in the plan's unit, which fills the weeks before the plan for W4max.
    var weeklyVolume: Double
}

/// P-L30, W4max, weekly volumes and the gap reference, from logged runs (Terms, HL-1, HL-2, TI-5, AD-10).
enum LoadMetrics {
    static let windowDays = 30

    // MARK: Sessions

    /// Merges runs that start less than 15 minutes after the previous one ended.
    static func sessions(from runs: [LoggedRun]) -> [RunSessionLoad] {
        var sessions: [RunSessionLoad] = []
        for run in runs.sorted(by: { $0.start < $1.start }) {
            if var last = sessions.last, run.start.timeIntervalSince(last.end) < CoachLimits.sessionMergeGap {
                last.end = max(last.end, run.end)
                last.runIDs.append(run.id)
                last.meters += run.meters
                last.seconds += run.movingSeconds
                last.runningSeconds += run.runningSeconds
                sessions[sessions.count - 1] = last
            } else {
                sessions.append(RunSessionLoad(
                    start: run.start,
                    end: run.end,
                    runIDs: [run.id],
                    meters: run.meters,
                    seconds: run.movingSeconds,
                    runningSeconds: run.runningSeconds
                ))
            }
        }
        return sessions
    }

    // MARK: P-L30

    /// P-L30 just before `date`: the longest session in the 30 days before it, each counted at most
    /// 1.10 × the P-L30 in force when it was run, on distance and on time separately (Terms).
    /// - Parameters:
    ///   - seed: intake's starting long run, in force for its first 30 days (TI-5).
    ///   - countFrom: sessions before this date don't count (AD-10: only post-return runs).
    ///   - ceiling: P-L30 stays at or below this, side by side (AD-10, AD-14c: ≤ the reference).
    ///   - capOnly: sessions with these runs count at most the P-L30 in force: the goal race never raises it (HL-1).
    static func longest(
        before date: Date,
        sessions: [RunSessionLoad],
        seed: LoadSeed?,
        countFrom: Date? = nil,
        ceiling: Load? = nil,
        capOnly: Set<UUID> = [],
        calendar: Calendar
    ) -> Load {
        let counted = countedSessions(before: date, sessions: sessions, seed: seed, countFrom: countFrom, ceiling: ceiling, capOnly: capOnly, calendar: calendar)
        return inForce(at: date, counted: counted[...], seed: seed, seedEnd: seedEnd(seed, calendar: calendar), ceiling: ceiling, calendar: calendar)
    }

    /// P-L30 just before each session's start, in one pass: for each session the same as
    /// `longest(before: session.start, ...)` with the same arguments.
    static func longestBeforeEach(
        sessions: [RunSessionLoad],
        seed: LoadSeed?,
        countFrom: Date? = nil,
        ceiling: Load? = nil,
        capOnly: Set<UUID> = [],
        calendar: Calendar
    ) -> [Date: Load] {
        let counted = countedSessions(before: .distantFuture, sessions: sessions, seed: seed, countFrom: countFrom, ceiling: ceiling, capOnly: capOnly, calendar: calendar)
        let seedEnd = self.seedEnd(seed, calendar: calendar)
        var longest: [Date: Load] = [:]
        // Counted sessions inside the 30 days before the current one: [first, next).
        var first = 0
        var next = 0
        for session in sessions.sorted(by: { $0.start < $1.start }) {
            while next < counted.count, counted[next].session.start < session.start { next += 1 }
            let from = windowStart(before: session.start, calendar: calendar)
            while first < next, counted[first].session.start < from { first += 1 }
            longest[session.start] = inForce(at: session.start, counted: counted[first ..< next], seed: seed, seedEnd: seedEnd, ceiling: ceiling, calendar: calendar)
        }
        return longest
    }

    /// The uncapped longest session of the 30 days before `date` (detection L30), kept only to flag spikes.
    static func detectionLongest(before date: Date, sessions: [RunSessionLoad], calendar: Calendar) -> Load {
        let from = windowStart(before: date, calendar: calendar)
        return sessions
            .filter { $0.start >= from && $0.start < date }
            .reduce(Load.zero) { Load(meters: max($0.meters, $1.meters), seconds: max($0.seconds, $1.seconds)) }
    }

    /// Each session with the value it counts at, in time order.
    static func countedSessions(
        before date: Date,
        sessions: [RunSessionLoad],
        seed: LoadSeed?,
        countFrom: Date? = nil,
        ceiling: Load? = nil,
        capOnly: Set<UUID> = [],
        calendar: Calendar
    ) -> [(session: RunSessionLoad, counted: Load)] {
        var counted: [(session: RunSessionLoad, counted: Load)] = []
        let seedEnd = self.seedEnd(seed, calendar: calendar)
        // The first counted session inside the 30 days before the current one: the window only moves forward.
        var windowFirst = 0
        for session in sessions.sorted(by: { $0.start < $1.start }) where session.start < date {
            if let countFrom, session.start < countFrom { continue }
            let from = windowStart(before: session.start, calendar: calendar)
            while windowFirst < counted.count, counted[windowFirst].session.start < from { windowFirst += 1 }
            let force = countFrom == nil ? inForce(at: session.start, counted: counted[windowFirst...], seed: seed, seedEnd: seedEnd, ceiling: ceiling, calendar: calendar) : .zero
            let allowance = seedEnd.map { session.start < $0 } == true ? seed?.reportedLongest : nil
            let raceOnly = !capOnly.isDisjoint(with: session.runIDs)
            var value = Load(
                meters: countedSide(session.meters, force: force.meters, allowance: allowance?.meters, raceOnly: raceOnly),
                seconds: countedSide(session.seconds, force: force.seconds, allowance: allowance?.seconds, raceOnly: raceOnly)
            )
            if let ceiling { value = value.capped(at: ceiling) }
            counted.append((session, value))
        }
        return counted
    }

    private static func countedSide(_ value: Double, force: Double, allowance: Double?, raceOnly: Bool) -> Double {
        guard value > 0 else { return 0 }
        guard force > 0 else { return value }
        if raceOnly { return min(value, force) }
        let cap = max(force * CoachLimits.sessionGrowth, allowance ?? 0)
        return min(value, cap)
    }

    private static func inForce(
        at date: Date,
        counted: ArraySlice<(session: RunSessionLoad, counted: Load)>,
        seed: LoadSeed?,
        seedEnd: Date?,
        ceiling: Load?,
        calendar: Calendar
    ) -> Load {
        let from = windowStart(before: date, calendar: calendar)
        var best = Load.zero
        for (session, value) in counted where session.start >= from && session.start < date {
            best = Load(meters: max(best.meters, value.meters), seconds: max(best.seconds, value.seconds))
        }
        if let seed, let seedEnd, date < seedEnd {
            best = Load(meters: max(best.meters, seed.longest.meters), seconds: max(best.seconds, seed.longest.seconds))
        }
        if let ceiling { best = best.capped(at: ceiling) }
        return best
    }

    /// The seed counts from the plan's first day for 30 days (TI-5).
    static func seedActive(_ seed: LoadSeed?, at date: Date, calendar: Calendar) -> Bool {
        guard let end = seedEnd(seed, calendar: calendar) else { return false }
        return date < end
    }

    /// The day the seed stops counting.
    static func seedEnd(_ seed: LoadSeed?, calendar: Calendar) -> Date? {
        guard let seed else { return nil }
        return calendar.date(byAdding: .day, value: windowDays, to: calendar.startOfDay(for: seed.date))
    }

    private static func windowStart(before date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -windowDays, to: date) ?? date
    }

    // MARK: Weekly volume

    /// The first day of plan week `index` (negative for the weeks before the plan).
    static func weekStart(_ index: Int, planStart: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: index * 7, to: calendar.startOfDay(for: planStart)) ?? planStart
    }

    /// Volume done between two dates, in the plan's unit.
    static func volume(from start: Date, to end: Date, sessions: [RunSessionLoad], unit: VolumeUnit, pace: Double?) -> Double {
        sessions
            .filter { $0.start >= start && $0.start < end }
            .reduce(0) { $0 + $1.volume(in: unit, pace: pace) }
    }

    /// Volume done in plan week `index`.
    static func doneVolume(week index: Int, planStart: Date, sessions: [RunSessionLoad], unit: VolumeUnit, pace: Double?, calendar: Calendar) -> Double {
        volume(
            from: weekStart(index, planStart: planStart, calendar: calendar),
            to: weekStart(index + 1, planStart: planStart, calendar: calendar),
            sessions: sessions,
            unit: unit,
            pace: pace
        )
    }

    /// W4max in force during plan week `index`: the highest of the 4 weeks before it, each counted at most
    /// 1.20 × the W4max in force during that week (Terms). With a seed, the weeks before the plan count
    /// as V0 (TI-5: one seed, never above the report); without one they come from the logs.
    static func w4max(week index: Int, planStart: Date, sessions: [RunSessionLoad], unit: VolumeUnit, pace: Double?, seed: LoadSeed?, calendar: Calendar) -> Double {
        let first = index - 8
        var counted: [Int: Double] = [:]
        func force(_ week: Int) -> Double {
            (week - 4 ..< week).map { counted[$0] ?? 0 }.max() ?? 0
        }
        for week in first ..< index {
            let actual: Double
            if week < 0, let seed {
                actual = seed.weeklyVolume
            } else {
                actual = doneVolume(week: week, planStart: planStart, sessions: sessions, unit: unit, pace: pace, calendar: calendar)
            }
            let inForce = force(week)
            counted[week] = inForce > 0 && week >= first + 4 ? min(actual, inForce * CoachLimits.weekGrowth) : actual
        }
        return force(index)
    }

    /// HL-2's weekly cap: 1.20 × W4max, or W4max + 10 min when W4max is under 60 min (time plans only).
    static func weekCap(w4max: Double, unit: VolumeUnit) -> Double {
        if unit == .time, w4max < CoachLimits.smallWeekSeconds {
            return w4max + CoachLimits.smallWeekAllowanceSeconds
        }
        return w4max * CoachLimits.weekGrowth
    }

    /// The most volume in any 7 days ending on a completed day from `from` up to `through` (HL-2's spike check).
    static func maxRolling7Days(from: Date, through: Date, sessions: [RunSessionLoad], unit: VolumeUnit, pace: Double?, calendar: Calendar) -> Double {
        var best = 0.0
        var day = calendar.startOfDay(for: from)
        let last = calendar.startOfDay(for: through)
        while day <= last {
            guard let end = calendar.date(byAdding: .day, value: 1, to: day),
                  let start = calendar.date(byAdding: .day, value: -6, to: day) else { break }
            best = max(best, volume(from: start, to: end, sessions: sessions, unit: unit, pace: pace))
            day = end
        }
        return best
    }

    // MARK: Gaps and the return reference (AD-10)

    /// A qualifying run: ≥20 min, or ≥50% of the usual easy run, whichever is shorter (AD-5).
    static func qualifies(_ session: RunSessionLoad, usualEasySeconds: Double?) -> Bool {
        let half = (usualEasySeconds ?? .infinity) * 0.5
        return session.runningSeconds >= min(CoachLimits.minimumRunSeconds, half)
    }

    /// The last qualifying session before `date`.
    static func lastQualifying(before date: Date, sessions: [RunSessionLoad], usualEasySeconds: Double?) -> RunSessionLoad? {
        sessions.filter { $0.start < date && qualifies($0, usualEasySeconds: usualEasySeconds) }.max { $0.start < $1.start }
    }

    /// Whole days from the last qualifying run to `date`, or nil when there is none.
    static func daysSinceQualifyingRun(at date: Date, sessions: [RunSessionLoad], usualEasySeconds: Double?, calendar: Calendar) -> Int? {
        guard let last = lastQualifying(before: date, sessions: sessions, usualEasySeconds: usualEasySeconds) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: last.start), to: calendar.startOfDay(for: date)).day
    }

    /// AD-10's reference: the mean of the last 3 full plan weeks before the gap, and the longest
    /// session in the 30 days before it. Until 3 logged weeks exist, V0 and the planning P-L30.
    static func gapReference(
        gapStart: Date,
        planStart: Date,
        sessions: [RunSessionLoad],
        unit: VolumeUnit,
        pace: Double?,
        seed: LoadSeed?,
        fallbackVolume: Double,
        fallbackLongest: Load,
        calendar: Calendar
    ) -> (volume: Double, longest: Load) {
        let gapWeek = (calendar.dateComponents([.day], from: calendar.startOfDay(for: planStart), to: calendar.startOfDay(for: gapStart)).day ?? 0) / 7
        let weeks = (gapWeek - 3 ..< gapWeek).filter { $0 >= 0 }
        let longest = longest(before: gapStart, sessions: sessions, seed: seed, calendar: calendar)
        guard weeks.count == 3 else {
            return (fallbackVolume, longest.meters > 0 || longest.seconds > 0 ? longest : fallbackLongest)
        }
        let mean = weeks
            .map { doneVolume(week: $0, planStart: planStart, sessions: sessions, unit: unit, pace: pace, calendar: calendar) }
            .reduce(0, +) / 3
        return (mean, longest.meters > 0 || longest.seconds > 0 ? longest : fallbackLongest)
    }

    // MARK: Calibration (TI-5)

    /// After week 2: a logged weekly mean ≥80% of V0 keeps V0, otherwise V0 becomes the mean. V0 only moves down.
    static func rebasedV0(_ v0: Double, loggedWeeks: [Double]) -> Double {
        guard !loggedWeeks.isEmpty else { return v0 }
        let mean = loggedWeeks.reduce(0, +) / Double(loggedWeeks.count)
        return mean >= 0.8 * v0 ? v0 : min(v0, mean)
    }
}
