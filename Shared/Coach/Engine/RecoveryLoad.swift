//
//  RecoveryLoad.swift
//  Wind Run
//

import Foundation

/// RB-1's classes for a non-running or unplanned session, by RPE × minutes, never by wrist heart rate.
enum ActivityClass: String, Codable, Comparable {
    /// RPE ≤4 and under 90 min: no effect, any day.
    case light
    /// RPE 5, RPE 6 for under 20 min, or ≥90 min at RPE ≥4: its hours count toward F1.
    case moderate
    /// Heavy leg strength or plyometrics, HIIT or spin, team or court sport, or ≥20 min at RPE ≥6: 1 hard unit.
    case hard

    private var order: Int {
        switch self {
        case .light: 0
        case .moderate: 1
        case .hard: 2
        }
    }

    static func < (lhs: ActivityClass, rhs: ActivityClass) -> Bool { lhs.order < rhs.order }

    /// RB-1's classification.
    static func of(kind: ActivityKind, minutes: Double, effort: Int, heavy: Bool) -> ActivityClass {
        if kind == .legStrength && heavy { return .hard }
        if kind == .hiit || kind == .teamSport { return .hard }
        if effort >= 6 && minutes >= 20 { return .hard }
        if effort <= 4 && minutes < 90 { return .light }
        return .moderate
    }
}

extension OtherActivity {
    var activityClass: ActivityClass {
        ActivityClass.of(kind: kind, minutes: minutes, effort: effort, heavy: heavy)
    }

    /// Leg strength sessions need gaps before a Q, long run, test or race (RB-5).
    var isLegSession: Bool { kind == .legStrength }
}

extension OtherSession {
    var activityClass: ActivityClass {
        ActivityClass.of(kind: kind, minutes: minutes, effort: effort, heavy: heavy)
    }

    /// RPE × minutes, the load RB-6 compares week to week.
    var load: Double { Double(effort) * minutes }
}
