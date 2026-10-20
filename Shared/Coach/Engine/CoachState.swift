//
//  CoachState.swift
//  Wind Run
//

import Foundation

/// Why a plan is paused (AD-5 PAUSE).
enum PauseReason: String, Codable {
    /// A Severe report, or an Intense report without "cleared: yes" (AD-13c).
    case injury
    /// Fever or below-the-neck illness (AD-12).
    case illness
    /// Felt unwell in the heat (AD-16).
    case heat
    /// Fatigue Level 2 (AD-6b).
    case fatigue

    var name: String {
        switch self {
        case .injury: "Paused (injury)"
        case .illness: "Paused (illness)"
        case .heat: "Paused (heat)"
        case .fatigue: "Paused (fatigue)"
        }
    }
}

/// Why a plan stopped.
enum StopReason: String, Codable {
    /// The runner stopped it.
    case runner
    /// The race didn't start: an EF-5 or HL-19 "don't start", or a cancelled race (EV-9).
    case didNotStart
    /// Run days dropped below 2 a week (RC-1, arising mid-plan).
    case fewRunDays
    /// A new plan replaced it (RC-12a).
    case replaced
}

/// The plan's status (Open questions: plan state).
enum PlanStatus: Codable, Hashable {
    case active
    case paused(reason: PauseReason, since: Date)
    case complete(on: Date)
    case stopped(reason: StopReason, on: Date)

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
}

/// The level's cycle and the numbers the next step builds from (CL-1, CL-2, HL-4, AD-6a).
struct CycleState: Codable, Hashable {
    /// Position in the level's cycle for the next planned (not adaptive) week.
    var position: Int
    /// Loading, HOLD and EASE weeks in a row (HL-4).
    var loadingInRow: Int
    /// The last loading week's volume, the lower of planned and done: the next step's base.
    var lastLoadingVolume: Double
    /// The last loading week's long run.
    var lastLoadingLongRun: Load
    /// The level before an EASE or STEP BACK, which the next clean week returns to (AD-6a).
    var preCutVolume: Double?
    var preCutLongRun: Load?
    /// The last planned step-back, which resumes at its pre-step-back level plus one step (CL-2).
    var stepBackPending: Bool
    var lastNewLongest: Date?
    /// Planned runs a week now, and the week the last run was added (+1 per ≥4 weeks, HL-9).
    var runsPerWeek: Int
    var lastRunAddedWeek: Int?
    /// Weeks rated "too easy" in a row with no injury report (CL-4, AD-6d).
    var tooEasyWeeks: Int
    var levelUpOffered: Bool

    init(runsPerWeek: Int, lastLoadingVolume: Double, lastLoadingLongRun: Load) {
        self.position = 0
        self.loadingInRow = 0
        self.lastLoadingVolume = lastLoadingVolume
        self.lastLoadingLongRun = lastLoadingLongRun
        self.stepBackPending = false
        self.runsPerWeek = runsPerWeek
        self.tooEasyWeeks = 0
        self.levelUpOffered = false
    }
}

/// Quality sessions: the gate, the doses, the Speed Work block (HL-12, HL-13, SW-3).
struct QualityState: Codable, Hashable {
    /// The last dose of each Q type.
    var doses: [QualityDose]
    /// When HL-12's Q gate was first met.
    var gateMetOn: Date?
    /// Clean weeks at 1 Q, for the 2nd Q (CL-1).
    var cleanWeeksAtOneQ: Int
    /// Q types in the order they were last run, newest last, for alternation (SW-4).
    var recentTypes: [QualityType]
    /// Speed Work block: the plan week its week 1 fell on, and its length (8, or 6 in Reduced or Low).
    var blockStartWeek: Int?
    var blockLength: Int
    var blocksDone: Int
    /// A retest brought forward or set by a Failed session (FB-4g, SW-7a), by plan week.
    var retestWeek: Int?
    /// Recent outcomes per type, newest last (FB-4g: a second Struggled in a row is Failed).
    var outcomes: [QualityOutcomeRecord]
    /// Q sessions in a row judged "Even and on target" not yet used for a raise (PZ-7).
    var evenStreak: Int

    init() {
        doses = []
        cleanWeeksAtOneQ = 0
        recentTypes = []
        blockLength = 8
        blocksDone = 0
        outcomes = []
        evenStreak = 0
    }

    func dose(for type: QualityType) -> QualityDose? {
        doses.last { $0.type == type }
    }

    mutating func setDose(_ dose: QualityDose) {
        doses.removeAll { $0.type == dose.type }
        doses.append(dose)
    }
}

struct QualityOutcomeRecord: Codable, Hashable {
    var date: Date
    var type: QualityType
    var outcome: SessionOutcome
    var runID: UUID
}

/// AD-10's gap tiers.
enum GapTier: Int, Codable, Comparable {
    case g0
    case g1
    case g2
    case g3
    case g4

    /// Week-1 volume as a share of the reference, and its lower bound.
    var firstWeekShare: (normal: Double, lower: Double) {
        switch self {
        case .g0: (1.0, 1.0)
        case .g1: (0.75, 0.70)
        case .g2: (0.60, 0.50)
        case .g3: (0.50, 0.40)
        case .g4: (0.40, 0.30)
        }
    }

    /// Points added each week.
    var step: Double {
        switch self {
        case .g0: 0
        case .g1: 0.25
        case .g2: 0.20
        case .g3: 0.15
        case .g4: 0.10
        }
    }

    /// Week-1 long run as a share of the reference long run.
    var longRunShare: Double {
        switch self {
        case .g0: 1.0
        case .g1: 0.80
        case .g2: 0.65
        case .g3: 0.50
        case .g4: 0.40
        }
    }

    init(daysOff: Int) {
        switch daysOff {
        case ...7: self = .g0
        case 8...14: self = .g1
        case 15...28: self = .g2
        case 29...56: self = .g3
        default: self = .g4
        }
    }

    static func < (lhs: GapTier, rhs: GapTier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// An AD-10 return ramp in progress.
struct GapRamp: Codable, Hashable {
    var tier: GapTier
    var daysOff: Int
    /// The mean of the last 3 uninterrupted weeks, and the longest run in the 30 days before the gap.
    var reference: Double
    var referenceLongRun: Load
    /// The current share of the reference, and the step per week.
    var share: Double
    var step: Double
    var weeksDone: Int
    /// Drops in a row ("too hard", or soreness on 2 days), for the two-drops question.
    var dropsInRow: Int
    var startedAt: Date
}

/// AD-6b's fatigue clock.
struct FatigueState: Codable, Hashable {
    /// STEP BACK weeks in a row without recovery.
    var stepBacksInRow: Int
    /// 0 none, 1 Level 1, 2 Level 2 (pause).
    var level: Int
    /// The volume before the first cut, for Level 1's 50%.
    var preCutVolume: Double?

    init() {
        stepBacksInRow = 0
        level = 0
    }
}

/// An event plan's state (EV-1, EF-1 to EF-3).
enum EventStatus: String, Codable {
    case onTrack
    case goalAtRisk
    case finishLikely
    case offTrack

    var name: String {
        switch self {
        case .onTrack: "On track"
        case .goalAtRisk: "Goal at risk"
        case .finishLikely: "Finish likely"
        case .offTrack: "Off track"
        }
    }
}

struct EventState: Codable, Hashable {
    var raceDate: Date
    /// The taper's first day; it never moves (HL-16).
    var taperStart: Date
    /// The specific phase's first day.
    var specificStart: Date
    /// A time goal's speed block's first day, if any.
    var speedBlockStart: Date?
    var bufferWeeks: Int
    var bufferUsed: Int
    var status: EventStatus
    var cutoffRisk: Bool
    /// The goal became a comfortable finish (EF-3), or the injury review set a walk plan (EF-9).
    var finishOnly: Bool
    /// EF-9: the walk share and the run-walk pattern, once reviewed.
    var walkShare: Double?
    var runWalkPattern: String?
    var finishRange: ClosedRange<Double>?

    init(raceDate: Date, taperStart: Date, specificStart: Date, speedBlockStart: Date? = nil, bufferWeeks: Int, status: EventStatus = .onTrack) {
        self.raceDate = raceDate
        self.taperStart = taperStart
        self.specificStart = specificStart
        self.speedBlockStart = speedBlockStart
        self.bufferWeeks = bufferWeeks
        self.bufferUsed = 0
        self.status = status
        self.cutoffRisk = false
        self.finishOnly = false
    }
}

/// A pre-session check answer, kept with its session (RB-8).
struct ReadinessRecord: Codable, Hashable {
    var date: Date
    var sessionID: UUID
    var answer: ReadinessAnswer
    var heat: HeatAnswer?
}

/// A level change, with its date (CL-4).
struct LevelChange: Codable, Hashable {
    var date: Date
    var from: CommitmentLevel
    var to: CommitmentLevel
}

/// The values a week's planning and review change, kept so a re-plan or a late check-in can
/// start again from the same place instead of applying a change twice.
struct PlanBaseline: Codable, Hashable {
    var cycle: CycleState
    var quality: QualityState
    var gap: GapRamp?
    var fatigue: FatigueState
    var v0: Double
    var paces: TrainingPaces
    var ladder: LadderState?
    var event: EventState?

    init(_ state: CoachState) {
        cycle = state.cycle
        quality = state.quality
        gap = state.gap
        fatigue = state.fatigue
        v0 = state.v0
        paces = state.paces
        ladder = state.ladder
        event = state.event
    }

    func restore(into state: inout CoachState) {
        state.cycle = cycle
        state.quality = quality
        state.gap = gap
        state.fatigue = fatigue
        state.v0 = v0
        state.paces = paces
        state.ladder = ladder
        state.event = event
    }
}

/// One plan week: what was planned, the weekly check-in and the review.
struct WeekRecord: Codable, Hashable {
    var plan: PlannedWeek
    var checkIn: WeeklyCheckIn?
    var review: WeekReview?
    /// The state just before this week was planned, and just before it was reviewed.
    var planBaseline: PlanBaseline?
    var reviewBaseline: PlanBaseline?

    init(plan: PlannedWeek, checkIn: WeeklyCheckIn? = nil, review: WeekReview? = nil, planBaseline: PlanBaseline? = nil) {
        self.plan = plan
        self.checkIn = checkIn
        self.review = review
        self.planBaseline = planBaseline
    }
}

/// Everything the coach keeps for a plan. The app stores it as JSON and passes it back to each call.
/// History is never overwritten: weeks, reports and episodes keep their records (Storage principle).
struct CoachState: Codable, Hashable {
    static let currentRulesVersion = 1

    var rulesVersion: Int
    var intake: CoachIntake
    var goal: GoalChoice
    /// The runner confirmed "I understand this isn't recommended" (RC-9).
    var insisted: Bool
    /// A refused or paused goal, kept with the earliest date it can be planned (RC-1).
    var savedGoal: GoalChoice?
    /// The saved goal's earliest date (RC-1, RC-12), when one is known.
    var savedGoalEarliest: Date? = nil
    var startDate: Date
    var status: PlanStatus
    var level: CommitmentLevel
    var levelChanges: [LevelChange]
    var assessment: RunnerAssessment
    var paces: TrainingPaces
    /// V0 after calibration's re-base (TI-5), in the plan's unit.
    var v0: Double
    var weeks: [WeekRecord]
    var cycle: CycleState
    var quality: QualityState
    var ladder: LadderState?
    var gap: GapRamp?
    var fatigue: FatigueState
    var event: EventState?
    var injuries: [InjuryReport]
    var illnesses: [IllnessEpisode]
    var lifeEvents: [LifeEvent]
    var otherSessions: [OtherSession]
    var morningChecks: [MorningCheck]
    var readiness: [ReadinessRecord]
    /// Heat illness and the heat-risk window (AD-16).
    var heat: HeatState
    /// What run reviews keep between runs: spikes, extra-run habits, logged easy paces (AD-8, PZ-8, FB).
    var runReview: RunReviewState
    /// The event forecast and its checks (EF-1 to EF-9).
    var eventReview: EventReviewState
    /// Messages and offers that show once (milestones, the safety line at plan start, the physio suggestion).
    var shownOnce: Set<String>

    var volumeUnit: VolumeUnit { assessment.start.volumeUnit }

    /// The plan week that contains `date`, counted from the start in whole weeks.
    func weekIndex(on date: Date, calendar: Calendar) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: calendar.startOfDay(for: date)).day ?? 0
        return days >= 0 ? days / 7 : -1
    }

    /// The first day of plan week `index`.
    func weekStart(_ index: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: index * 7, to: calendar.startOfDay(for: startDate)) ?? startDate
    }

    /// The latest planned week.
    var currentWeek: PlannedWeek? { weeks.last?.plan }

    var openInjuries: [InjuryReport] { injuries.filter { !$0.status.isClosed } }

    var activeIllness: IllnessEpisode? { illnesses.last { $0.isActive } }

    /// The calendar day of a session.
    func date(of session: PlannedSession, in week: PlannedWeek, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: session.dayOffset, to: week.start) ?? week.start
    }
}

/// What a call to the engine returns: the new state, what to say, and what to ask.
struct CoachUpdate: Hashable {
    var state: CoachState
    var notes: [CoachNote]
    var questions: [CoachQuestion]

    init(state: CoachState, notes: [CoachNote] = [], questions: [CoachQuestion] = []) {
        self.state = state
        self.notes = notes
        self.questions = questions
    }
}

extension PlanBaseline {
    /// Only what planning a week changes: the cycle and the Q doses.
    func restorePlanning(into state: inout CoachState) {
        state.cycle = cycle
        state.quality = quality
    }
}

/// Deterministic UUIDs from text (FNV-1a), for IDs that must not change between launches.
enum StableID {
    static func make(_ text: String) -> UUID {
        var first: UInt64 = 0xcbf2_9ce4_8422_2325
        var second: UInt64 = 0x6c62_272e_07bb_0142
        for byte in text.utf8 {
            first = (first ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            second = (second ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
            second = (second << 7) | (second >> 57)
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0 ..< 8 {
            bytes[index] = UInt8(truncatingIfNeeded: first >> (8 * UInt64(index)))
            bytes[index + 8] = UInt8(truncatingIfNeeded: second >> (8 * UInt64(index)))
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
