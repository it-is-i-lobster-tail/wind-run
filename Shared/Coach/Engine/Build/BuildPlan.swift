//
//  BuildPlan.swift
//  Wind Run
//

import Foundation

/// A finished run as the coach reads it: when, how far and how much it climbed.
struct CoachRun: Codable, Hashable, Identifiable {
    var id: UUID
    var start: Date
    var meters: Double
    /// Climb in meters, 0 when the run has no heights.
    var climb: Double
    /// The planned run the runner started it from, if any.
    var plannedSessionID: UUID?

    init(id: UUID = UUID(), start: Date, meters: Double, climb: Double = 0, plannedSessionID: UUID? = nil) {
        self.id = id
        self.start = start
        self.meters = meters
        self.climb = climb
        self.plannedSessionID = plannedSessionID
    }
}

/// Where a planned run stands.
enum BuildSessionStatus: Codable, Hashable {
    case planned
    case done(runID: UUID)
    case missed

    var isPlanned: Bool { self == .planned }

    var runID: UUID? {
        if case .done(let id) = self { return id }
        return nil
    }
}

/// One planned run.
struct BuildSession: Codable, Hashable, Identifiable {
    var id: UUID
    /// The day, at its start.
    var date: Date
    var kind: BuildSessionKind
    /// What's planned now: what's left of the week shared over the runs left.
    var target: WeekVolume
    var status: BuildSessionStatus

    init(id: UUID = UUID(), date: Date, kind: BuildSessionKind, target: WeekVolume, status: BuildSessionStatus = .planned) {
        self.id = id
        self.date = date
        self.kind = kind
        self.target = target
        self.status = status
    }
}

/// One plan week.
struct BuildWeek: Codable, Hashable, Identifiable {
    var number: Int
    var start: Date
    var kind: BuildWeekKind
    var target: WeekVolume
    /// The base before this week was planned, so the week can be planned again (a change of easy weeks).
    var baseBefore: WeekVolume
    var holdBefore: Bool
    var sessions: [BuildSession]
    /// What was run in the week, filled in as runs come in.
    var done: WeekVolume
    var closed: Bool

    var id: Int { number }

    /// The week's planned share that was run, 1 when nothing was planned.
    var doneShare: Double {
        target.meters > 0 ? done.meters / target.meters : 1
    }
}

/// An injury the runner reported. The coach never diagnoses: the level decides what the plan does.
struct BuildInjury: Codable, Hashable, Identifiable {
    var id: UUID
    var reportedAt: Date
    var level: InjuryLevel
    var area: InjuryArea?
    var runID: UUID?
    /// Intense: "Are you medically cleared to keep training?"
    var clearance: ClearanceAnswer?
    /// The weeks back, once cleared (Intense) or ready (Severe), and the plan week they start in.
    var recovery: RecoverySettings?
    var recoveryStartWeek: Int?
    /// The last building week when it was reported, which the recovery weeks are shares of.
    var baseAtReport: WeekVolume
    var closedAt: Date?

    var isOpen: Bool { closedAt == nil }

    /// No running until the runner is cleared (Intense) or ready (Severe).
    var pauses: Bool {
        guard isOpen, recoveryStartWeek == nil else { return false }
        return level != .mild
    }
}

/// The weeks back after an Intense or Severe injury, which the runner can change (AD-14b, AD-14c).
struct RecoverySettings: Codable, Hashable {
    /// Weeks with no running.
    var restWeeks: Int
    /// Then weeks at a share of the week before the injury.
    var reducedWeeks: Int
    var reducedShare: Double

    /// Intense, once cleared: 1 week off, then 2 weeks at 50%.
    static let intense = RecoverySettings(restWeeks: 1, reducedWeeks: 2, reducedShare: 0.5)
    /// Severe, once ready: 2 weeks at 50%.
    static let severe = RecoverySettings(restWeeks: 0, reducedWeeks: 2, reducedShare: 0.5)

    static let shareRange = 0.1 ... 0.9
    static let shareStep = 0.1

    init(restWeeks: Int, reducedWeeks: Int, reducedShare: Double) {
        self.restWeeks = max(0, restWeeks)
        self.reducedWeeks = max(1, reducedWeeks)
        self.reducedShare = (Double(Int((reducedShare * 10).rounded())) / 10).clamped(to: Self.shareRange)
    }

    var weeks: Int { restWeeks + reducedWeeks }

    /// The share of the pre-injury week planned in recovery week `index` (0 is the first).
    func share(at index: Int) -> Double {
        index < restWeeks ? 0 : reducedShare
    }
}

enum BuildPlanStatus: Codable, Hashable {
    case active
    case complete(on: Date)
    case stopped(on: Date)

    var isCurrent: Bool { self == .active }
}

/// Everything the coach keeps about a Build Distance plan, stored as JSON with the plan.
struct BuildPlanState: Codable, Hashable {
    static let currentVersion = 1

    var version: Int
    var settings: BuildSettings
    var createdAt: Date
    var planCalendar: PlanCalendar
    var status: BuildPlanStatus
    /// The last building week, which the next one grows from.
    var base: WeekVolume
    /// The next building week holds the base instead of growing: the last one came up short.
    var holdNext: Bool
    /// Weeks in a row under half done.
    var lowWeeks: Int
    var weeks: [BuildWeek]
    var injuries: [BuildInjury]

    var openInjuries: [BuildInjury] { injuries.filter(\.isOpen) }

    var isPaused: Bool { injuries.contains(where: \.pauses) }

    var goalDate: Date { settings.goal.date }

    func week(_ number: Int) -> BuildWeek? { weeks.first { $0.number == number } }
}
