//
//  PlanTypes.swift
//  Wind Run
//

import Foundation

/// What a planned session is (Building blocks, plus the plan items the rules add).
enum SessionKind: String, Codable, CaseIterable {
    case easy
    case long
    /// Threshold or tempo, continuous or in reps.
    case threshold
    /// VO2max reps of 2-4 min (4-6 at 50+).
    case intervals
    /// 30/30, 15/15 or 10-20-30 in 5-min blocks.
    case shortReps
    case hills
    /// Half or marathon pace, at the central forecast.
    case racePace
    /// An app test (PZ-3), all-out or controlled.
    case test
    /// The goal race, a tune-up or a Speed Work attempt.
    case race
    /// Run-walk: the ladder, the short run-walk, a Severe return's jog/walk.
    case runWalk
    /// Brisk walking: the walk stage and habit mode.
    case walk
    /// Strength and balance (HL-25 at 65+).
    case strength
    /// A bike, pool run, swim or elliptical in place of a run while injured (AD-14e).
    case crossTraining

    var name: String {
        switch self {
        case .easy: "Easy run"
        case .long: "Long run"
        case .threshold: "Tempo run"
        case .intervals: "Intervals"
        case .shortReps: "Short reps"
        case .hills: "Hills"
        case .racePace: "Race pace"
        case .test: "Test"
        case .race: "Race day"
        case .runWalk: "Run-walk"
        case .walk: "Brisk walk"
        case .strength: "Strength and balance"
        case .crossTraining: "Cross-training"
        }
    }

    /// Quality sessions (Terms): threshold or faster, intervals, hills, race pace, races and tests.
    var isQuality: Bool {
        switch self {
        case .threshold, .intervals, .shortReps, .hills, .racePace, .test, .race: true
        case .easy, .long, .runWalk, .walk, .strength, .crossTraining: false
        }
    }

    /// Counts toward running volume.
    var isRun: Bool {
        switch self {
        case .walk, .strength, .crossTraining: false
        default: true
        }
    }
}

/// A Q's type, for doses and the mix (HL-13, SW-4, EV-2).
enum QualityType: String, Codable, CaseIterable {
    case threshold
    case vo2max
    case shortReps
    case hills
    case racePace

    var sessionKind: SessionKind {
        switch self {
        case .threshold: .threshold
        case .vo2max: .intervals
        case .shortReps: .shortReps
        case .hills: .hills
        case .racePace: .racePace
        }
    }

    var effort: Effort {
        switch self {
        case .threshold: .threshold
        case .vo2max, .shortReps, .hills: .interval
        case .racePace: .steady
        }
    }
}

/// A Q's dose: reps of a length, or one continuous piece, and its place on the type's ladder.
struct QualityDose: Codable, Hashable {
    var type: QualityType
    /// Position on the type's ladder (SW-5).
    var step: Int
    var reps: Int
    /// Work per rep in seconds.
    var repSeconds: Double
    /// Recovery after each rep in seconds (jog, or walk down hills).
    var recoverySeconds: Double
    /// One continuous piece instead of reps.
    var continuous: Bool

    init(type: QualityType, step: Int, reps: Int, repSeconds: Double, recoverySeconds: Double, continuous: Bool = false) {
        self.type = type
        self.step = step
        self.reps = reps
        self.repSeconds = repSeconds
        self.recoverySeconds = recoverySeconds
        self.continuous = continuous
    }

    /// Minutes of work: what the dose caps and the HL-8 share count.
    var workSeconds: Double { Double(reps) * repSeconds }

    /// "3 × 5 min", "20 min".
    var summary: String {
        let minutes = repSeconds / 60
        let repText = minutes == minutes.rounded() ? "\(Int(minutes)) min" : CoachFormat.clock(repSeconds)
        return continuous || reps == 1 ? repText : "\(reps) × \(repText)"
    }
}

/// A step of a structured session, mirroring the app's interval steps.
enum SessionStepKind: String, Codable {
    case warmup
    case work
    case recovery
    case cooldown
}

/// When a step ends.
enum StepGoal: Codable, Hashable {
    case time(seconds: Double)
    case distance(meters: Double)
    /// Ends on tap (ladder walk breaks prompt at 1.5 min).
    case open
}

struct SessionStep: Codable, Hashable {
    var kind: SessionStepKind
    var goal: StepGoal
    var effort: Effort
    /// A pace band to hold, or nil to go by effort.
    var pace: PaceBand?
    /// A walking step (run-walk, walk breaks, walk-down recoveries).
    var walk: Bool

    init(kind: SessionStepKind, goal: StepGoal, effort: Effort, pace: PaceBand? = nil, walk: Bool = false) {
        self.kind = kind
        self.goal = goal
        self.effort = effort
        self.pace = pace
        self.walk = walk
    }
}

/// Steps repeated a number of times: "5 × (3 min hard, 2 min easy)".
struct SessionBlock: Codable, Hashable {
    var repeats: Int
    var steps: [SessionStep]

    init(repeats: Int = 1, steps: [SessionStep]) {
        self.repeats = max(1, repeats)
        self.steps = steps
    }
}

/// PZ-3's app test as planned: 12 minutes for 1 mile to 10K goals, or 5 km for half and marathon goals.
/// A controlled test is capped at RPE 8 and its result is marked low precision.
struct AppTest: Codable, Hashable {
    /// The test's work: `.time(seconds: 720)` or `.distance(meters: 5_000)`.
    var goal: StepGoal
    var controlled: Bool
}

/// Why a session became an easy run of the same minutes.
enum EasyReason: String, Codable {
    /// A hard day would touch another (RB-5).
    case spacing
    /// Legs or energy below normal (RB-8).
    case readiness
    /// An extra hard run took the week's Q (AD-8).
    case extraRun
    /// An open Mild report (AD-13a).
    case mildInjury
    /// EASE, STEP BACK or HL-8's one-Q week.
    case adaptation
    /// Head cold (AD-12).
    case illness
    /// Over the hard-unit budget (RB-4).
    case budget
}

/// Where a planned session stands.
enum SessionStatus: Codable, Hashable {
    case planned
    /// Matched to a run (AD-8).
    case done(runID: UUID)
    case missed
    /// Dropped: a key session that couldn't move, or a trimmed run (AD-8, AD-9).
    case dropped

    var isPlanned: Bool { self == .planned }
}

/// One planned session.
struct PlannedSession: Codable, Hashable, Identifiable {
    var id: UUID
    /// Days after the start of the plan week, 0...6.
    var dayOffset: Int
    var kind: SessionKind
    var effort: Effort
    /// Planned distance and time. `leadsWith` says which one the runner sees.
    var target: Load
    var leadsWith: VolumeUnit
    /// The pace to keep, or nil for effort only. For easy runs only the fast edge is a limit.
    var paceBand: PaceBand?
    /// Steps for structured sessions; empty for continuous runs.
    var blocks: [SessionBlock]
    /// Strides after an easy run, 0 for none.
    var strides: Int
    /// The Q's dose, for quality sessions.
    var dose: QualityDose?
    /// The week's key session (Terms): the long run, or the Q in Speed Work.
    var isKey: Bool
    /// A new longest run (HL-1's one per 7 days).
    var isNewLongest: Bool
    var madeEasy: EasyReason?
    /// The day it moved from (AD-9), if it moved.
    var movedFrom: Int?
    /// Short lines shown with the session: the fuel tip, route changes, the early-window cap.
    var notes: [String]
    var status: SessionStatus
    /// The app test this session is (PZ-3), for kind `.test`.
    var appTest: AppTest?
    /// An easy run that is also BD-5c's benchmark: the usual benchmark route at RPE 3.
    var benchmark: Bool?

    init(
        id: UUID = UUID(),
        dayOffset: Int,
        kind: SessionKind,
        effort: Effort = .easy,
        target: Load,
        leadsWith: VolumeUnit = .distance,
        paceBand: PaceBand? = nil,
        blocks: [SessionBlock] = [],
        strides: Int = 0,
        dose: QualityDose? = nil,
        isKey: Bool = false,
        isNewLongest: Bool = false,
        madeEasy: EasyReason? = nil,
        movedFrom: Int? = nil,
        notes: [String] = [],
        status: SessionStatus = .planned,
        appTest: AppTest? = nil,
        benchmark: Bool? = nil
    ) {
        self.id = id
        self.dayOffset = dayOffset
        self.kind = kind
        self.effort = effort
        self.target = target
        self.leadsWith = leadsWith
        self.paceBand = paceBand
        self.blocks = blocks
        self.strides = strides
        self.dose = dose
        self.isKey = isKey
        self.isNewLongest = isNewLongest
        self.madeEasy = madeEasy
        self.movedFrom = movedFrom
        self.notes = notes
        self.status = status
        self.appTest = appTest
        self.benchmark = benchmark
    }

    var isQuality: Bool { kind.isQuality && madeEasy == nil }

    var isBenchmark: Bool { benchmark == true }

    /// A hard day (Terms): a Q, or a long run over 90 minutes.
    var isHardDay: Bool {
        isQuality || (kind == .long && target.seconds > CoachLimits.hardLongRunSeconds)
    }

    /// The RPE range the session aims for (PZ-1).
    var rpeTarget: ClosedRange<Int> { effort.rpeRange }
}

/// The kind of plan week.
enum WeekKind: String, Codable {
    /// TI-5: just under the reported numbers, nothing progresses.
    case calibration
    /// A loading week on the cycle: N or H.
    case loading
    /// A planned step-back (CL-2).
    case stepBack
    /// AD-5 outcomes.
    case hold
    case ease
    case adaptiveStepBack
    /// AD-6b fatigue Level 1: easy only, 50% of the pre-cut volume, ≥2 rest days.
    case fatigueEasy
    /// No planned running: Severe report, illness, heat or fatigue Level 2.
    case paused
    /// AD-10 return ramp after a gap.
    case ramp
    /// AD-14b Intense recovery plan.
    case recovery
    /// AD-14c Severe return weeks and ramp.
    case injuryReturn
    /// AD-12 illness return stages.
    case illnessReturn
    /// The ladder, short run-walk or walk stage (BD-2, TI-2).
    case ladder
    /// EV-6 taper weeks before the dead week.
    case taper
    /// The race week, or the week before a Speed Work attempt: ≤50%, all easy (EV-6, SW-8).
    case dead
    /// After the race (EV-9).
    case raceRecovery
    /// AD-11 busy weeks.
    case busy
    /// HL-9 habit mode: 1 run plus walking.
    case habit
    /// After a rung or goal: no more distance added (BD-1g, SW-7c).
    case maintain

    var name: String {
        switch self {
        case .calibration: "Starting check"
        case .loading: "Building week"
        case .stepBack: "Lighter week"
        case .hold: "Holding week"
        case .ease: "Easier week"
        case .adaptiveStepBack: "Lighter week"
        case .fatigueEasy: "Easy week"
        case .paused: "Paused"
        case .ramp: "Easing back"
        case .recovery: "Recovery plan"
        case .injuryReturn: "Return week"
        case .illnessReturn: "Easing back"
        case .ladder: "Run-walk"
        case .taper: "Taper"
        case .dead: "Race week"
        case .raceRecovery: "Recovery week"
        case .busy: "Busy week"
        case .habit: "Habit week"
        case .maintain: "Maintain"
        }
    }

    /// Weeks that count toward HL-4's limit of 3 loading weeks in a row.
    var countsAsLoading: Bool {
        switch self {
        case .loading, .hold, .ease: true
        default: false
        }
    }
}

/// Where an event or Speed Work plan is (EV-1, SW-3).
enum TrainingPhase: String, Codable {
    case base
    case build
    /// A 4-week speed block before the specific phase (time goals), or a Speed Work block.
    case speedBlock
    case specific
    case taper
    case raceWeek
    case recovery
    /// Speed Work's volume cycle between blocks (SW-6).
    case volumeCycle
}

/// One planned week. Volume and long run are targets in the plan's volume unit.
struct PlannedWeek: Codable, Hashable, Identifiable {
    /// 0-based plan week.
    var index: Int
    var start: Date
    var kind: WeekKind
    var cycleWeek: CycleWeek?
    var phase: TrainingPhase?
    /// Speed Work block week, 1-8 (1-6 in the short form).
    var blockWeek: Int?
    var volumeUnit: VolumeUnit
    var plannedVolume: Double
    var longRun: Load?
    var sessions: [PlannedSession]
    /// The "because" sentences behind the week (AD-5, every limit that binds).
    var notes: [CoachNote]

    var id: Int { index }

    init(
        index: Int,
        start: Date,
        kind: WeekKind,
        cycleWeek: CycleWeek? = nil,
        phase: TrainingPhase? = nil,
        blockWeek: Int? = nil,
        volumeUnit: VolumeUnit,
        plannedVolume: Double,
        longRun: Load? = nil,
        sessions: [PlannedSession] = [],
        notes: [CoachNote] = []
    ) {
        self.index = index
        self.start = start
        self.kind = kind
        self.cycleWeek = cycleWeek
        self.phase = phase
        self.blockWeek = blockWeek
        self.volumeUnit = volumeUnit
        self.plannedVolume = plannedVolume
        self.longRun = longRun
        self.sessions = sessions
        self.notes = notes
    }

    var runs: [PlannedSession] { sessions.filter { $0.kind.isRun } }

    var qualitySessions: [PlannedSession] { sessions.filter(\.isQuality) }

    /// The planned volume of the run sessions, in the week's unit.
    var sessionVolume: Double { runs.reduce(0) { $0 + $1.target.amount(in: volumeUnit) } }
}
