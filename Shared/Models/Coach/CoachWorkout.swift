//
//  CoachWorkout.swift
//  Wind Run
//

import Foundation
import SwiftData

enum CoachWorkoutKind: String, Codable, CaseIterable {
    case easy
    case long
    case tempo
    case intervals
    case race

    var name: String {
        switch self {
        case .easy: "Easy run"
        case .long: "Long run"
        case .tempo: "Tempo run"
        case .intervals: "Intervals"
        case .race: "Race day"
        }
    }
}

/// One planned session in a coach week.
@Model
final class CoachWorkout {
    var orderValue: Int = 0
    /// Days after the start of its week, 0...6.
    var dayOffsetValue: Int = 0
    var kindValue: CoachWorkoutKind = CoachWorkoutKind.easy
    var targetMetersValue: Double?
    var notesValue: String = ""

    /// The structure for an interval session. Plans are shared, so deleting this session keeps it.
    /// The inverse is `IntervalPlan.coachWorkoutsValue`.
    @Relationship(deleteRule: .nullify)
    var intervalPlanValue: IntervalPlan?

    // Optional because iCloud sync requires it.
    @Relationship(deleteRule: .nullify, inverse: \Run.coachWorkoutValue)
    var runsValue: [Run]? = []

    var weekValue: CoachWeek?

    init(kind: CoachWorkoutKind, dayOffset: Int, targetMeters: Double? = nil, order: Int = 0) {
        self.kindValue = kind
        self.dayOffsetValue = min(max(dayOffset, 0), 6)
        self.targetMetersValue = targetMeters
        self.orderValue = order
    }
}

extension CoachWorkout {
    var order: Int { orderValue }
    var dayOffset: Int { dayOffsetValue }
    var kind: CoachWorkoutKind { kindValue }
    var targetMeters: Double? { targetMetersValue }
    var intervalPlan: IntervalPlan? { intervalPlanValue }

    /// Done once a finished run is linked to it.
    var isDone: Bool {
        (runsValue ?? []).contains { $0.status == .complete }
    }

    /// The calendar day this session falls on.
    var scheduledDate: Date? {
        guard let week = weekValue, let plan = week.plan else { return nil }
        return Calendar.current.date(byAdding: .day, value: week.order * 7 + dayOffset, to: plan.startDate)
    }
}
