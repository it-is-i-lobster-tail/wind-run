//
//  RunReviewTypes.swift
//  Wind Run
//

import Foundation

/// A run longer than 1.10 × P-L30 (AD-8): it counts at the cap and holds back the next steps.
struct SpikeRecord: Codable, Hashable {
    var runID: UUID
    var date: Date
    /// The run's load and the P-L30 in force when it was run.
    var load: Load
    var longest: Load
    /// Over 1.30 × P-L30: next week HOLD.
    var large: Bool
}

/// FB-4g's judgement of one Q, kept with the run so a re-plan can't lose it. `quality.outcomes` mirrors these.
struct SessionJudgement: Codable, Hashable {
    var runID: UUID
    var sessionID: UUID
    var date: Date
    var weekIndex: Int
    var type: QualityType
    var outcome: SessionOutcome
    /// PZ-7's down trigger: RPE target + 2 or more, or the session not finished.
    var downTrigger: Bool
    /// A cut on a session with no pace target: a third fewer reps instead of slower paces (PZ-7).
    var fewerReps: Bool
    /// Pace on target at RPE 1 or more below target: PZ-7's raise trigger.
    var easierThanTarget: Bool
    /// The work averaged more than 3% slower than target (family E, AD-4).
    var slow: Bool
    /// A marked fade, a tempo fade or a fading last rep (FB-4a, FB-4d, FB-4f): the even-pace band is added.
    var faded: Bool
    /// Judged on RPE and completion only (PZ-7's "conditions", or no usable pace): it never moves paces.
    var conditions: Bool
}

/// A pace change a run made, applied once and kept with the run (PZ-7, PZ-8, FB-4c, FB-4d).
enum RunEffectKind: String, Codable {
    /// Quality paces 3% slower: a Failed session or PZ-7's down trigger.
    case qualityCut
    /// Quality paces 3% slower after rep drift in 2 of the last 3 sessions of a type (FB-4d).
    case repsCut
    /// Quality paces 1% faster (PZ-7, HL-27).
    case qualityRaise
    /// PZ-8: the third easy run checked the reported pace; `changed` says whether the band moved.
    case easyChecked
    /// FB-4c: easy runs too fast, the band 15 s/km slower.
    case easySlowed
}

struct RunEffect: Codable, Hashable {
    var kind: RunEffectKind
    var runID: UUID
    var date: Date
    /// The runs the change used: a raise's sessions, a pattern's runs. They never count toward another one.
    var runIDs: [UUID]
    var changed: Bool
    /// PZ-8's new easy band.
    var band: PaceBand?

    init(kind: RunEffectKind, runID: UUID, date: Date, runIDs: [UUID] = [], changed: Bool = true, band: PaceBand? = nil) {
        self.kind = kind
        self.runID = runID
        self.date = date
        self.runIDs = runIDs
        self.changed = changed
        self.band = band
    }

    /// Identifies the effect in a plan baseline (`PlanBaseline.runEffects`).
    var key: String { "\(kind.rawValue)|\(runID.uuidString)" }
}

/// A pacing change for the next session of a kind, from FB-4a, FB-4b, FB-4d and FB-4f. The planner applies
/// each one to the first matching session dated after its run (`RunReviewer.advice(for:on:state:calendar:)`).
enum PacingAdviceKind: String, Codable {
    /// The even-pace band (target ±5%) on the next paced run, an in-run cue only. In Build Distance it is a
    /// ceiling at the easy band's fast edge on the next easy or long run.
    case evenBand
    /// The next tempo or race-pace session keeps its minutes as 5-min reps with threshold-rep recoveries.
    case splitIntoReps
    /// The next long run's first third stays inside the easy band.
    case capLongRunStart
    /// Build Distance: the next loading week keeps the long run at its current length, once.
    case holdLongRunStep
    /// FB-4f repeated: the next tempo becomes reps, or 3% slower when it's already reps.
    case tempoAsReps
    /// FB-4d still repeating after a pace cut: longer recoveries before any rep is cut (SW-5).
    case lengthenRecoveries
}

struct PacingAdvice: Codable, Hashable {
    var kind: PacingAdviceKind
    var runID: UUID
    var date: Date
    /// The session kinds the advice is for.
    var sessionKinds: [SessionKind]
    /// The Q type, for rep advice.
    var qualityType: QualityType?
    /// The even-pace band, or the Build Distance ceiling (its fast edge).
    var band: PaceBand?

    init(kind: PacingAdviceKind, runID: UUID, date: Date, sessionKinds: [SessionKind], qualityType: QualityType? = nil, band: PaceBand? = nil) {
        self.kind = kind
        self.runID = runID
        self.date = date
        self.sessionKinds = sessionKinds
        self.qualityType = qualityType
        self.band = band
    }
}

/// An offer or one-time message a run brought, kept with the run so its review can show it again (AD-8, FB-4).
enum RunOfferKind: String, Codable {
    case extraRunSlot
    case swapRunDay
    case walkBreaks
    case benchmarkSooner
    case cadenceCue
    /// AD-8's "Fun run!" message.
    case funRun
}

struct RunOffer: Codable, Hashable {
    var kind: RunOfferKind
    var runID: UUID
    var date: Date
    var question: CoachQuestion?
    /// The question's wording, when it depends on the runs ("You've run with a friend most Wednesdays").
    var text: String?
    var answeredAt: Date?
}

/// A retest a Failed session asked for (FB-4g), or the runner's yes to a benchmark sooner (FB-4l, FB-4m, SW-7a).
/// It holds `quality.retestWeek` at or below `dueWeek` until a week from `dueWeek` on has been planned.
struct RetestRequest: Codable, Hashable {
    var runID: UUID?
    var requestWeek: Int
    var dueWeek: Int

    /// Identifies the request in a plan baseline (`PlanBaseline.runEffects`).
    var key: String { "retest|\(runID?.uuidString ?? "runner")|\(requestWeek)|\(dueWeek)" }
}

/// AD-8's planned slot after the runner's yes: from plan week `week`, this many runs a week.
struct SlotChange: Codable, Hashable {
    var week: Int
    var runsPerWeek: Int

    /// Identifies the change in a plan baseline (`PlanBaseline.runEffects`).
    var key: String { "slot|\(week)|\(runsPerWeek)" }
}

/// The opt-in cadence cue (FB-4n): when the runner said yes, and the knee or shin report it serves. The
/// baseline is read from the runs at each call, never stored.
struct CadenceCueState: Codable, Hashable {
    var startedAt: Date
    var reportID: UUID
}

/// The plan changes a run can make (AD-8), one "because" sentence each.
enum RunChangeKind: String, Codable {
    /// Q made easy: a hard extra run took the week's Q, an RPE 5 run, or the 48 h after a spike or a hard day.
    case quality
    /// The long run moved, swapped or dropped for the 48 h after a spike or a hard day.
    case longRun
    /// AD-8's rest step: the next day is rest and the next run the week's shortest.
    case rest
    /// AD-8's total: trims, or next week's HOLD.
    case total
}

/// A "because" sentence a run's plan changes produced (AD-8), kept so a second review of the run shows it again
/// after the change is already in the plan.
struct RunNoteRecord: Codable, Hashable {
    var runID: UUID
    var kind: RunChangeKind
    var note: CoachNote
    /// The note follows the run's greeting ("Nice social run."), worked out from the check-in at each review.
    var greets: Bool

    init(runID: UUID, kind: RunChangeKind, note: CoachNote, greets: Bool = false) {
        self.runID = runID
        self.kind = kind
        self.note = note
        self.greets = greets
    }
}

/// What run reviews keep between runs (AD-8, FB-1 to FB-4, PZ-7, PZ-8). Nothing here comes from heart rate or
/// step rate: those are only ever notes on a run, worked out again at each call (PZ-13).
struct RunReviewState: Codable, Hashable {
    /// Runs already reviewed, so a second call for the same run (after its check-in) updates instead of adding.
    var reviewedRunIDs: [UUID]
    /// Runs found extra while their plan week was planned: they stay extra, so a trim they caused can't make them
    /// match the trimmed run later (AD-8).
    var extraRunIDs: [UUID]
    var spikes: [SpikeRecord]
    /// FB-4g judgements, one per Q run.
    var judgements: [SessionJudgement]
    /// Pace changes, each applied once.
    var effects: [RunEffect]
    var advice: [PacingAdvice]
    var offers: [RunOffer]
    var retestRequests: [RetestRequest]
    /// AD-8: the runner's yes to a planned slot for their extra run.
    var slotChanges: [SlotChange]
    /// FB-4c: the runner accepted walk breaks on easy runs.
    var walkBreaks: Bool
    var cadence: CadenceCueState?
    var runNotes: [RunNoteRecord]
    /// When the runner last answered "Want to try a benchmark sooner?" (FB-4l, FB-4m): not asked again for 4 weeks.
    var benchmarkAnsweredAt: Date?

    init() {
        reviewedRunIDs = []
        extraRunIDs = []
        spikes = []
        judgements = []
        effects = []
        advice = []
        offers = []
        retestRequests = []
        slotChanges = []
        walkBreaks = false
        runNotes = []
    }

    func effect(_ kind: RunEffectKind, runID: UUID) -> RunEffect? {
        effects.first { $0.kind == kind && $0.runID == runID }
    }

    func offer(_ kind: RunOfferKind, runID: UUID) -> RunOffer? {
        offers.first { $0.kind == kind && $0.runID == runID }
    }

    func judgement(runID: UUID) -> SessionJudgement? {
        judgements.first { $0.runID == runID }
    }

    /// The changes a plan baseline records as already made: pace changes, retest requests and planned slots.
    var baselineKeys: [String] {
        effects.map(\.key) + retestRequests.map(\.key) + slotChanges.map(\.key)
    }
}

/// What a week's runs add to the weekly families and the decision table (Applying AD-4, AD-8, FB-4g). Worked out
/// from the runs at each call.
struct RunWeekSignals: Hashable {
    /// FB-3 "Tired" answers on runs not already marked cut short (family E's cut-short flag).
    var extraEffortFlags: Int
    /// FB-4l's higher heart rate at the same easy pace (family H), from decision-grade heart rate only. Worked out
    /// from the runs at each call and never kept in the plan's state (PZ-13).
    var heartRateNegative: Bool
    /// Extra runs left the week more than 10% over plan and trims couldn't fit it (AD-8): HOLD. HL-2's cap is
    /// the weekly review's own check.
    var overPlan: Bool
    /// A second down-step in a row for one Q type this week: the fatigue check (FB-4g, PZ-7).
    var secondDownStep: Bool
}

/// Answers to the run review's own questions.
enum RunReviewAnswer: Codable, Hashable {
    /// AD-8: make the extra run a planned run on this day.
    case extraRunSlot(day: Weekday, accept: Bool)
    /// AD-8: swap a planned run day for the day the runner keeps running on.
    case swapRunDay(from: Weekday, to: Weekday, accept: Bool)
    /// FB-4c: walk breaks on easy runs.
    case walkBreaks(Bool)
    /// FB-4l, FB-4m: bring the next benchmark or retest forward.
    case benchmarkSooner(Bool)
    /// FB-4n: the cadence cue on easy runs.
    case cadenceCue(Bool)
}

/// The words for the run review's yes-or-no questions.
struct RunReviewPrompt: Hashable {
    var text: String
    var detail: String?
    var yes: String
    var no: String
}
