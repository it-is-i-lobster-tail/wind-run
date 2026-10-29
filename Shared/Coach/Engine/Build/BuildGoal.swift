//
//  BuildGoal.swift
//  Wind Run
//

import Foundation

/// The event a Build Distance plan works toward (Brendon, 2026-10-28): a distance on a date, with its climb.
enum GoalEvent: String, Codable, CaseIterable, Hashable {
    case fiveK
    case tenK
    case halfMarathon
    case marathon
    case fiftyK
    /// Any other distance, typed by the runner.
    case custom

    /// The event's distance in meters, or nil for a custom one.
    var meters: Double? {
        switch self {
        case .fiveK: 5_000
        case .tenK: 10_000
        case .halfMarathon: 21_097.5
        case .marathon: 42_195
        case .fiftyK: 50_000
        case .custom: nil
        }
    }

    var name: String {
        switch self {
        case .fiveK: "5K"
        case .tenK: "10K"
        case .halfMarathon: "Half"
        case .marathon: "Marathon"
        case .fiftyK: "50K"
        case .custom: "Custom"
        }
    }

    /// For sentences: "your marathon", "your 50K".
    var shortName: String {
        switch self {
        case .halfMarathon: "half"
        case .marathon: "marathon"
        case .custom: "event"
        default: name
        }
    }
}

/// What the plan builds to: the event, its date, and the peak week that gets the runner ready for it.
struct BuildGoal: Codable, Hashable {
    var event: GoalEvent
    /// The event's distance in meters.
    var meters: Double
    /// The event's climb in meters, 0 for a flat race.
    var climbMeters: Double
    /// The week the plan builds to. Preset from the event and changeable.
    var peakWeekMeters: Double
    var peakWeekClimbMeters: Double
    /// The event's day, at the start of the day. The last plan week ends on it.
    var date: Date

    init(event: GoalEvent, meters: Double? = nil, climbMeters: Double = 0, peakWeekMeters: Double? = nil, peakWeekClimbMeters: Double? = nil, date: Date) {
        let distance = meters ?? event.meters ?? BuildLimits.minimumPeakMeters
        self.event = event
        self.meters = distance
        self.climbMeters = max(0, climbMeters)
        self.peakWeekMeters = peakWeekMeters ?? Self.defaultPeak(forMeters: distance)
        self.peakWeekClimbMeters = peakWeekClimbMeters ?? Self.defaultPeakClimb(forClimb: climbMeters)
        self.date = date
    }

    /// The peak week for an event: 1.5 times its distance, and never under 16 km (10 mi).
    static func defaultPeak(forMeters meters: Double) -> Double {
        max(BuildLimits.minimumPeakMeters, meters * BuildLimits.peakMultiple)
    }

    /// The peak week's climb: 1.5 times the event's climb.
    static func defaultPeakClimb(forClimb climb: Double) -> Double {
        max(0, climb) * BuildLimits.peakMultiple
    }

    var hasClimb: Bool { peakWeekClimbMeters > 0 }
}

/// When the easy weeks fall: every Nth week, or the weeks the runner picks. The goal week is an easy week either way.
enum EasyWeekSchedule: Codable, Hashable {
    /// Every `n`th plan week, 3 to 6.
    case every(Int)
    /// Only the weeks the runner marked, by week number (1 is the first plan week).
    case chosen(Set<Int>)

    static let standard = EasyWeekSchedule.every(4)
    static let spacing = 3 ... 6

    var isAutomatic: Bool {
        if case .every = self { return true }
        return false
    }

    /// True when week `number` is an easy week by this schedule (the goal week aside).
    func isEasy(_ number: Int) -> Bool {
        switch self {
        case .every(let n): number > 0 && number % n.clamped(to: Self.spacing) == 0
        case .chosen(let weeks): weeks.contains(number)
        }
    }

    /// The schedule with week `number` turned into, or out of, an easy week. An automatic schedule becomes the
    /// runner's own picks, starting from the weeks it had before the goal week (`count`).
    func toggling(_ number: Int, through count: Int) -> EasyWeekSchedule {
        var weeks: Set<Int>
        switch self {
        case .every: weeks = Set((1 ..< max(2, count)).filter(isEasy))
        case .chosen(let chosen): weeks = chosen
        }
        if weeks.contains(number) { weeks.remove(number) } else { weeks.insert(number) }
        return .chosen(weeks)
    }
}

/// Everything setup asks, as the plan keeps it.
struct BuildSettings: Codable, Hashable {
    /// Weekly mileage and climb now, in meters: the last 4 weeks' average, changeable.
    var currentWeeklyMeters: Double
    var currentWeeklyClimbMeters: Double
    var goal: BuildGoal
    /// The days the runner runs. Only a way to split the week; the week's total is what counts.
    var runDays: [Weekday]
    var easyWeeks: EasyWeekSchedule

    init(currentWeeklyMeters: Double, currentWeeklyClimbMeters: Double = 0, goal: BuildGoal, runDays: [Weekday], easyWeeks: EasyWeekSchedule = .standard) {
        self.currentWeeklyMeters = max(0, currentWeeklyMeters)
        self.currentWeeklyClimbMeters = max(0, currentWeeklyClimbMeters)
        self.goal = goal
        self.runDays = Array(Set(runDays)).sorted()
        self.easyWeeks = easyWeeks
    }
}

/// The numbers the plan never goes past (Brendon, 2026-10-28), and the calls made where his rules are silent.
enum BuildLimits {
    /// Never more than 10% on the last building week.
    static let maxGrowth = 0.10
    /// The slow end of the timeline's estimate, and the least the plan adds while it's building.
    static let minGrowth = 0.05
    /// An easy week is 25% under the last building week (the recovery-week rule the coach always had).
    static let easyWeekShare = 0.75
    /// The peak week is 1.5 times the event, and never under 16 km (10 mi) for distance.
    static let peakMultiple = 1.5
    static let minimumPeakMeters = 16_093.44
    /// A plan never starts under 5 km (3 mi) a week, or under 10% of the peak's climb.
    static let floorMeters = 5_000.0
    static let climbFloorShare = 0.10
    /// A week counts as done at 90% of its mileage; under that the next week repeats it.
    static let doneShare = 0.90
    /// Two weeks in a row under half done starts the plan again from what was run lately.
    static let lowShare = 0.50
    /// The first plan week needs at least this many days left, or the plan starts the week after.
    static let firstWeekDays = 3
    /// No planned run is shorter than 2 km: a week with less left than that a run has fewer runs.
    static let shortestRunMeters = 2_000.0
}
