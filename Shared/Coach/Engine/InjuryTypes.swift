//
//  InjuryTypes.swift
//  Wind Run
//

import Foundation

/// How bad an injury is, as the runner reports it (AD-13). The coach never diagnoses.
enum InjuryLevel: Int, Codable, CaseIterable, Comparable {
    case mild
    case intense
    case severe

    var name: String {
        switch self {
        case .mild: "Mild"
        case .intense: "Intense"
        case .severe: "Severe"
        }
    }

    /// The text under each choice on "How bad is it?"
    var detail: String {
        switch self {
        case .mild: "Some pain that fades within about 30 minutes after a run, like light shin splints."
        case .intense: "You think you may need a physio, or you're seeing one and you're cleared to train."
        case .severe: "You need to stop: it hurts too much to run, or you're not cleared to run."
        }
    }

    static func < (lhs: InjuryLevel, rhs: InjuryLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Where it hurts (optional). Used only for wording, route changes, the area memory and the
/// same-area count, never for a diagnosis (AD-13).
enum InjuryArea: String, Codable, CaseIterable {
    case footAnkle
    case shin
    case calfAchilles
    case knee
    case thighHamstring
    case hipGroin
    case back
    case other

    var name: String {
        switch self {
        case .footAnkle: "foot or ankle"
        case .shin: "shin"
        case .calfAchilles: "calf or Achilles"
        case .knee: "knee"
        case .thighHamstring: "thigh or hamstring"
        case .hipGroin: "hip or groin"
        case .back: "back"
        case .other: "other"
        }
    }

    /// AD-13d: no hills for the shin, calf, Achilles, foot and ankle.
    var avoidsHills: Bool { self == .shin || self == .calfAchilles || self == .footAnkle }

    /// AD-13d: no steep downhills for the knee.
    var avoidsDownhills: Bool { self == .knee }

    /// AD-13d, FB-4n: the cadence cue is offered for the knee and shin.
    var offersCadenceCue: Bool { self == .knee || self == .shin }
}

/// Where the runner made the report (AD-13).
enum InjuryOrigin: String, Codable, CaseIterable {
    case planScreen
    case runSummary
    case morningCheck
    case lifeHappens
    case whatHappened
    case missedRuns
    case dipCheck
    case rampDrops
    case stopLine
}

/// A report's state: open until it clears; a cleared Mild report waits a week for its follow-up.
enum InjuryStatus: Codable, Hashable {
    case open
    /// Mild only: "Cleared" was answered on this date; the one-week follow-up is due.
    case cleared(on: Date)
    case closed(on: Date)

    var isOpen: Bool {
        if case .open = self { return true }
        return false
    }

    var isClosed: Bool {
        if case .closed = self { return true }
        return false
    }
}

/// "Are you medically cleared to keep training?" (AD-13b)
enum ClearanceAnswer: String, Codable, CaseIterable {
    case yes
    case no
    case notSure

    var name: String {
        switch self {
        case .yes: "Yes"
        case .no: "No"
        case .notSure: "Not sure"
        }
    }
}

/// The Mild weekly check: "How's your {area}?" (AD-13a)
enum MildCheckAnswer: String, Codable, CaseIterable {
    case cleared
    case stillThere
    case worse

    var name: String {
        switch self {
        case .cleared: "Cleared"
        case .stillThere: "Still there, but fading within 30 minutes after runs"
        case .worse: "Worse, or lasting longer after runs"
        }
    }
}

/// The Intense and Severe-return weekly check: "How's your {area} now?" (AD-13b, AD-14c)
enum RecoveryCheckAnswer: String, Codable, CaseIterable {
    case better
    case same
    case worse

    var name: String { rawValue.capitalized }
}

/// The one-week follow-up after a Mild report clears (AD-14a).
enum FollowUpAnswer: String, Codable, CaseIterable {
    case stillClear
    case itsBack

    var name: String {
        switch self {
        case .stillClear: "Yes"
        case .itsBack: "It's back"
        }
    }
}

/// The runner's choice after a suggestion (AD-13a, AD-13b).
enum InjurySuggestionChoice: String, Codable, CaseIterable {
    case repeatWeek
    case pausePlan
    case keepGoing
    case switchToIntense
}

/// The Intense recovery plan the runner shapes (AD-14b). Defaults: 1 week off, 2 weeks at 50%,
/// then +25 points a week back to 100%.
struct RecoveryPlanSettings: Codable, Hashable {
    /// Phase 1, no running: 0 weeks or more.
    var restWeeks: Int
    /// Phase 2's share of the pre-injury week: 10-90% in steps of 10.
    var reducedShare: Double
    /// Phase 2's length: 1 week or more.
    var reducedWeeks: Int
    /// Phase 3's step: +10 to +50 points in steps of 5, or nil for straight back to 100%.
    var rampStep: Double?
    /// Ramp weeks the runner chose to repeat, by their position in the ramp (0 is the first ramp week).
    var repeatedRampWeeks: [Int]

    init(restWeeks: Int = 1, reducedShare: Double = 0.5, reducedWeeks: Int = 2, rampStep: Double? = 0.25, repeatedRampWeeks: [Int] = []) {
        self.restWeeks = max(0, restWeeks)
        self.reducedShare = reducedShare
        self.reducedWeeks = max(1, reducedWeeks)
        self.rampStep = rampStep
        self.repeatedRampWeeks = repeatedRampWeeks
    }

    static let standard = RecoveryPlanSettings()

    static let shareRange = 0.1...0.9
    static let shareStep = 0.1
    static let rampRange = 0.10...0.50
    static let rampIncrement = 0.05
}

/// How the runner comes back after a Severe pause (AD-14c).
enum ReturnForm: String, Codable, CaseIterable {
    /// Easy jogging.
    case jogging
    /// Jog/walk sessions of 20-30 min: 2 min jog and 2 min walk, then 3 and 1.
    case jogWalk

    var name: String {
        switch self {
        case .jogging: "Easy jogging"
        case .jogWalk: "Jog/walk"
        }
    }
}

/// The Severe return the runner can shape (AD-14c).
struct ReturnSettings: Codable, Hashable {
    /// Return weeks: 1 or more, 2 by default.
    var weeks: Int
    var form: ReturnForm
    /// Share of the pre-injury week: 50% after a pause of 4 weeks or less, else 30%; 10-90%.
    var share: Double
    /// The ramp step after the return weeks: AD-10's step for the pause's gap tier, or nil for
    /// straight back to 100%.
    var rampStep: Double?

    init(weeks: Int = 2, form: ReturnForm, share: Double, rampStep: Double?) {
        self.weeks = max(1, weeks)
        self.form = form
        self.share = share
        self.rampStep = rampStep
    }
}

/// The values a report keeps through every level change (AD-13e, AD-14b).
struct InjuryBaseline: Codable, Hashable {
    var volumeUnit: VolumeUnit
    /// AD-10's reference: the mean of the last 3 uninterrupted weeks before the report.
    var weekVolume: Double
    /// The longest run in the 30 days before the report.
    var longRun: Load
    /// Mild: the report week's planned volume and long run, held until it clears (AD-13a).
    var heldVolume: Double?
    var heldLongRun: Load?
    /// The last dose of each Q type, for the 2/3 dose after Mild (AD-14a).
    var qualityDoses: [QualityDose]
    /// The ladder or walk-stage step at the report, for ladder runners (AD-13b, AD-18).
    var ladderStep: Int?
    /// Whether the runner ran 30 min non-stop before the injury (AD-14c's form choice).
    var ranThirtyMinutesNonStop: Bool

    init(
        volumeUnit: VolumeUnit,
        weekVolume: Double,
        longRun: Load,
        heldVolume: Double? = nil,
        heldLongRun: Load? = nil,
        qualityDoses: [QualityDose] = [],
        ladderStep: Int? = nil,
        ranThirtyMinutesNonStop: Bool = true
    ) {
        self.volumeUnit = volumeUnit
        self.weekVolume = weekVolume
        self.longRun = longRun
        self.heldVolume = heldVolume
        self.heldLongRun = heldLongRun
        self.qualityDoses = qualityDoses
        self.ladderStep = ladderStep
        self.ranThirtyMinutesNonStop = ranThirtyMinutesNonStop
    }
}

/// One entry in a report's history; reports keep everything (AD-13, Open questions storage).
enum InjuryEventKind: Codable, Hashable {
    case reported(InjuryLevel)
    case levelChanged(from: InjuryLevel, to: InjuryLevel, suggested: Bool)
    case clearance(ClearanceAnswer)
    case mildCheck(MildCheckAnswer)
    case recoveryCheck(RecoveryCheckAnswer)
    case ready(Bool)
    case followUp(FollowUpAnswer)
    case suggestion(InjurySuggestionChoice)
    case recoveryPlanSet(RecoveryPlanSettings)
    case returnSet(ReturnSettings)
    case weekAdded
    case physioSuggested
    case closed
}

struct InjuryEvent: Codable, Hashable {
    var date: Date
    var kind: InjuryEventKind
}

/// An injury the runner reported (AD-13). Open reports limit the plan by their level (HL-18).
struct InjuryReport: Codable, Hashable, Identifiable {
    var id: UUID
    var reportedAt: Date
    var origin: InjuryOrigin
    /// The run the report follows, if any.
    var runID: UUID?
    var level: InjuryLevel
    var area: InjuryArea?
    var status: InjuryStatus
    var baseline: InjuryBaseline

    /// Intense: the answer to the medical question. Until it's answered the plan pauses.
    var clearance: ClearanceAnswer?
    /// Intense: the recovery plan as set, and the day the runner started it (phase 1 starts then).
    var recoveryPlan: RecoveryPlanSettings?
    var recoveryStart: Date?

    /// Severe: the pause, the last run before it, and "Ready".
    var pauseStart: Date?
    var lastRunBeforePause: Date?
    var readyAt: Date?
    /// Severe: the return as set, and its first day.
    var returnPlan: ReturnSettings?
    var returnStart: Date?

    /// The first run back after an Intense or Severe report: the 12-week injury window starts here (TI-3c).
    var firstRunBack: Date?
    /// Ever Intense or Severe: keeps TI-3b's 12-month memory and risk points.
    var everIntenseOrSevere: Bool
    var physioSuggested: Bool
    var events: [InjuryEvent]

    init(
        id: UUID = UUID(),
        reportedAt: Date,
        origin: InjuryOrigin,
        runID: UUID? = nil,
        level: InjuryLevel,
        area: InjuryArea? = nil,
        baseline: InjuryBaseline
    ) {
        self.id = id
        self.reportedAt = reportedAt
        self.origin = origin
        self.runID = runID
        self.level = level
        self.area = area
        self.status = .open
        self.baseline = baseline
        self.everIntenseOrSevere = level >= .intense
        self.physioSuggested = false
        self.events = [InjuryEvent(date: reportedAt, kind: .reported(level))]
    }

    /// "your shin", or "your injury" with no area.
    var areaName: String { area.map { "your \($0.name)" } ?? "your injury" }

    /// The help text on the report screen.
    static let helpText = "Muscle soreness that starts hours after a new, longer, faster or downhill run and fades over 1-3 days is normal, not an injury."
}
