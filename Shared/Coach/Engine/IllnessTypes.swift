//
//  IllnessTypes.swift
//  Wind Run
//

import Foundation

/// AD-12's one question: "Just a head cold, or a fever or anything below the neck?"
enum IllnessKind: String, Codable, CaseIterable {
    /// Above the neck, no fever.
    case headCold
    /// A fever or anything below the neck (chest, stomach, aches all over): no running (HL-19).
    case feverOrBelowNeck

    var name: String {
        switch self {
        case .headCold: "Just a head cold"
        case .feverOrBelowNeck: "A fever or anything below the neck"
        }
    }

    static let question = "Just a head cold (above the neck, no fever), or a fever or anything below the neck (chest, stomach, aches all over)?"
}

/// The return stages after a fever or below-the-neck illness (AD-12).
enum IllnessStage: Int, Codable, Comparable {
    /// Head cold: easy runs no longer than usual, no Q, test or long-run step.
    case headCold
    /// 1. Rest: no running until "Ready" with 2 symptom-free days.
    case rest
    /// 2. One run of 10-20 min at RPE ≤3, then a next-day check.
    case firstRun
    /// 3. Easy runs only, load may rise; no Q, long run or test.
    case easy
    /// 4. The AD-10 ramp for the days off.
    case backToPlan
    case over

    static func < (lhs: IllnessStage, rhs: IllnessStage) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// An illness the runner reported (AD-12). Illness is user-reported only.
struct IllnessEpisode: Codable, Hashable, Identifiable {
    var id: UUID
    var reportedAt: Date
    /// Nil until the question is answered: head-cold rules apply meanwhile (AD-17).
    var kind: IllnessKind?
    /// Bed-bound or feverish illness moves the gap tier up (AD-10).
    var bedBound: Bool
    var stage: IllnessStage
    var stageStartedAt: Date
    /// Head cold: the next "Has it gone?" (every 3 days).
    var nextCheck: Date?
    /// The first symptom-free day counted from "Ready".
    var symptomFreeSince: Date?
    var firstRunAt: Date?
    var easyRunsSinceFirst: Int
    var relapses: Int
    var endedAt: Date?

    init(id: UUID = UUID(), reportedAt: Date, kind: IllnessKind? = nil, bedBound: Bool = false) {
        self.id = id
        self.reportedAt = reportedAt
        self.kind = kind
        self.bedBound = bedBound
        self.stage = kind == .feverOrBelowNeck ? .rest : .headCold
        self.stageStartedAt = reportedAt
        self.easyRunsSinceFirst = 0
        self.relapses = 0
    }

    var isActive: Bool { endedAt == nil }

    /// Fever or below the neck before the back-to-plan stage: no planned running (HL-19).
    var stopsRunning: Bool { isActive && stage == .rest }
}

/// "Life happens" (AD-11).
enum LifeEventKind: String, Codable, CaseIterable {
    case busy
    case travelling
    case sick
    case injured
    case holiday
    /// A move, a bereavement, a new baby, exams: each week is HOLD with ≤2 hard days (RB-7).
    case bigLifeChange

    var name: String {
        switch self {
        case .busy: "Busy"
        case .travelling: "Travelling"
        case .sick: "Sick"
        case .injured: "Injured"
        case .holiday: "Holiday"
        case .bigLifeChange: "Big life change"
        }
    }
}

/// "For about how long?" (AD-11)
enum LifeEventLength: String, Codable, CaseIterable {
    case oneWeek
    case twoToThreeWeeks
    case longer
    case notSure

    var name: String {
        switch self {
        case .oneWeek: "1 week"
        case .twoToThreeWeeks: "2-3 weeks"
        case .longer: "Longer"
        case .notSure: "Not sure"
        }
    }
}

/// A "Life happens" entry: it ends on its end date or at "Back to normal".
struct LifeEvent: Codable, Hashable, Identifiable {
    var id: UUID
    var kind: LifeEventKind
    var start: Date
    var length: LifeEventLength?
    var endedAt: Date?
    /// Travel: time zones crossed, direction and whether a flight is over 6 hours (AD-15).
    var timeZones: Int?
    var eastward: Bool?
    var longHaulFlight: Bool?

    init(id: UUID = UUID(), kind: LifeEventKind, start: Date, length: LifeEventLength? = nil) {
        self.id = id
        self.kind = kind
        self.start = start
        self.length = length
    }

    /// The expected end from the length answer; "not sure" and "longer" have none.
    func expectedEnd(calendar: Calendar) -> Date? {
        switch length {
        case .oneWeek: calendar.date(byAdding: .day, value: 7, to: start)
        case .twoToThreeWeeks: calendar.date(byAdding: .day, value: 21, to: start)
        case .longer, .notSure, nil: nil
        }
    }

    func isActive(on date: Date, calendar: Calendar) -> Bool {
        guard date >= start else { return false }
        if let endedAt { return date < endedAt }
        if let end = expectedEnd(calendar: calendar) { return date < end }
        return true
    }
}

/// Heat illness and the heat-risk window (AD-16).
struct HeatState: Codable, Hashable {
    /// Each "felt unwell in the heat" report.
    var illnessDates: [Date]
    /// Easy runs of ≤30 min at T0 or indoors still owed after the last heat illness.
    var easyRunsLeft: Int
    /// High-risk for heat until this date (an illness report adds 10 days); a heat illness makes it permanent.
    var highRiskUntil: Date?

    init() {
        illnessDates = []
        easyRunsLeft = 0
    }

    /// A heat illness reported in the app makes the runner high-risk from then on (AD-16).
    var permanentlyHighRisk: Bool { !illnessDates.isEmpty }

    func isHighRisk(on date: Date) -> Bool {
        permanentlyHighRisk || (highRiskUntil.map { date < $0 } ?? false)
    }
}
