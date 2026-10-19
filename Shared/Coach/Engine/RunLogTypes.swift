//
//  RunLogTypes.swift
//  Wind Run
//

import Foundation

/// How a run was measured, which decides what the coach can read from it (FB-2).
enum RunSource: String, Codable, CaseIterable {
    /// GPS from the phone or watch.
    case gps
    /// Treadmill: pace from the belt or the runner's distance, compared only with treadmill runs.
    case treadmill
    /// Entered by hand, or recorded without GPS: volume in minutes, no pace analysis.
    case manual
    /// Written to Apple Health by another app.
    case otherApp
}

/// "Felt too easy / OK / hard / too hard" after a run (AD-1).
enum RunFeel: String, Codable, CaseIterable {
    case tooEasy
    case ok
    case hard
    case tooHard

    var name: String {
        switch self {
        case .tooEasy: "Too easy"
        case .ok: "OK"
        case .hard: "Hard"
        case .tooHard: "Too hard"
        }
    }
}

/// Why a run was cut short (AD-1). The same answers serve FB-3's "What happened?" check.
enum CutShortReason: String, Codable, CaseIterable {
    case tired
    case unwellInHeat
    case somethingHurt
    case feltIll
    case other

    var name: String {
        switch self {
        case .tired: "Tired"
        case .unwellInHeat: "Felt unwell in the heat"
        case .somethingHurt: "Something hurt"
        case .feltIll: "Felt ill"
        case .other: "Other"
        }
    }
}

/// FB-3's answers to "That run got tough. What happened?"
enum WhatHappened: String, Codable, CaseIterable {
    case tired
    case unwellInHeat
    case somethingHurt
    case feltIll
    case stoppedForOtherReason
    case dataProblem

    var name: String {
        switch self {
        case .tired: "Tired"
        case .unwellInHeat: "Felt unwell in the heat"
        case .somethingHurt: "Something hurt"
        case .feltIll: "Felt ill"
        case .stoppedForOtherReason: "Stopped for another reason"
        case .dataProblem: "Watch or GPS problem"
        }
    }

    init(_ reason: CutShortReason) {
        switch reason {
        case .tired: self = .tired
        case .unwellInHeat: self = .unwellInHeat
        case .somethingHurt: self = .somethingHurt
        case .feltIll: self = .feltIll
        case .other: self = .stoppedForOtherReason
        }
    }
}

/// The heat answer when there's no weather source (AD-16): cool T0, warm T1, hot T2, very hot T3.
enum HeatAnswer: String, Codable, CaseIterable, Comparable {
    case cool
    case warm
    case hot
    case veryHot

    var name: String {
        switch self {
        case .cool: "Cool"
        case .warm: "Warm"
        case .hot: "Hot"
        case .veryHot: "Very hot"
        }
    }

    /// The heat tier, 0-3.
    var tier: Int {
        switch self {
        case .cool: 0
        case .warm: 1
        case .hot: 2
        case .veryHot: 3
        }
    }

    static func < (lhs: HeatAnswer, rhs: HeatAnswer) -> Bool { lhs.tier < rhs.tier }
}

/// The per-run check-in (AD-1), about 30 minutes after the run. Every answer is skippable, and a
/// skipped answer stays nil (AD-17).
struct RunCheckIn: Codable, Hashable {
    var answeredAt: Date?
    /// CR-10, 0-10.
    var rpe: Int?
    /// "Could you talk in full sentences?" after easy runs.
    var talkTest: Bool?
    var feel: RunFeel?
    var cutShort: CutShortReason?
    var unplannedOrWithFriends: Bool = false
    var runWalk: Bool = false
    var treadmill: Bool = false
    var badData: Bool = false
    /// Only a run marked so can become an anchor (PZ-2) or raise HRmax (PZ-11).
    var raceOrAllOut: Bool = false
    /// FB-3's answer when the check was shown and answered.
    var whatHappened: WhatHappened?
    /// The heat answer given before the run, when there's no weather source (AD-16).
    var heat: HeatAnswer?
    /// Event-prep runs over 60 min: carbohydrate per hour and a gut score 0-3 (EV-5).
    var fuelGramsPerHour: Double?
    var gutScore: Int?

    init(answeredAt: Date? = nil, rpe: Int? = nil, talkTest: Bool? = nil, feel: RunFeel? = nil) {
        self.answeredAt = answeredAt
        self.rpe = rpe
        self.talkTest = talkTest
        self.feel = feel
    }

    /// The FB-3 answer, from the cut-short reason when the runner already gave one (one question per run).
    var effectiveWhatHappened: WhatHappened? {
        whatHappened ?? cutShort.map(WhatHappened.init)
    }
}

/// One GPS fix, mapped from the app's route samples.
struct TrackPoint: Codable, Hashable {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var altitude: Double?
    /// Meters; negative is invalid.
    var horizontalAccuracy: Double
    /// Meters per second; negative is unknown.
    var speed: Double?

    init(timestamp: Date, latitude: Double, longitude: Double, altitude: Double? = nil, horizontalAccuracy: Double, speed: Double? = nil) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.speed = speed
    }
}

/// One kilometer (or the last part) of a run.
struct Split: Codable, Hashable {
    var meters: Double
    var seconds: Double
    var climbMeters: Double

    var pace: Double { meters > 0 ? seconds / meters * 1_000 : 0 }
}

/// What the run's track says, after the data gate's measurements (FB-2).
struct TrackSummary: Codable, Hashable {
    var splits: [Split]
    /// Share of moving time with poor GPS: accuracy worse than 20 m, a gap or a jump.
    var poorGPSShare: Double
    /// Climb in each half of the run, for the 20 m rule.
    var climbFirstHalf: Double
    var climbSecondHalf: Double
    /// The longest stretch run without walking or stopping, for milestones (BD-1e).
    var longestNonStopSeconds: Double?
    var longestNonStopMeters: Double?
    /// Median altitude at the start, for the usual-altitude rule (PZ-9).
    var startAltitude: Double?

    init(
        splits: [Split] = [],
        poorGPSShare: Double = 0,
        climbFirstHalf: Double = 0,
        climbSecondHalf: Double = 0,
        longestNonStopSeconds: Double? = nil,
        longestNonStopMeters: Double? = nil,
        startAltitude: Double? = nil
    ) {
        self.splits = splits
        self.poorGPSShare = poorGPSShare
        self.climbFirstHalf = climbFirstHalf
        self.climbSecondHalf = climbSecondHalf
        self.longestNonStopSeconds = longestNonStopSeconds
        self.longestNonStopMeters = longestNonStopMeters
        self.startAltitude = startAltitude
    }
}

/// One work step of a structured session as it was run, for rep analysis (FB-4d, FB-4g).
struct LoggedStep: Codable, Hashable {
    var isWork: Bool
    var meters: Double
    var seconds: Double
    /// True when the runner ended the step early or skipped it.
    var cut: Bool = false

    var pace: Double { meters > 0 ? seconds / meters * 1_000 : 0 }
}

/// A saved run as the coach reads it. The app maps its `Run` model to this.
struct LoggedRun: Codable, Hashable, Identifiable {
    var id: UUID
    var start: Date
    /// Moving time in seconds, walking inside the run included (Terms).
    var movingSeconds: Double
    var meters: Double
    var source: RunSource
    /// The planned session the runner started this run from, if any. Matching fills the rest (AD-8).
    var plannedSessionID: UUID?
    var checkIn: RunCheckIn?
    var track: TrackSummary?
    /// The structured session's steps as run, for interval sessions.
    var steps: [LoggedStep]?
    /// Walking time inside the run, for run-walk sessions.
    var walkingSeconds: Double?

    init(
        id: UUID = UUID(),
        start: Date,
        movingSeconds: Double,
        meters: Double,
        source: RunSource = .gps,
        plannedSessionID: UUID? = nil,
        checkIn: RunCheckIn? = nil,
        track: TrackSummary? = nil,
        steps: [LoggedStep]? = nil,
        walkingSeconds: Double? = nil
    ) {
        self.id = id
        self.start = start
        self.movingSeconds = movingSeconds
        self.meters = meters
        self.source = source
        self.plannedSessionID = plannedSessionID
        self.checkIn = checkIn
        self.track = track
        self.steps = steps
        self.walkingSeconds = walkingSeconds
    }

    var end: Date { start.addingTimeInterval(movingSeconds) }

    var load: Load { Load(meters: meters, seconds: movingSeconds) }

    /// Seconds per km over the whole run, or nil without a distance.
    var pace: Double? { meters > 0 ? movingSeconds / meters * 1_000 : nil }

    /// Running seconds: moving time less walking, for run-walk volume (Terms).
    var runningSeconds: Double { max(0, movingSeconds - (walkingSeconds ?? 0)) }

    var rpe: Int? { checkIn?.rpe }
}

/// "Better / same / worse than normal" on the weekly check-in (AD-3).
enum WeeklyTrend: String, Codable, CaseIterable {
    case better
    case same
    case worse

    var name: String {
        switch self {
        case .better: "Better"
        case .same: "Same"
        case .worse: "Worse"
        }
    }
}

/// "The week: too easy / about right / hard but OK / too hard" (AD-3).
enum WeekFeel: String, Codable, CaseIterable {
    case tooEasy
    case aboutRight
    case hardButOK
    case tooHard

    var name: String {
        switch self {
        case .tooEasy: "Too easy"
        case .aboutRight: "About right"
        case .hardButOK: "Hard but OK"
        case .tooHard: "Too hard"
        }
    }
}

/// "Other training: same / more / new / less" (AD-3).
enum OtherTrainingChange: String, Codable, CaseIterable {
    case same
    case more
    case new
    case less
}

/// A non-running session the runner logs or names in a follow-up, classed by RB-1.
struct OtherSession: Codable, Hashable, Identifiable {
    var id: UUID
    var date: Date
    var kind: ActivityKind
    var minutes: Double
    var effort: Int
    var worksLegs: Bool
    var heavy: Bool
    /// Cross-training in place of a run while injured (AD-14e).
    var replacesRun: UUID?

    init(id: UUID = UUID(), date: Date, kind: ActivityKind, minutes: Double, effort: Int, worksLegs: Bool, heavy: Bool = false, replacesRun: UUID? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.minutes = minutes
        self.effort = effort
        self.worksLegs = worksLegs
        self.heavy = heavy
        self.replacesRun = replacesRun
    }
}

/// The weekly check-in at the end of each plan week (AD-3). Injury and pause questions are answered
/// through their own calls, so this holds only the general items.
struct WeeklyCheckIn: Codable, Hashable {
    var answeredAt: Date
    var week: WeekFeel?
    var legs: WeeklyTrend?
    var energy: WeeklyTrend?
    var lifeStress: WeeklyTrend?
    var motivation: WeeklyTrend?
    var ill: Bool?
    var otherTraining: OtherTrainingChange?
    /// The follow-up sessions for "more" or "new" (RB-6).
    var otherSessions: [OtherSession] = []
    var travel: Bool?

    init(answeredAt: Date, week: WeekFeel? = nil, legs: WeeklyTrend? = nil, energy: WeeklyTrend? = nil, lifeStress: WeeklyTrend? = nil, motivation: WeeklyTrend? = nil, ill: Bool? = nil) {
        self.answeredAt = answeredAt
        self.week = week
        self.legs = legs
        self.energy = energy
        self.lifeStress = lifeStress
        self.motivation = motivation
        self.ill = ill
    }

    /// How many of the four wellness items are worse than normal (family W).
    var worseWellnessItems: Int {
        [legs, energy, lifeStress, motivation].filter { $0 == .worse }.count
    }
}

/// The optional next-morning check (AD-2): fatigue and soreness 1-7, where 4 is normal.
struct MorningCheck: Codable, Hashable {
    var date: Date
    var fatigue: Int?
    var soreness: Int?

    init(date: Date, fatigue: Int? = nil, soreness: Int? = nil) {
        self.date = date
        self.fatigue = fatigue
        self.soreness = soreness
    }

    /// Fatigue or soreness over 5 (family W, AD-10's drop rule).
    var isHigh: Bool { (fatigue ?? 0) > 5 || (soreness ?? 0) > 5 }
}

/// "Ready for today's session?" before a Q, long run, test or race (RB-8).
enum ReadinessAnswer: String, Codable, CaseIterable {
    case goodToGo
    case belowNormal
    case unwell

    var name: String {
        switch self {
        case .goodToGo: "Good to go"
        case .belowNormal: "Legs or energy below normal"
        case .unwell: "Feeling unwell"
        }
    }
}
