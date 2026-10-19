//
//  WeekTargets.swift
//  Wind Run
//

import Foundation

/// How a week's runs are run.
enum RunForm: Codable, Hashable {
    /// Continuous running; walking is allowed on easy and long runs.
    case continuous
    /// Run-walk at easy effort: run for `runSeconds`, then walk for `walkSeconds`, repeated.
    /// A nil walk is an open walk break that ends on tap, with a prompt at 1.5 min (BD-2a).
    case runWalk(runSeconds: Double, walkSeconds: Double?)
    /// Brisk walking only: the walk stage (TI-2) and habit mode's walks (HL-9).
    case walk
}

/// A race on a day of the week: the goal race or a Speed Work attempt (EV-8, SW-8).
struct RaceDay: Codable, Hashable {
    var dayOffset: Int
    var distance: RaceDistance
    /// The target finish, when there is a time goal or a forecast.
    var targetSeconds: Double?
}

/// A week's shape before the scheduler puts it on days. Every rule module returns one of these for
/// the weeks it governs (injury, illness, the ladder, gaps), and the planner for the rest.
struct WeekTargets: Hashable {
    var kind: WeekKind
    var cycleWeek: CycleWeek?
    var phase: TrainingPhase?
    var blockWeek: Int?
    /// Running volume in the plan's unit. 0 for a week with no planned running.
    var volume: Double
    /// The long run, or nil when the week has none and every run is alike.
    var longRun: Load?
    var isNewLongest: Bool
    /// Planned runs, the long run and the Q included.
    var runs: Int
    /// Quality sessions to place, the key one first.
    var quality: [QualityDose]
    /// How many easy runs carry strides.
    var strides: Int
    var form: RunForm
    /// The most any single session may hold (HL-11's early-window cap, an illness stage, a fatigue week).
    var sessionCap: Load?
    /// Plan items that aren't runs: brisk walks, strength and balance (HL-25), cross-training (AD-14e).
    var extras: [SessionKind]
    var race: RaceDay?
    /// At least this many rest days (HL-10, fatigue Level 1's 2).
    var minimumRestDays: Int?
    var notes: [CoachNote]

    init(
        kind: WeekKind,
        cycleWeek: CycleWeek? = nil,
        phase: TrainingPhase? = nil,
        blockWeek: Int? = nil,
        volume: Double,
        longRun: Load? = nil,
        isNewLongest: Bool = false,
        runs: Int,
        quality: [QualityDose] = [],
        strides: Int = 0,
        form: RunForm = .continuous,
        sessionCap: Load? = nil,
        extras: [SessionKind] = [],
        race: RaceDay? = nil,
        minimumRestDays: Int? = nil,
        notes: [CoachNote] = []
    ) {
        self.kind = kind
        self.cycleWeek = cycleWeek
        self.phase = phase
        self.blockWeek = blockWeek
        self.volume = volume
        self.longRun = longRun
        self.isNewLongest = isNewLongest
        self.runs = runs
        self.quality = quality
        self.strides = strides
        self.form = form
        self.sessionCap = sessionCap
        self.extras = extras
        self.race = race
        self.minimumRestDays = minimumRestDays
        self.notes = notes
    }

    /// A week with no planned running (PAUSE).
    static func paused(notes: [CoachNote] = []) -> WeekTargets {
        WeekTargets(kind: .paused, volume: 0, runs: 0, notes: notes)
    }
}

/// What the planner knows when it shapes a week: the plan so far and the load numbers in force.
struct PlanningContext {
    var state: CoachState
    var runs: [LoggedRun]
    var sessions: [RunSessionLoad]
    /// The plan week being shaped and its first day.
    var weekIndex: Int
    var weekStart: Date
    /// P-L30 and W4max in force at the week's start.
    var longest: Load
    var w4max: Double
    /// HL-2's cap for the week.
    var weekCap: Double
    var now: Date
    var calendar: Calendar

    var unit: VolumeUnit { state.volumeUnit }

    /// The pace used to convert between distance and time: the easy band's middle.
    var easyPace: Double? { state.paces.easyPace }

    /// The previous week's record, if any.
    var previousWeek: WeekRecord? {
        state.weeks.last { $0.plan.index == weekIndex - 1 }
    }
}
