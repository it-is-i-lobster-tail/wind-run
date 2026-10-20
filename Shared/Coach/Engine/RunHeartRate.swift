//
//  RunHeartRate.swift
//  Wind Run
//

import Foundation

/// Heart rate over one stretch of a run, for decoupling and pace at heart rate (FB-4k, FB-4l).
struct RunHeartRateWindow: Codable, Hashable {
    var seconds: Double
    var meters: Double
    /// Mean decision-grade heart rate over the stretch, in bpm.
    var mean: Double
    /// Climb inside the stretch, for FB-4l's 5 m limit.
    var climbMeters: Double?

    init(seconds: Double, meters: Double, mean: Double, climbMeters: Double? = nil) {
        self.seconds = seconds
        self.meters = meters
        self.mean = mean
        self.climbMeters = climbMeters
    }

    /// Meters per second.
    var speed: Double { seconds > 0 ? meters / seconds : 0 }

    /// Seconds per km.
    var pace: Double { meters > 0 ? seconds / meters * 1_000 : 0 }
}

/// One work step's heart rate from its 2nd minute, in the order of the run's work steps (PZ-10's rep grading).
struct StepHeartRate: Codable, Hashable {
    /// Mean from the step's 2nd minute to its end, in bpm.
    var mean: Double?
    /// The highest value in the step's last minute (PZ-12's VO2max row).
    var lastMinutePeak: Double?
    /// Share of the graded part with at least one sample per 10 s (check 2).
    var coverage: Double

    init(mean: Double?, lastMinutePeak: Double? = nil, coverage: Double = 1) {
        self.mean = mean
        self.lastMinutePeak = lastMinutePeak
        self.coverage = coverage
    }
}

/// A run's heart rate as the app reads it from HealthKit on the device, each time it calls the coach.
/// The app never stores it with the plan, and the coach turns it only into notes on the run: heart rate and
/// anything derived from it stay on the device, never in iCloud (PZ-10, PZ-13, App Review 5.1.3).
struct RunHeartRate: Codable, Hashable {
    var source: HeartRateDevice
    /// "Use heart rate for coaching" is On (IN-17). Show only makes every run's heart rate display only.
    var useForCoaching: Bool
    /// More than one sensor in the run, or another app's thin data (Garmin min and max, Polar averages, WHOOP).
    var mixedOrThirdParty: Bool
    /// Share of moving time with at least one sample per 10 s (check 2).
    var coverage: Double
    /// Heart rate within ±3 of step rate for more than 60 s (check 4); nil when step rate wasn't recorded.
    var cadenceLock: Bool?
    /// A value outside 30-210 bpm, or a jump of 30 bpm or more within 5 s (check 5).
    var implausible: Bool
    /// Dropouts on a cold-weather run (check 6); nil when the run wasn't cold or it isn't known.
    var coldDropouts: Bool?
    /// Mean over the run's decision-grade minutes: after minute 5 with a strap, or the Watch's steady
    /// segments of 5 min or more that start after minute 5. Nil when there are none.
    var mean: Double?
    /// Minutes 5-10, for pace at heart rate (FB-4l).
    var minutes5to10: RunHeartRateWindow?
    /// Each half after the first km and minute 5, for decoupling (FB-4k).
    var firstHalf: RunHeartRateWindow?
    var secondHalf: RunHeartRateWindow?
    /// The work steps in order, each from its 2nd minute (PZ-10).
    var workSteps: [StepHeartRate]
    /// The highest 30-s average over the run's decision-grade minutes, for max heart rate (PZ-11).
    var peak30s: Double?
    /// The decision-grade mean from minute 10 to the finish, for threshold heart rate (PZ-11).
    var fromMinute10: Double?
    /// The lab max from the runner's settings (IN-17), so the run's review uses the zones the app shows.
    var labMax: Double?

    init(
        source: HeartRateDevice,
        useForCoaching: Bool = true,
        mixedOrThirdParty: Bool = false,
        coverage: Double,
        cadenceLock: Bool? = false,
        implausible: Bool = false,
        coldDropouts: Bool? = nil,
        mean: Double? = nil,
        minutes5to10: RunHeartRateWindow? = nil,
        firstHalf: RunHeartRateWindow? = nil,
        secondHalf: RunHeartRateWindow? = nil,
        workSteps: [StepHeartRate] = [],
        peak30s: Double? = nil,
        fromMinute10: Double? = nil,
        labMax: Double? = nil
    ) {
        self.source = source
        self.useForCoaching = useForCoaching
        self.mixedOrThirdParty = mixedOrThirdParty
        self.coverage = coverage
        self.cadenceLock = cadenceLock
        self.implausible = implausible
        self.coldDropouts = coldDropouts
        self.mean = mean
        self.minutes5to10 = minutes5to10
        self.firstHalf = firstHalf
        self.secondHalf = secondHalf
        self.workSteps = workSteps
        self.peak30s = peak30s
        self.fromMinute10 = fromMinute10
        self.labMax = labMax
    }
}

extension RunHeartRate {
    /// The runner's heart-rate numbers (PZ-11, PZ-12): PaceCalculator's estimate and lab value, raised by an observed
    /// max, with the threshold HR and the personal easy ceiling, all from the logged runs. The app calls it on the
    /// device with every run it holds; nothing in the result goes into the plan's state (PZ-13). With Show only, or
    /// a source that can't coach, only the estimate applies (IN-17).
    static func zones(age: Int, settings: HeartRateSettings, runs: [LoggedRun], state: CoachState, calendar: Calendar) -> HeartRateZones {
        guard settings.canCoach else { return PaceCalculator.heartRateZones(age: age, settings: settings) }
        let usable = RunDataGate.usableRuns(runs)
        var zones = PaceCalculator.heartRateZones(
            age: age,
            settings: settings,
            observedMax: HeartRateRules.observedMax(age: age, runs: usable, state: state),
            threshold: HeartRateRules.thresholdHeartRate(runs: usable, state: state, calendar: calendar)
        )
        zones.personalEasyCeiling = HeartRateRules.personalEasyCeiling(runs: usable, device: settings.device, state: state)
        return zones
    }
}

/// One resting heart rate from HealthKit, read on the device each time the app calls the coach. Like a run's
/// heart rate, it never goes into the plan's state (PZ-13).
struct RestingHeartRate: Codable, Hashable {
    /// When the value was recorded. A day's last value is its settled one.
    var date: Date
    var bpm: Double
    /// The source device's identifier: baselines are kept per device, never mixed (PZ-13).
    var device: String

    init(date: Date, bpm: Double, device: String) {
        self.date = date
        self.bpm = bpm
        self.device = device
    }
}

/// PZ-13's resting-HR flag for today: what the coach says, and today's hard session it offers to make easy.
struct RestingHeartRateCheck: Hashable {
    var note: CoachNote
    /// Today's planned Q or long run, if any. A yes is the readiness answer "Legs or energy below normal" for it
    /// (RB-8), so the easy day is offered, never forced.
    var easySessionID: UUID?
}

extension RestingHeartRate {
    /// PZ-13's resting-HR check for today, worked out on the device from HealthKit's resting heart rate. Nil when
    /// the flag isn't raised. The app shows it at most once a day and keeps nothing of it with the plan.
    static func check(_ readings: [RestingHeartRate], settings: HeartRateSettings, state: CoachState, now: Date, calendar: Calendar) -> RestingHeartRateCheck? {
        guard HeartRateRules.restingRaised(readings, settings: settings, on: now, calendar: calendar) else { return nil }
        let session = state.weeks.lazy.flatMap { record in
            record.plan.sessions.lazy.filter { session in
                session.status.isPlanned && (session.isQuality || session.kind == .long) && session.kind != .race && session.kind != .test
                    && calendar.isDate(state.date(of: session, in: record.plan, calendar: calendar), inSameDayAs: now)
            }
        }.first
        return RestingHeartRateCheck(note: CoachNote(.insight, HeartRateRules.restingNote), easySessionID: session?.id)
    }
}

/// The badge each run with heart rate shows (PZ-10).
enum HeartRateBadge: String, Codable {
    case usedForCoaching
    case shownOnly
    case notUsed

    var name: String {
        switch self {
        case .usedForCoaching: "Used for coaching"
        case .shownOnly: "Shown only"
        case .notUsed: "Not used"
        }
    }
}

/// The heart-rate rules that read a run (PZ-10 to PZ-13, FB-4c, FB-4k, FB-4l). Everything here is computed from
/// the runs and resting values the app passes in and returned as notes; nothing is written to the plan's state.
enum HeartRateRules {
    // MARK: The gate (PZ-10)

    /// The run's badge: one source, ≥80% coverage, a strap or the Watch's steady segments, no cadence lock,
    /// plausible values and no cold-weather dropouts. Any unknown check makes it shown only.
    static func badge(_ heartRate: RunHeartRate) -> HeartRateBadge {
        if heartRate.mixedOrThirdParty || heartRate.source == .off { return .notUsed }
        guard heartRate.useForCoaching, heartRate.source == .chestStrap || heartRate.source == .appleWatch else { return .shownOnly }
        guard runChecksPass(heartRate), heartRate.coverage >= 0.8 else { return .shownOnly }
        return heartRate.mean == nil && !heartRate.workSteps.contains(where: { $0.mean != nil }) ? .shownOnly : .usedForCoaching
    }

    /// Checks 1, 4, 5 and 6, which apply to the whole run even when reps are graded on their own.
    static func runChecksPass(_ heartRate: RunHeartRate) -> Bool {
        !heartRate.mixedOrThirdParty && heartRate.cadenceLock == false && !heartRate.implausible && heartRate.coldDropouts != true
    }

    /// The run's decision-grade mean, or nil when the run's heart rate can't be used.
    static func decisionGradeMean(_ run: LoggedRun) -> Double? {
        guard let heartRate = run.heartRate, badge(heartRate) == .usedForCoaching else { return nil }
        return heartRate.mean
    }

    /// Work steps whose heart rate is decision-grade: reps of 3 min or more with a strap, 4 min or more with a Watch,
    /// from their 2nd minute, with the run-level checks passed. Indexed like the run's work steps.
    static func decisionGradeSteps(_ run: LoggedRun) -> [Int: StepHeartRate] {
        guard let heartRate = run.heartRate, heartRate.useForCoaching, runChecksPass(heartRate),
              heartRate.source == .chestStrap || heartRate.source == .appleWatch else { return [:] }
        let minimum: Double = heartRate.source == .chestStrap ? 180 : 240
        let work = (run.steps ?? []).filter(\.isWork)
        var graded: [Int: StepHeartRate] = [:]
        for (index, step) in heartRate.workSteps.enumerated() where index < work.count {
            if work[index].seconds >= minimum, step.coverage >= 0.8, step.mean != nil { graded[index] = step }
        }
        return graded
    }

    // MARK: Max and threshold heart rate (PZ-11)

    /// Only a run the runner marked as a race or all-out effort can raise HRmax or set threshold HR (AD-1).
    static func isAllOut(_ run: LoggedRun) -> Bool {
        run.checkIn?.raceOrAllOut == true
    }

    /// An observed max: the lower of the two highest decision-grade 30-s peaks from races or all-out runs (one is
    /// enough with a chest strap), never above the estimate + 22 bpm. Starters and Novices keep the estimate. The
    /// zones take it only when it is higher than the max in force, so HRmax is never lowered automatically.
    static func observedMax(age: Int, runs: [LoggedRun], state: CoachState) -> Double? {
        guard state.assessment.tier >= .regular else { return nil }
        let peaks = runs
            .filter { isAllOut($0) }
            .compactMap { run -> (peak: Double, strap: Bool)? in
                guard let heartRate = run.heartRate, badge(heartRate) == .usedForCoaching, let peak = heartRate.peak30s else { return nil }
                return (peak, heartRate.source == .chestStrap)
            }
            .sorted { $0.peak > $1.peak }
        let value: Double
        if peaks.count >= 2 {
            value = peaks[1].peak
        } else if let only = peaks.first, only.strap {
            value = only.peak
        } else {
            return nil
        }
        return min(value, HeartRateZones.estimated(age: age).max + 22)
    }

    /// PZ-13's fallback: with 30% or more of the last 10 runs with heart rate failing the gate, the coach works
    /// from pace and effort. Returns whether heart rate may coach, and whether this run tipped it over.
    static func fallback(at run: LoggedRun, runs: [LoggedRun]) -> (coaching: Bool, justSwitched: Bool) {
        let withHeartRate = runs
            .filter { $0.start <= run.start && $0.heartRate.map { $0.useForCoaching && $0.source != .earbuds } == true }
            .sorted { $0.start < $1.start }
        func failing(_ list: ArraySlice<LoggedRun>) -> Bool {
            guard list.count >= 3 else { return false }
            let failed = list.filter { run in run.heartRate.map { badge($0) } != .usedForCoaching }.count
            return Double(failed) >= 0.3 * Double(list.count)
        }
        let now = failing(withHeartRate.suffix(10))
        let before = failing(withHeartRate.dropLast().suffix(10))
        return (!now, now && !before)
    }

    /// The start of the first run after the latest break of 14 days or more: heart-rate baselines start again
    /// there (PZ-13). Nil without such a break.
    static func restart(_ runs: [LoggedRun]) -> Date? {
        let sessions = LoadMetrics.sessions(from: runs)
        var restart: Date?
        for (previous, next) in zip(sessions, sessions.dropFirst()) where next.start.timeIntervalSince(previous.end) >= 14 * 86_400 {
            restart = next.start
        }
        return restart
    }

    /// After 14 days or more off, heart rate settles for 2 weeks and the coach goes by effort (PZ-13).
    static func settlingAfterBreak(_ run: LoggedRun, runs: [LoggedRun]) -> Bool {
        guard let restart = restart(runs.filter { $0.start < run.start } + [run]) else { return false }
        return run.start.timeIntervalSince(restart) < 14 * 86_400
    }

    /// Threshold heart rate: the mean decision-grade HR after minute 10 of the newest race or all-out run of
    /// 40-70 min that isn't a "conditions" run (heat, hills, altitude, after leg strength, PZ-7).
    static func thresholdHeartRate(runs: [LoggedRun], state: CoachState, calendar: Calendar) -> Double? {
        runs
            .filter { isAllOut($0) && (40 * 60 ... 70 * 60).contains($0.movingSeconds) && !RunAnalysis.isConditionsRun($0, state: state, calendar: calendar) }
            .sorted { $0.start > $1.start }
            .lazy
            .compactMap { run -> Double? in
                guard let heartRate = run.heartRate, badge(heartRate) == .usedForCoaching else { return nil }
                return heartRate.fromMinute10
            }
            .first
    }

    /// The zones a run's review reads: the app's entry point with the settings the run was recorded under, from
    /// the runs before it.
    static func zones(before run: LoggedRun, runs: [LoggedRun], state: CoachState, calendar: Calendar) -> HeartRateZones {
        let heartRate = run.heartRate
        let settings = HeartRateSettings(device: heartRate?.source ?? .off, useForCoaching: heartRate?.useForCoaching ?? false, labMax: heartRate?.labMax)
        return RunHeartRate.zones(age: state.assessment.age, settings: settings, runs: runs.filter { $0.start < run.start }, state: state, calendar: calendar)
    }

    // MARK: Easy runs (PZ-12, FB-4c)

    /// PZ-12's personal easy ceiling: once 3 or more decision-grade easy runs rated 3 or less with the talk test
    /// passed exist, the mean HR of the latest of them, up to 5. Like the other baselines it keeps to one device
    /// and starts again after 14 days or more off (PZ-13).
    static func personalEasyCeiling(runs: [LoggedRun], device: HeartRateDevice, state: CoachState) -> Double? {
        let restart = restart(runs) ?? .distantPast
        let means = runs
            .filter { $0.start >= restart && $0.heartRate?.source == device && RunAnalysis.isEasyRun($0, state: state) && ($0.rpe ?? 99) <= 3 && $0.checkIn?.talkTest == true }
            .sorted { $0.start > $1.start }
            .compactMap { decisionGradeMean($0) }
            .prefix(5)
        guard means.count >= 3 else { return nil }
        return (means.reduce(0, +) / Double(means.count)).rounded()
    }

    // MARK: Decoupling (FB-4k)

    /// The drop in speed per heartbeat from the first half to the second, or nil when the run doesn't qualify:
    /// decision-grade, steady, 45 min or more, flat, and not warm.
    static func decoupling(_ run: LoggedRun, state: CoachState) -> Double? {
        guard run.movingSeconds >= 45 * 60, let heartRate = run.heartRate, badge(heartRate) == .usedForCoaching,
              let first = heartRate.firstHalf, let second = heartRate.secondHalf, first.mean > 0, second.mean > 0,
              !RunDataGate.isHilly(run), (RunAnalysis.heatTier(run, state: state) ?? 0) == 0,
              (run.temperature ?? 0) < 20 else { return nil }
        let before = first.speed / first.mean
        let after = second.speed / second.mean
        guard before > 0 else { return nil }
        return (before - after) / before
    }

    // MARK: Pace at heart rate (FB-4l)

    /// One easy run's minutes 5-10: pace and heart rate, when they qualify (DG, ≤5 m climb, not treadmill, not warm).
    static func easyWindow(_ run: LoggedRun, state: CoachState) -> (date: Date, speed: Double, heartRate: Double, device: HeartRateDevice)? {
        guard RunAnalysis.isEasyRun(run, state: state), run.source != .treadmill, (RunAnalysis.heatTier(run, state: state) ?? 0) == 0,
              let heartRate = run.heartRate, badge(heartRate) == .usedForCoaching,
              let window = heartRate.minutes5to10, window.speed > 0, window.mean > 0, (window.climbMeters ?? 0) <= 5 else { return nil }
        return (run.start, window.speed, window.mean, heartRate.source)
    }

    /// FB-4l both ways, from the last 4 qualifying easy runs on the same device against the 2-week and 8-week
    /// baselines, each run's heart rate moved to a reference pace along the runner's own HR-pace line.
    /// Baselines start again after 14 or more days off (PZ-13).
    static func paceAtHeartRate(after run: LoggedRun, runs: [LoggedRun], state: CoachState, calendar: Calendar) -> (higher: Bool, lower: Bool) {
        guard let current = easyWindow(run, state: state) else { return (false, false) }
        let device = current.device
        var windows = runs
            .filter { $0.start <= run.start }
            .compactMap { easyWindow($0, state: state) }
            .filter { $0.device == device }
            .sorted { $0.date < $1.date }
        // A break of 14 days or more resets the baselines.
        if let restart = restart(runs.filter { $0.start <= run.start }) { windows = windows.filter { $0.date >= restart } }
        guard windows.count >= 7 else { return (false, false) }
        let recent = Array(windows.suffix(4))
        let earlier = windows.dropLast(4)
        let eightWeeksAgo = run.start.addingTimeInterval(-56 * 86_400)
        let twoWeeksAgo = run.start.addingTimeInterval(-14 * 86_400)
        let eight = earlier.filter { $0.date >= eightWeeksAgo }
        let two = earlier.filter { $0.date >= twoWeeksAgo }
        guard eight.count >= 3 else { return (false, false) }

        // The runner's HR-speed line over the 8 weeks, and a fixed reference speed at its median.
        let line = Array(eight) + recent
        let speeds = line.map(\.speed)
        let meanSpeed = speeds.reduce(0, +) / Double(speeds.count)
        let meanHR = line.map(\.heartRate).reduce(0, +) / Double(line.count)
        let spread = speeds.reduce(0) { $0 + ($1 - meanSpeed) * ($1 - meanSpeed) }
        let slope = spread > 1e-9 && (speeds.max()! - speeds.min()!) / meanSpeed >= 0.03
            ? max(0, line.reduce(0) { $0 + ($1.speed - meanSpeed) * ($1.heartRate - meanHR) } / spread) : 0
        let reference = eight.map(\.speed).sorted()[eight.count / 2]
        func adjusted(_ window: (date: Date, speed: Double, heartRate: Double, device: HeartRateDevice)) -> Double {
            window.heartRate + slope * (reference - window.speed)
        }
        let recentMean = recent.map(adjusted).reduce(0, +) / Double(recent.count)
        let eightMean = eight.map(adjusted).reduce(0, +) / Double(eight.count)
        let margin: Double = device == .chestStrap ? 3 : 5
        var higher = recentMean >= eightMean + margin
        if two.count >= 2 {
            let twoMean = two.map(adjusted).reduce(0, +) / Double(two.count)
            higher = higher && recentMean >= twoMean + margin
        } else {
            higher = false
        }
        let lower = recentMean <= eightMean * 0.97
        return (higher, lower)
    }

    // MARK: Resting heart rate (PZ-13)

    /// At least 6% above the 30-day mean, on 2 days running.
    static let restingRise = 1.06
    static let restingNote = "Your resting heart rate has been above your usual for two days. Feeling run down? An easy day may help."

    /// PZ-13's resting-HR flag on `day`: the settled values of the 2 days before it, from one device, each at least
    /// 6% above that device's mean over the 30 days before it (7 values or more). The device is the one with the most
    /// values in those 30 days. Only with "Use heart rate for coaching" On (IN-17).
    static func restingRaised(_ readings: [RestingHeartRate], settings: HeartRateSettings, on day: Date, calendar: Calendar) -> Bool {
        guard settings.canCoach else { return false }
        let today = calendar.startOfDay(for: day)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let dayBefore = calendar.date(byAdding: .day, value: -2, to: today),
              let monthAgo = calendar.date(byAdding: .day, value: -30, to: today) else { return false }
        let recent = settledValues(readings.filter { $0.date >= monthAgo && $0.date < today }, calendar: calendar)
        let counts = Dictionary(grouping: recent, by: \.device).mapValues(\.count)
        guard let device = counts.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key > $1.key) })?.key else { return false }
        let values = settledValues(readings.filter { $0.device == device }, calendar: calendar)
        return [yesterday, dayBefore].allSatisfy { day in
            guard let value = values.first(where: { calendar.isDate($0.date, inSameDayAs: day) }),
                  let start = calendar.date(byAdding: .day, value: -30, to: day) else { return false }
            let baseline = values.filter { $0.date >= start && $0.date < day }
            guard baseline.count >= 7 else { return false }
            let mean = baseline.map(\.bpm).reduce(0, +) / Double(baseline.count)
            return value.bpm >= restingRise * mean - 1e-9
        }
    }

    /// Each device's last value of each day.
    static func settledValues(_ readings: [RestingHeartRate], calendar: Calendar) -> [RestingHeartRate] {
        let days = Dictionary(grouping: readings) { "\($0.device)|\(calendar.startOfDay(for: $0.date).timeIntervalSinceReferenceDate)" }
        return days.values.compactMap { $0.max { $0.date < $1.date } }.sorted { $0.date < $1.date }
    }

    // MARK: Threshold and VO2max work (PZ-12)

    /// PZ-12's reading of a threshold or VO2max session's decision-grade work: below the band, over its top for
    /// most of the work, or neither. Nil when the session has no decision-grade work.
    enum WorkSignal: Hashable {
        case belowBand
        case overBand
        case underNinetyPercent
        case confirmsDose
    }

    static func workSignal(_ run: LoggedRun, session: PlannedSession, runs: [LoggedRun], state: CoachState, calendar: Calendar) -> WorkSignal? {
        guard let type = session.dose?.type, !RunAnalysis.isConditionsRun(run, state: state, calendar: calendar) else { return nil }
        let graded = decisionGradeSteps(run)
        guard !graded.isEmpty else { return nil }
        let zones = zones(before: run, runs: runs, state: state, calendar: calendar)
        let means = graded.values.compactMap(\.mean)
        switch type {
        case .threshold:
            guard !means.isEmpty else { return nil }
            let band = zones.thresholdBand
            let mean = means.reduce(0, +) / Double(means.count)
            let over = means.filter { $0 > band.upperBound }.count
            if over * 2 > means.count { return .overBand }
            if mean < band.lowerBound { return .belowBand }
            return nil
        case .vo2max:
            guard zones.maxObserved, (run.steps ?? []).filter(\.isWork).allSatisfy({ $0.seconds >= 240 }) else { return nil }
            let peaks = graded.values.compactMap(\.lastMinutePeak)
            guard !peaks.isEmpty else { return nil }
            let line = zones.max * 0.90
            if peaks.allSatisfy({ $0 < line }) { return .underNinetyPercent }
            if peaks.filter({ $0 >= line }).count * 2 > peaks.count { return .confirmsDose }
            return nil
        case .shortReps, .hills, .racePace:
            return nil
        }
    }
}
