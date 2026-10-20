//
//  CoachIntake.swift
//  Wind Run
//

import Foundation

/// The goal the runner picks (IN-1).
struct GoalChoice: Codable, Hashable {
    var flavor: CoachGoal
    var distance: RaceDistance
    /// A time goal in seconds (Speed Work and events). Nil means no time goal.
    var targetSeconds: Double?
    /// Speed Work's "strong first time": the central forecast with the cautious k (SW-1a).
    var strongFirstTime: Bool = false
    /// Race day, for events.
    var eventDate: Date?
    /// The race cut-off in seconds, if the race has one (EF-3).
    var cutoffSeconds: Double?
    /// Build Distance's 5K and 10K run-walk rungs (BD-1d).
    var runWalk: Bool = false

    init(
        flavor: CoachGoal,
        distance: RaceDistance,
        targetSeconds: Double? = nil,
        strongFirstTime: Bool = false,
        eventDate: Date? = nil,
        cutoffSeconds: Double? = nil,
        runWalk: Bool = false
    ) {
        self.flavor = flavor
        self.distance = distance
        self.targetSeconds = targetSeconds
        self.strongFirstTime = strongFirstTime
        self.eventDate = eventDate
        self.cutoffSeconds = cutoffSeconds
        self.runWalk = runWalk
    }

    var hasTimeGoal: Bool { targetSeconds != nil }
}

/// "Have you finished this distance?" (IN-1)
enum FinishedDistance: String, Codable, CaseIterable {
    case yesRecently
    case yesLongerAgo
    case no

    var name: String {
        switch self {
        case .yesRecently: "Yes, in the last 18 months"
        case .yesLongerAgo: "Yes, longer ago"
        case .no: "No"
        }
    }
}

/// "Longest you can run without stopping?" after "not yet" (IN-4).
enum NonStopBand: String, Codable, CaseIterable {
    case underOneMinute
    case oneToFive
    case fiveToFifteen
    case fifteenToTwentyNine

    var name: String {
        switch self {
        case .underOneMinute: "Under 1 min"
        case .oneToFive: "1-5 min"
        case .fiveToFifteen: "5-15 min"
        case .fifteenToTwentyNine: "15-29 min"
        }
    }

    /// The band's low end in minutes, the conservative reading.
    var lowMinutes: Double {
        switch self {
        case .underOneMinute: 0
        case .oneToFive: 1
        case .fiveToFifteen: 5
        case .fifteenToTwentyNine: 15
        }
    }
}

/// "Day to day, how easily do you walk and climb stairs?" (IN-4)
enum DailyFunction: String, Codable, CaseIterable {
    case good
    case fair
    case poor

    var name: String { rawValue.capitalized }
}

/// "How long have you run at least twice a week?" (IN-5)
enum RunningHistory: String, Codable, CaseIterable, Comparable {
    case notYet
    case underThreeMonths
    case threeToTwelveMonths
    case oneToTwoYears
    case overTwoYears

    var name: String {
        switch self {
        case .notYet: "Not yet"
        case .underThreeMonths: "Under 3 months"
        case .threeToTwelveMonths: "3-12 months"
        case .oneToTwoYears: "1-2 years"
        case .overTwoYears: "Over 2 years"
        }
    }

    /// The band's low end in months, used when no months answer is given (Intake).
    var lowMonths: Double {
        switch self {
        case .notYet: 0
        case .underThreeMonths: 0
        case .threeToTwelveMonths: 3
        case .oneToTwoYears: 12
        case .overTwoYears: 24
        }
    }

    /// Under 12 months asks "About how many months?"
    var asksMonths: Bool { self == .underThreeMonths || self == .threeToTwelveMonths }

    private var order: Int {
        switch self {
        case .notYet: 0
        case .underThreeMonths: 1
        case .threeToTwelveMonths: 2
        case .oneToTwoYears: 3
        case .overTwoYears: 4
        }
    }

    static func < (lhs: RunningHistory, rhs: RunningHistory) -> Bool { lhs.order < rhs.order }
}

/// A distance or a time: every distance answer also accepts minutes (Intake).
enum RunAmount: Codable, Hashable {
    case distance(meters: Double)
    case time(seconds: Double)

    var meters: Double? {
        if case .distance(let meters) = self { return meters }
        return nil
    }

    var seconds: Double? {
        if case .time(let seconds) = self { return seconds }
        return nil
    }

    /// The amount in `unit`, converting at `pace` (seconds per km) when the units differ.
    func value(in unit: VolumeUnit, pace: Double?) -> Double? {
        switch (self, unit) {
        case (.distance(let meters), .distance): meters
        case (.time(let seconds), .time): seconds
        case (.distance(let meters), .time): pace.map { meters / 1_000 * $0 }
        case (.time(let seconds), .distance): pace.flatMap { $0 > 0 ? seconds / $0 * 1_000 : nil }
        }
    }

    var unit: VolumeUnit {
        switch self {
        case .distance: .distance
        case .time: .time
        }
    }
}

/// "In the last 4 weeks:" (IN-6), and the same answers for the weeks before a break.
struct RecentRunning: Codable, Hashable {
    var runsPerWeek: Int
    /// The low end of the weekly range is V0 (TI-5).
    var weeklyLow: RunAmount
    var weeklyHigh: RunAmount?
    /// Nil is "not sure": P-L30 starts at 0.5 × V0 (IN-21).
    var longest: RunAmount?
    /// Intervals, tempo, hills or races a week.
    var hardSessionsPerWeek: Int = 0
    /// Asked at 5 runs a week: "For 3 months or more?"
    var fiveRunsForThreeMonths: Bool?

    init(
        runsPerWeek: Int,
        weeklyLow: RunAmount,
        weeklyHigh: RunAmount? = nil,
        longest: RunAmount? = nil,
        hardSessionsPerWeek: Int = 0,
        fiveRunsForThreeMonths: Bool? = nil
    ) {
        self.runsPerWeek = runsPerWeek
        self.weeklyLow = weeklyLow
        self.weeklyHigh = weeklyHigh
        self.longest = longest
        self.hardSessionsPerWeek = hardSessionsPerWeek
        self.fiveRunsForThreeMonths = fiveRunsForThreeMonths
    }
}

/// Where a race or test result came from (PZ-2).
enum ResultSource: String, Codable, CaseIterable {
    /// A race, reported at intake or logged.
    case race
    /// An all-out effort the runner reports (IN-7) or marks on a run (AD-1).
    case allOutEffort
    /// An all-out app test (PZ-3).
    case appTest
    /// A controlled test capped at RPE 8: counts, marked low precision (PZ-3).
    case controlledTest
    /// A goal attempt or solo time trial (SW-8).
    case timeTrial
}

/// Course difficulty for a result (IN-7, PZ-2): a very hilly course is not used.
enum CourseProfile: String, Codable, CaseIterable {
    case flat
    case hilly
    case veryHilly

    var name: String {
        switch self {
        case .flat: "Flat"
        case .hilly: "Hilly"
        case .veryHilly: "Very hilly"
        }
    }
}

/// A race or all-out result: a possible pace anchor (PZ-2).
struct RaceResult: Codable, Hashable, Identifiable {
    var id: UUID
    var date: Date
    var meters: Double
    var seconds: Double
    var source: ResultSource
    /// Official chip time, or the runner's watch.
    var official: Bool
    var course: CourseProfile
    var treadmill: Bool
    /// Weekly distance in the month before the result, for PZ-2's volume adjustment.
    var weeklyMetersBefore: Double?

    init(
        id: UUID = UUID(),
        date: Date,
        meters: Double,
        seconds: Double,
        source: ResultSource = .race,
        official: Bool = true,
        course: CourseProfile = .flat,
        treadmill: Bool = false,
        weeklyMetersBefore: Double? = nil
    ) {
        self.id = id
        self.date = date
        self.meters = meters
        self.seconds = seconds
        self.source = source
        self.official = official
        self.course = course
        self.treadmill = treadmill
        self.weeklyMetersBefore = weeklyMetersBefore
    }

    /// Seconds per kilometer.
    var pace: Double { meters > 0 ? seconds / meters * 1_000 : 0 }
}

/// The chips on "What other training do you do?" (IN-10).
enum ActivityKind: String, Codable, CaseIterable {
    case legStrength
    case upperBody
    case hiit
    case cycling
    case swimming
    case yoga
    case teamSport
    case other

    var name: String {
        switch self {
        case .legStrength: "Leg strength"
        case .upperBody: "Upper body"
        case .hiit: "HIIT or class"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .yoga: "Yoga"
        case .teamSport: "Team or court sport"
        case .other: "Other"
        }
    }

    /// The effort slider's starting value, at each chip's usual RB-1 class (IN-10).
    var defaultEffort: Int {
        switch self {
        case .legStrength, .hiit, .teamSport: 6
        case .cycling, .swimming, .other: 5
        case .yoga, .upperBody: 4
        }
    }

    var defaultWorksLegs: Bool {
        switch self {
        case .legStrength, .hiit, .cycling, .teamSport: true
        case .upperBody, .swimming, .yoga, .other: false
        }
    }
}

/// One kind of other training in the runner's routine (IN-10).
struct OtherActivity: Codable, Hashable, Identifiable {
    var id: UUID
    var kind: ActivityKind
    var sessionsPerWeek: Int
    var minutes: Double
    /// RPE 0-10.
    var effort: Int
    var worksLegs: Bool
    /// New or doubled in the last 8 weeks (RB-6).
    var newOrDoubled: Bool
    /// Leg strength only: "Heavy (8 reps or fewer)?"
    var heavy: Bool
    /// The days it falls on, when the runner gives them; the scheduler never moves these (RB-5).
    var days: Set<Weekday>

    init(
        id: UUID = UUID(),
        kind: ActivityKind,
        sessionsPerWeek: Int,
        minutes: Double,
        effort: Int? = nil,
        worksLegs: Bool? = nil,
        newOrDoubled: Bool = false,
        heavy: Bool = false,
        days: Set<Weekday> = []
    ) {
        self.id = id
        self.kind = kind
        self.sessionsPerWeek = sessionsPerWeek
        self.minutes = minutes
        self.effort = effort ?? kind.defaultEffort
        self.worksLegs = worksLegs ?? kind.defaultWorksLegs
        self.newOrDoubled = newOrDoubled
        self.heavy = heavy
        self.days = days
    }
}

/// "Why do you run?" (IN-19), used only for wording.
enum RunReason: String, Codable, CaseIterable {
    case health
    case fitness
    case friends
    case performance
}

/// The intake answers (IN-1 to IN-19). A skipped answer stays nil, never a guess (IN-21), so the
/// cautious branch is visible and can be asked again. Coach mode asks nothing about health.
struct CoachIntake: Codable, Hashable {
    // IN-1
    var goal: GoalChoice
    var finished: FinishedDistance?

    // IN-2, stored as the year the runner was born; adults only.
    var birthYear: Int?

    // IN-16 (optional)
    var heightCentimeters: Double?
    var weightKilograms: Double?

    // IN-19 (optional)
    var reasons: Set<RunReason> = []

    // IN-4
    /// "Can you run for 30 minutes without stopping?" Nil is skipped.
    var runs30Minutes: Bool?
    var longestNonStop: NonStopBand?
    var dailyFunction: DailyFunction?
    /// Asked under 1 min: "Can you walk briskly for 30 minutes?"
    var walksBriskly30: Bool?

    // IN-5
    var history: RunningHistory?
    /// "About how many months?" under 12 months.
    var monthsRunning: Double?
    /// A break of 4 weeks or more lately: how many weeks ago it began. Nil is no break.
    var breakBeganWeeksAgo: Double?
    var racedLastYear: Bool = false
    var sessionsLastYear: Bool = false
    var sessionsForAYearOrMore: Bool = false

    // IN-6
    var lastFourWeeks: RecentRunning?
    var beforeBreak: RecentRunning?

    // IN-7
    /// Usual easy pace in seconds per km. Nil is "not sure".
    var easyPace: Double?
    var race: RaceResult?

    // IN-10
    /// Nil is skipped, which counts as the F1 flag (IN-21); an empty list is "None".
    var otherTraining: [OtherActivity]?
    /// "Physical job or shift work?" Nil is skipped.
    var physicalWork: Bool?

    // IN-12
    var runDays: Set<Weekday> = []
    /// Longest time for a run on a weekday, and on a weekend, in seconds.
    var weekdayMaxSeconds: Double?
    var weekendMaxSeconds: Double?
    var longRunDay: Weekday?

    // IN-13
    var level: CommitmentLevel?

    /// Km or miles, picked once (Intake); every sentence the coach shows uses it.
    var distanceUnit: DistanceUnit = .kilometers

    var answeredAt: Date

    init(goal: GoalChoice, answeredAt: Date) {
        self.goal = goal
        self.answeredAt = answeredAt
    }

    /// The runner's age on a date, from the birth year.
    func age(on date: Date, calendar: Calendar) -> Int? {
        guard let birthYear else { return nil }
        return max(18, calendar.component(.year, from: date) - birthYear)
    }

    /// BMI from height and weight, when both are given.
    var bmi: Double? {
        guard let heightCentimeters, let weightKilograms, heightCentimeters > 0 else { return nil }
        let meters = heightCentimeters / 100
        return weightKilograms / (meters * meters)
    }

    /// The longest time the runner has for a run on a weekday.
    func maxSeconds(on day: Weekday) -> Double? {
        day.isWeekend ? weekendMaxSeconds : weekdayMaxSeconds
    }

    /// Required items still unanswered: age, goal and run days have no safe default (IN-21).
    var missingRequired: [String] {
        var missing: [String] = []
        if birthYear == nil { missing.append("age") }
        if runDays.isEmpty { missing.append("run days") }
        return missing
    }
}

extension DistanceUnit: Codable {}
