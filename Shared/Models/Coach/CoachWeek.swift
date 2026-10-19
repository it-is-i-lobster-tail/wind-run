//
//  CoachWeek.swift
//  Wind Run
//

import Foundation
import SwiftData

/// One week of a coach plan.
@Model
final class CoachWeek {
    /// 0-based week number within the plan.
    var orderValue: Int = 0

    // Optional because iCloud sync requires it.
    @Relationship(deleteRule: .cascade, inverse: \CoachWorkout.weekValue)
    var workoutsValue: [CoachWorkout]? = []

    var planValue: CoachPlan?

    init(order: Int) {
        self.orderValue = order
    }
}

extension CoachWeek {
    var order: Int { orderValue }
    var plan: CoachPlan? { planValue }

    var workouts: [CoachWorkout] {
        (workoutsValue ?? []).sorted { $0.order < $1.order }
    }

    /// Planned distance for the week, from the sessions that set one.
    var plannedMeters: Double {
        (workoutsValue ?? []).reduce(0) { $0 + ($1.targetMeters ?? 0) }
    }

    @discardableResult
    func addWorkout(_ kind: CoachWorkoutKind, dayOffset: Int, targetMeters: Double? = nil) -> CoachWorkout {
        let workout = CoachWorkout(
            kind: kind,
            dayOffset: dayOffset,
            targetMeters: targetMeters,
            order: (workouts.last?.order ?? -1) + 1
        )
        workoutsValue = (workoutsValue ?? []) + [workout]
        return workout
    }
}
