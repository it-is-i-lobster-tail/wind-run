//
//  CoachBasics.swift
//  Wind Run
//

import Foundation

/// What the coach is building toward.
enum CoachGoal: String, Codable, CaseIterable {
    /// Grow how far the runner can go at an easy effort (Flavor 1).
    case buildDistance
    /// Get faster with regular quality sessions in blocks (Flavor 2).
    case speedWork
    /// Be ready for a race of a given distance on a given date (Flavor 3).
    case event

    var name: String {
        switch self {
        case .buildDistance: "Build distance"
        case .speedWork: "Speed work"
        case .event: "Train for an event"
        }
    }

    var summary: String {
        switch self {
        case .buildDistance: "Add a little more each week, with easy weeks to recover."
        case .speedWork: "Regular intervals and tempo runs to lift your pace."
        case .event: "A plan that peaks on race day, from 5K to the marathon."
        }
    }

    var systemImage: String {
        switch self {
        case .buildDistance: "chart.line.uptrend.xyaxis"
        case .speedWork: "hare"
        case .event: "flag.checkered"
        }
    }

    /// The distances each flavor offers (IN-1): no marathon time goals in Speed Work, no mile races.
    var distances: [RaceDistance] {
        switch self {
        case .buildDistance: [.mile, .fiveK, .tenK, .halfMarathon, .marathon]
        case .speedWork: [.mile, .fiveK, .tenK, .halfMarathon]
        case .event: [.fiveK, .tenK, .halfMarathon, .marathon]
        }
    }
}

/// Goal and race distances.
enum RaceDistance: String, Codable, CaseIterable, Comparable {
    case mile
    case fiveK
    case tenK
    case halfMarathon
    case marathon

    var meters: Double {
        switch self {
        case .mile: 1_609.344
        case .fiveK: 5_000
        case .tenK: 10_000
        case .halfMarathon: 21_097.5
        case .marathon: 42_195
        }
    }

    var name: String {
        switch self {
        case .mile: "1 mile"
        case .fiveK: "5K"
        case .tenK: "10K"
        case .halfMarathon: "Half marathon"
        case .marathon: "Marathon"
        }
    }

    /// For sentences: "your first half", "a 10K".
    var shortName: String {
        switch self {
        case .mile: "mile"
        case .fiveK: "5K"
        case .tenK: "10K"
        case .halfMarathon: "half"
        case .marathon: "marathon"
        }
    }

    /// Up to 10K, the k, ranges and early-window rules of the short races apply.
    var isUpToTenK: Bool { self <= .tenK }

    var isHalfOrLonger: Bool { self >= .halfMarathon }

    /// Taper length before the race (EV-1, EV-6).
    var taperDays: Int {
        switch self {
        case .mile, .fiveK, .tenK: 7
        case .halfMarathon: 14
        case .marathon: 21
        }
    }

    /// The next shorter distance, for "the shorter race on the same day".
    var shorter: RaceDistance? {
        switch self {
        case .mile: nil
        case .fiveK: .mile
        case .tenK: .fiveK
        case .halfMarathon: .tenK
        case .marathon: .halfMarathon
        }
    }

    var longer: RaceDistance? {
        switch self {
        case .mile: .fiveK
        case .fiveK: .tenK
        case .tenK: .halfMarathon
        case .halfMarathon: .marathon
        case .marathon: nil
        }
    }

    private var order: Int {
        switch self {
        case .mile: 0
        case .fiveK: 1
        case .tenK: 2
        case .halfMarathon: 3
        case .marathon: 4
        }
    }

    static func < (lhs: RaceDistance, rhs: RaceDistance) -> Bool { lhs.order < rhs.order }
}

/// How fast the plan builds (CL-1). A level only sets rates inside the hard limits (CL-5).
enum CommitmentLevel: Int, Codable, CaseIterable, Comparable {
    case gentle
    case steady
    case ambitious

    var name: String {
        switch self {
        case .gentle: "Gentle"
        case .steady: "Steady"
        case .ambitious: "Ambitious"
        }
    }

    /// Volume added in each loading (N or H) week.
    var loadingRate: Double {
        switch self {
        case .gentle: 0.05
        case .steady: 0.075
        case .ambitious: 0.10
        }
    }

    /// The picker's description (CL-1). With a Reduced or Low recovery tier Gentle steps back every 3rd week.
    func summary(stepBackEveryThird: Bool = false) -> String {
        switch self {
        case .gentle:
            stepBackEveryThird
                ? "Small steps: about 5% more each building week, a longer long run every other week, and a lighter week every 3rd week."
                : "Small steps: about 5% more each building week, a longer long run every other week, and a lighter week every 4th week."
        case .steady: "About 7.5% more each building week, and a lighter week every 3rd week."
        case .ambitious: "About 10% more each building week, and a lighter week every 4th week."
        }
    }

    static let pickerFootnote = "Every level stays inside the same safety limits. The level only changes how quickly you move through them."

    /// One level lower, never below Gentle.
    var lower: CommitmentLevel { CommitmentLevel(rawValue: rawValue - 1) ?? .gentle }

    var higher: CommitmentLevel? { CommitmentLevel(rawValue: rawValue + 1) }

    static func < (lhs: CommitmentLevel, rhs: CommitmentLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A week's place in the level's cycle (CL-1): N adds a new longest run, H holds the long run, S steps back.
enum CycleWeek: String, Codable, CaseIterable {
    case newLongest
    case heldLongRun
    case stepBack

    var letter: String {
        switch self {
        case .newLongest: "N"
        case .heldLongRun: "H"
        case .stepBack: "S"
        }
    }

    var isLoading: Bool { self != .stepBack }

    /// The cycle a runner gets (CL-1, CL-2, RB-3, the 2-week hold).
    /// - Parameters:
    ///   - stepBackEveryThird: a Reduced or Low recovery tier puts S every 3rd week.
    ///   - twoWeekHold: the injury window and 65+ ramps follow every N week with an H week.
    static func cycle(for level: CommitmentLevel, stepBackEveryThird: Bool, twoWeekHold: Bool) -> [CycleWeek] {
        if stepBackEveryThird {
            return level == .gentle || twoWeekHold ? [.newLongest, .heldLongRun, .stepBack] : [.newLongest, .newLongest, .stepBack]
        }
        if twoWeekHold {
            return [.newLongest, .heldLongRun, .newLongest, .stepBack]
        }
        switch level {
        case .gentle: return [.newLongest, .heldLongRun, .newLongest, .stepBack]
        case .steady: return [.newLongest, .newLongest, .stepBack]
        case .ambitious: return [.newLongest, .newLongest, .newLongest, .stepBack]
        }
    }
}

/// The runner's stage (TI-1), from the lowest tier they fit.
enum RunnerTier: Int, Codable, CaseIterable, Comparable {
    case starter
    case novice
    case regular
    case experienced

    var name: String {
        switch self {
        case .starter: "Starter"
        case .novice: "Novice"
        case .regular: "Regular"
        case .experienced: "Experienced"
        }
    }

    /// Planned runs a week, at most (HL-9), before the other caps.
    var runsCap: Int {
        switch self {
        case .starter: 3
        case .novice: 4
        case .regular: 4
        case .experienced: 5
        }
    }

    /// Hard units a week (RB-4); the Low recovery tier takes one less, never below 2.
    func hardUnitBudget(recovery: RecoveryTier) -> Int {
        let units: Int
        switch self {
        case .starter: units = 2
        case .novice: units = 3
        case .regular: units = 4
        case .experienced: units = 5
        }
        return recovery == .low ? max(2, units - 1) : units
    }

    static func < (lhs: RunnerTier, rhs: RunnerTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// How much recovery other training and work leave for running (RB-2).
enum RecoveryTier: Int, Codable, CaseIterable, Comparable {
    case normal
    case reduced
    case low

    var name: String {
        switch self {
        case .normal: "Normal"
        case .reduced: "Reduced"
        case .low: "Low"
        }
    }

    /// Risk points the tier adds (TI-4).
    var riskPoints: Int { rawValue }

    /// Reduced and Low put a step-back every 3rd week (CL-2, RB-3).
    var stepsBackEveryThird: Bool { self != .normal }

    /// The highest level the tier allows (RB-3).
    var levelCeiling: CommitmentLevel {
        switch self {
        case .normal: .ambitious
        case .reduced: .steady
        case .low: .gentle
        }
    }

    static func < (lhs: RecoveryTier, rhs: RecoveryTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A day of the week, numbered like `Calendar`'s weekday component (Sunday is 1).
enum Weekday: Int, Codable, CaseIterable, Comparable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var name: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }

    var shortName: String { String(name.prefix(3)) }

    var isWeekend: Bool { self == .saturday || self == .sunday }

    /// The weekday `days` after this one, wrapping around the week.
    func adding(_ days: Int) -> Weekday {
        let index = ((rawValue - 1 + days) % 7 + 7) % 7
        return Weekday(rawValue: index + 1) ?? self
    }

    init(of date: Date, calendar: Calendar) {
        self = Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .sunday
    }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The five effort labels every session and logged bout carries (PZ-1). Never shown as zones.
enum Effort: Int, Codable, CaseIterable, Comparable {
    case easy
    case steady
    case threshold
    case interval
    case race

    var name: String {
        switch self {
        case .easy: "Easy"
        case .steady: "Steady"
        case .threshold: "Threshold"
        case .interval: "Interval"
        case .race: "Race"
        }
    }

    var rpeRange: ClosedRange<Int> {
        switch self {
        case .easy: 2...3
        case .steady: 4...5
        case .threshold: 5...6
        case .interval: 7...8
        case .race: 9...10
        }
    }

    /// The RPE that marks a run as too hard for its label (PZ-1), or nil for races and tests.
    var tooHardRPE: Int? {
        switch self {
        case .easy: 4
        case .steady, .threshold: 7
        case .interval: 9
        case .race: nil
        }
    }

    /// The RPE a session is judged against (FB-4g): the "too hard" line minus 2.
    var targetRPE: Int {
        switch self {
        case .easy: 3
        case .steady, .threshold: 5
        case .interval: 7
        case .race: 9
        }
    }

    var talkTest: String {
        switch self {
        case .easy: "full sentences"
        case .steady: "short sentences"
        case .threshold: "short phrases"
        case .interval: "a few words"
        case .race: "none"
        }
    }

    /// PZ-1a: a bout with no pace target is labelled from RPE alone.
    init(rpe: Int) {
        switch rpe {
        case ...3: self = .easy
        case 4...5: self = .steady
        case 6: self = .threshold
        case 7...8: self = .interval
        default: self = .race
        }
    }

    /// Threshold or faster, for the intensity share (HL-8).
    var isHard: Bool { self >= .threshold }

    static func < (lhs: Effort, rhs: Effort) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What weekly volume is counted in (Terms): distance, or running minutes for run-walk plans and runs without GPS.
enum VolumeUnit: String, Codable {
    case distance
    case time

    /// The part of a load this unit counts: meters or seconds.
    func amount(of load: Load) -> Double {
        switch self {
        case .distance: load.meters
        case .time: load.seconds
        }
    }
}

/// A distance and a time together. Caps are checked on both and the stricter wins (Terms, HL-1).
struct Load: Codable, Hashable {
    var meters: Double
    var seconds: Double

    static let zero = Load(meters: 0, seconds: 0)

    init(meters: Double, seconds: Double) {
        self.meters = meters
        self.seconds = seconds
    }

    /// A load from one amount in `unit`, with the other side converted at `pace` (seconds per km).
    /// Without a pace the other side stays 0, which reads as "unknown" to the caps.
    init(_ amount: Double, in unit: VolumeUnit, pace: Double?) {
        switch unit {
        case .distance:
            meters = amount
            seconds = pace.map { amount / 1_000 * $0 } ?? 0
        case .time:
            seconds = amount
            meters = pace.map { $0 > 0 ? amount / $0 * 1_000 : 0 } ?? 0
        }
    }

    func amount(in unit: VolumeUnit) -> Double { unit.amount(of: self) }

    func scaled(by factor: Double) -> Load {
        Load(meters: meters * factor, seconds: seconds * factor)
    }

    /// The smaller of two loads on each side, where a 0 side counts as unknown.
    func capped(at cap: Load) -> Load {
        Load(
            meters: cap.meters > 0 ? min(meters, cap.meters) : meters,
            seconds: cap.seconds > 0 ? min(seconds, cap.seconds) : seconds
        )
    }

    static func + (lhs: Load, rhs: Load) -> Load {
        Load(meters: lhs.meters + rhs.meters, seconds: lhs.seconds + rhs.seconds)
    }

    static func - (lhs: Load, rhs: Load) -> Load {
        Load(meters: lhs.meters - rhs.meters, seconds: lhs.seconds - rhs.seconds)
    }
}

/// A pace range in seconds per kilometer: `fast` is the smaller number.
struct PaceBand: Codable, Hashable {
    var fast: Double
    var slow: Double

    init(fast: Double, slow: Double) {
        self.fast = min(fast, slow)
        self.slow = max(fast, slow)
    }

    /// "X% slower": per-km time × (1 + X/100), on both edges.
    func slower(by fraction: Double) -> PaceBand {
        PaceBand(fast: fast * (1 + fraction), slow: slow * (1 + fraction))
    }

    /// Both edges moved by a number of seconds per km (FB-4c: 15 s/km slower).
    func shifted(by seconds: Double) -> PaceBand {
        PaceBand(fast: fast + seconds, slow: slow + seconds)
    }

    func contains(_ pace: Double) -> Bool { pace >= fast && pace <= slow }

    var middle: Double { (fast + slow) / 2 }
}

extension Double {
    /// Rounded down to a multiple of `step` (for "rounded down to 0.1 km").
    func floored(toMultipleOf step: Double) -> Double {
        guard step > 0 else { return self }
        return (self / step + 1e-9).rounded(.down) * step
    }

    func rounded(toMultipleOf step: Double) -> Double {
        guard step > 0 else { return self }
        return (self / step).rounded() * step
    }

    func ceiled(toMultipleOf step: Double) -> Double {
        guard step > 0 else { return self }
        return (self / step - 1e-9).rounded(.up) * step
    }

    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// Fixed numbers the rules share.
enum CoachLimits {
    /// HL-1: a session is at most 10% longer than the 30-day longest.
    static let sessionGrowth = 1.10
    /// HL-2: a week is at most 20% above the biggest recent week.
    static let weekGrowth = 1.20
    /// HL-2: under 60 min a week, the cap is W4max + 10 min instead.
    static let smallWeekSeconds: Double = 60 * 60
    static let smallWeekAllowanceSeconds: Double = 10 * 60
    /// HL-5: the long-run ceiling.
    static let longRunCeiling = Load(meters: 35_000, seconds: 210 * 60)
    /// HL-6: every other run is at least 20 minutes.
    static let minimumRunSeconds: Double = 20 * 60
    /// HL-6: other runs are at most 2/3 of the long run.
    static let otherRunShare = 2.0 / 3.0
    /// HL-6: over 60% of the week, the long run holds while the week is below its ceiling.
    static let longRunWeekShare = 0.60
    /// HL-4: loading weeks in a row.
    static let loadingWeeksInRow = 3
    /// CL-2: a step-back cuts volume 25% and sets the long run at 70% of P-L30.
    static let stepBackVolume = 0.75
    static let stepBackLongRun = 0.70
    /// HL-11: early-window session cap.
    static let earlyWindowRunSeconds: Double = 30 * 60
    static let earlyWindowRunWalkSeconds: Double = 45 * 60
    /// TI-3: the early window ends after 12 weeks and 200 km of regular running.
    static let earlyWindowWeeks = 12.0
    static let earlyWindowMeters = 200_000.0
    /// TI-3: months to weeks.
    static let weeksPerMonth = 4.3
    /// HL-14: above 64 km a week, only levels already sustained for 4 weeks.
    static let highVolumeMeters = 64_000.0
    /// Runs less than 15 minutes apart merge into one session (Terms, FB-2).
    static let sessionMergeGap: TimeInterval = 15 * 60
    /// A long run over 90 minutes is a hard day (Terms).
    static let hardLongRunSeconds: Double = 90 * 60
}
