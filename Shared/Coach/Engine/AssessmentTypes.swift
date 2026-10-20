//
//  AssessmentTypes.swift
//  Wind Run
//

import Foundation

/// The first step for a runner who can't yet run 5 minutes or more, or who walks first (TI-2, BD-2).
enum StarterEntry: Codable, Hashable {
    /// Brisk walks 3-5 times a week, starting at this many minutes (TI-2a).
    case walkStage(minutes: Double)
    /// 15 s run / 45 s walk, then 20/40, 25/35, 30/30 (TI-2b).
    case shortRunWalk
    /// A step of the run-walk ladder, as an index into `RunWalkStep.sequence` (BD-2a). The 1-minute step is NHS week 1.
    case ladder(step: Int)
}

/// Overlays set at intake (TI-3). The injury window and area memory live with the injury reports.
struct RunnerOverlays: Codable, Hashable {
    /// The first 12 weeks and 200 km of regular running (HL-11). It ends at a week's end once intake's credit and
    /// the plan's logged running reach both (TI-3).
    var earlyWindow: Bool
    /// Regular running credited at intake, in weeks and meters (TI-3: months × 4.3 × V0, max 200 km).
    var creditedWeeks: Double
    var creditedMeters: Double
    /// Back from a break: the AD-10 ramp comes first.
    var returning: Bool
    /// Raced and did sessions for a year or more: smaller time-goal gains (RC-6).
    var trained: Bool
    /// No finish at the goal distance in about 18 months.
    var firstTimer: Bool

    init(earlyWindow: Bool = false, creditedWeeks: Double = 0, creditedMeters: Double = 0, returning: Bool = false, trained: Bool = false, firstTimer: Bool = false) {
        self.earlyWindow = earlyWindow
        self.creditedWeeks = creditedWeeks
        self.creditedMeters = creditedMeters
        self.returning = returning
        self.trained = trained
        self.firstTimer = firstTimer
    }
}

/// One factor in the risk score (TI-4).
enum RiskFactor: String, Codable, CaseIterable {
    /// An Intense or Severe injury report in the last 12 months (TI-3b).
    case recentInjury
    /// BMI 30 or more, for Starters and Novices.
    case bmi
    /// Under 1 year of running.
    case underOneYear
    /// 65 or older, or 50+ with under 1 year of running or under 20 km a week.
    case age
    case recoveryReduced
    case recoveryLow

    var points: Int {
        switch self {
        case .recentInjury, .recoveryLow: 2
        case .bmi, .underOneYear, .age, .recoveryReduced: 1
        }
    }

    /// The reason a locked level shows: "Locked for now: {reason}. I re-check every 4 weeks."
    var reason: String {
        switch self {
        case .recentInjury: "you reported an injury in the last year"
        case .bmi: "your first weeks build more gently"
        case .underOneYear: "you've been running for under a year"
        case .age: "your age calls for a gentler build"
        case .recoveryReduced, .recoveryLow: "your other training already uses part of your recovery"
        }
    }
}

/// The risk score and its reasons (TI-4).
struct RiskScore: Codable, Hashable {
    var factors: [RiskFactor]

    init(factors: [RiskFactor] = []) {
        self.factors = factors
    }

    var points: Int { factors.reduce(0) { $0 + $1.points } }

    /// The factor with the most points, for the locked-level reason.
    var largestFactor: RiskFactor? { factors.max { $0.points < $1.points } }

    /// TI-4's row for a score of 2 or more: Gentle only, H weeks held in full, ≤3 runs, ≤1 Q.
    var isHigh: Bool { points >= 2 }
}

/// Recovery flags and tier (RB-2) and the RB-6 level drop.
struct RecoveryAssessment: Codable, Hashable {
    /// F1: ≥2 hard non-running sessions a week, or ≥3 h a week at RPE ≥5. A skipped IN-10 counts as F1.
    var otherTrainingFlag: Bool
    /// F4: a physical job or shift work.
    var workFlag: Bool
    /// Hard non-running sessions a week, for the hard-unit budget (RB-4).
    var hardSessionsPerWeek: Int
    /// Leg-strength days a week, for HL-7's 1-Q rule.
    var legDaysPerWeek: Int
    /// RB-6: heavy-leg or vigorous training ≥3 times a week, or new or doubled in 8 weeks, drops the
    /// level one step for 8 weeks. The date the drop ends.
    var levelDropUntil: Date?

    init(otherTrainingFlag: Bool = false, workFlag: Bool = false, hardSessionsPerWeek: Int = 0, legDaysPerWeek: Int = 0, levelDropUntil: Date? = nil) {
        self.otherTrainingFlag = otherTrainingFlag
        self.workFlag = workFlag
        self.hardSessionsPerWeek = hardSessionsPerWeek
        self.legDaysPerWeek = legDaysPerWeek
        self.levelDropUntil = levelDropUntil
    }

    var tier: RecoveryTier {
        switch (otherTrainingFlag ? 1 : 0) + (workFlag ? 1 : 0) {
        case 0: .normal
        case 1: .reduced
        default: .low
        }
    }
}

/// The levels the runner may pick (CL-3).
struct LevelOptions: Codable, Hashable {
    var preset: CommitmentLevel
    var ceiling: CommitmentLevel
    /// "Locked for now: {reason}. I re-check every 4 weeks." Nil when nothing is locked.
    var lockedReason: String?

    func allows(_ level: CommitmentLevel) -> Bool { level <= ceiling }

    /// The text under a greyed level.
    var lockedMessage: String? {
        lockedReason.map { "Locked for now: \($0). I re-check every 4 weeks." }
    }
}

/// Where the plan starts from (TI-5, HL-17, IN-21).
struct StartingPoint: Codable, Hashable {
    /// Distance, or running minutes when the answers or the pace call for it (IN-21).
    var volumeUnit: VolumeUnit
    /// V0: the low end of the weekly range, in the volume unit.
    var v0: Double
    /// The reported longest run, if given.
    var reportedLongest: Load?
    /// The starting P-L30: min(0.9 × reported longest, 0.5 × V0) (TI-5).
    var planningLongest: Load
    /// Planned runs a week to start: the current number within the caps and the days offered.
    var runsPerWeek: Int
    /// Hard sessions a week the runner does now.
    var currentQ: Int
    /// A run length the runner already sustains (HL-6, HL-14), in the volume unit.
    var sustainedRunLength: Double?
    /// False for walk-stage and ladder runners, who skip the 2-week calibration (HL-17).
    var calibrates: Bool
    /// For Returning runners: the pre-break week and long run, the ramp's reference (AD-10).
    var preBreakVolume: Double?
    var preBreakLongest: Load?

    init(
        volumeUnit: VolumeUnit,
        v0: Double,
        reportedLongest: Load? = nil,
        planningLongest: Load,
        runsPerWeek: Int,
        currentQ: Int = 0,
        sustainedRunLength: Double? = nil,
        calibrates: Bool = true,
        preBreakVolume: Double? = nil,
        preBreakLongest: Load? = nil
    ) {
        self.volumeUnit = volumeUnit
        self.v0 = v0
        self.reportedLongest = reportedLongest
        self.planningLongest = planningLongest
        self.runsPerWeek = runsPerWeek
        self.currentQ = currentQ
        self.sustainedRunLength = sustainedRunLength
        self.calibrates = calibrates
        self.preBreakVolume = preBreakVolume
        self.preBreakLongest = preBreakLongest
    }
}

/// Everything intake sets: tier, overlays, risk, recovery, levels and the starting numbers.
struct RunnerAssessment: Codable, Hashable {
    var assessedAt: Date
    var age: Int
    var tier: RunnerTier
    var overlays: RunnerOverlays
    /// Set when the runner starts on the walk stage, the short run-walk or the ladder (TI-2).
    var starterEntry: StarterEntry?
    var recovery: RecoveryAssessment
    var risk: RiskScore
    var levels: LevelOptions
    var start: StartingPoint
    /// Fewer than 2 run days: 1 run plus walking, no event, no Q (HL-9).
    var habitMode: Bool
    /// Planned runs a week, at most (HL-9).
    var runsCap: Int
    /// Q per 7 days, at most, before the level's target (HL-7).
    var qCap: Int
    /// Months of regular running, from IN-5.
    var monthsRunning: Double
    /// Runs 30 minutes non-stop.
    var runs30Minutes: Bool

    var recoveryTier: RecoveryTier { recovery.tier }
}
