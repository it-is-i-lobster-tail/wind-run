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
    /// An event date before today.
    case pastDate
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
    /// The unit the paths and targets are in.
    var unit: VolumeUnit = .distance
    /// RC-2's Green long run and volume, capped by HL-5, in `unit`.
    var targetLongRun: Double = 0
    var targetVolume: Double = 0
    /// Weeks from today to race day (RC-7); nil without a date.
    var weeksAvailable: Int? = nil
    /// Weeks the open injury report's plan takes first (RC-4 step 2b).
    var heldWeeks: Int = 0
    /// Calibration weeks still to run (TI-5), and walk-stage or ladder weeks before the cycle (BD-2).
    var calibrationWeeks: Int = 0
    var ladderWeeks: Int = 0
    /// Weeks until RC-3's gate is met (0 when it already is), and its block minimum. Nil when no gate applies.
    var gateWeeks: Int? = nil
    var blockMinimum: Int = 0
    /// RC-2's time-goal rows (half 21 km and 32 km; marathon 4 runs over 20 km in 16 weeks) are met too.
    var timeGoalReady: Bool = true
    /// RC-4 step 2a's limits: the long-run day's time, and the time all planned run days hold.
    var longRunLimitSeconds: Double? = nil
    var volumeCapacitySeconds: Double? = nil
    /// Green can't be reached at all inside the runner's time (RC-4 step 2a), or within three years.
    var unreachable: Bool = false
    /// The projected end of the early window (TI-3), in weeks from now; nil when it is over or never ends in view.
    var earlyWindowEndWeeks: Int? = nil
    /// Weeks until the long run and the volume are both Green (RC-4 steps 3 and 4), calibration included; nil
    /// when they never are inside the simulation.
    var pathWeeks: Int? = nil
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
    /// The goal time in seconds.
    var goalSeconds: Double = 0
    /// The weeks the gains were counted over (RC-6b): weeks to race day, or the next block.
    var weeksCounted: Int = 0
    /// Speed Work: blocks the realistic gains need to reach R; nil when R passes the yearly cap (RC-6c).
    var blocksNeeded: Int? = nil
    /// No anchor yet: R comes from PZ-6a's plausible 5K (easy pace ÷ 1.5).
    var noAnchor: Bool = false
    /// When the coach plans to test and re-check (RC-8c), or confirm a provisional goal (RC-6e).
    var retestDate: Date? = nil
}

/// One alternative the coach offers instead of the goal (RC-8d, RC-1).
struct GoalAlternative: Codable, Hashable {
    var goal: GoalChoice
    var label: String
    var status: DistanceStatus?
    /// The alternative's earliest Green date, when it moves the date.
    var earliestDate: Date? = nil
    /// "Finish with walk breaks" (RC-8d option 1, Amber) or a run-walk finish (option 3).
    var walkBreaks: Bool = false
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
    /// A refused goal kept for later (RC-1), with its earliest date in `savedGoalEarliest`.
    var savedGoal: GoalChoice? = nil
    /// RC-12: an event more than 52 weeks away starts its plan on this date; until then a Build Distance plan
    /// runs (RC-12a).
    var planStartsOn: Date? = nil
    /// RC-8b, RC-9: the plan is built without the time goal.
    var timeGoalDropped: Bool = false
    /// The plan pace for race-pace work: the central forecast, only when the time goal is Realistic or Stretch (PZ-5).
    var racePace: Double? = nil
}
