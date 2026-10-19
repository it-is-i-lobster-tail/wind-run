//
//  GoalCheckTypes.swift
//  Wind Run
//

import Foundation

/// Readiness of the distance at taper start (RC-2).
enum DistanceStatus: Int, Codable, Comparable {
    case green
    case amber
    case red

    var name: String {
        switch self {
        case .green: "Green"
        case .amber: "Amber"
        case .red: "Red"
        }
    }

    static func < (lhs: DistanceStatus, rhs: DistanceStatus) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// How a time goal compares with realistic improvement (RC-6d).
enum TimeVerdict: Int, Codable, Comparable {
    case realistic
    case stretch
    case unlikely

    var name: String {
        switch self {
        case .realistic: "Realistic"
        case .stretch: "Stretch"
        case .unlikely: "Unlikely"
        }
    }

    static func < (lhs: TimeVerdict, rhs: TimeVerdict) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The overall verdict (RC-7).
enum GoalVerdict: String, Codable {
    /// "On track".
    case green
    /// "Doable with changes".
    case amber
    /// "Not ready": not built unless the runner insists (RC-9).
    case red
    /// No plan (RC-1); the alternative comes in the same message.
    case refused

    var label: String {
        switch self {
        case .green: "On track"
        case .amber: "Doable with changes"
        case .red: "Not ready"
        case .refused: "No plan"
        }
    }
}

/// Why a goal is refused outright (RC-1).
enum RefusalReason: String, Codable {
    /// An event longer than 10K inside the early window.
    case earlyWindow
    /// A first marathon failing HL-26.
    case firstMarathon
    /// A Severe injury report pauses the plan.
    case severeInjury
    /// An event or Speed Work with fewer than 2 run days a week.
    case fewRunDays
}

/// The feasibility simulation's output (RC-4).
struct Feasibility: Codable, Hashable {
    /// Earliest weeks to Green, including calibration and taper.
    var earliestWeeks: Int
    /// round(1.15 × earliest).
    var likelyWeeks: Int
    var earliestDate: Date
    var likelyDate: Date
    /// max(2, ceil(build ÷ 6)), +1 per 6 build weeks in the Low recovery tier.
    var bufferWeeks: Int
    /// The long run projected at taper start (events), or at the earliest date.
    var projectedLongest: Load
    /// The weekly volume projected at taper start, in the plan's unit.
    var projectedVolume: Double
    var longRunStatus: DistanceStatus
    var volumeStatus: DistanceStatus
    /// The worse of the two.
    var status: DistanceStatus
    /// Race distance ÷ projected longest run.
    var raceToLongest: Double
    /// RC-4 step 2a: the long run or the volume doesn't fit the runner's time per run.
    var longRunTimeLimited: Bool
    var volumeTimeLimited: Bool
}

/// A time-goal check (RC-6).
struct TimeGoalCheck: Codable, Hashable {
    /// R = (current equivalent − goal) ÷ current equivalent.
    var improvementNeeded: Double
    var currentEquivalent: Double
    var realisticGain: Double
    var stretchGain: Double
    var yearlyCap: Double
    var verdict: TimeVerdict
    /// current × (1 − stretch sum) when the goal is Unlikely.
    var interimGoal: Double?
    /// R above the yearly cap.
    var multiSeason: Bool
    /// Novice goals stay provisional until a test after the early window (RC-6e).
    var provisional: Bool
}

/// One alternative the coach offers instead of the goal (RC-8d, RC-1).
struct GoalAlternative: Codable, Hashable {
    var goal: GoalChoice
    var label: String
    var status: DistanceStatus?
}

/// The result of the realism check (RC-1 to RC-9), with the message the coach shows.
struct GoalCheck: Codable, Hashable {
    var verdict: GoalVerdict
    var refusal: RefusalReason?
    var feasibility: Feasibility?
    var forecast: RaceForecast?
    var timeGoal: TimeGoalCheck?
    var alternatives: [GoalAlternative]
    /// A refused goal is saved with the earliest date it can be planned (RC-1, HL-26).
    var savedGoalEarliest: Date?
    /// Amber or insist path: walk breaks from the start (EF-4).
    var plansRunWalk: Bool
    /// A cut-off at risk (RC-6c, EF-3).
    var cutoffAtRisk: Bool
    /// "Train for it anyway" is offered (Red, not refused).
    var canInsist: Bool
    /// The coach's message, one numeric reason, no shame (RC-8).
    var message: String
}
