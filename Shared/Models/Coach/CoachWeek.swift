//
//  CoachWeek.swift
//  Wind Run
//

import Foundation
import SwiftData

/// One week of a coach plan, copied from the engine's plan for showing on screen.
@Model
final class CoachWeek {
    /// 0-based week number within the plan, the engine's week index.
    var orderValue: Int = 0
    /// The engine's week type, as its raw value.
    var kindValue: String = ""
    /// The week's name, such as "Easy week".
    var titleValue: String = ""
    /// Why the week looks the way it does, in the coach's words.
    var becauseValue: String = ""
    var startDateValue: Date?
    /// Planned volume, as distance or time depending on the plan's unit.
    var plannedMetersValue: Double?
    var plannedSecondsValue: Double?
    var longRunMetersValue: Double?
    var longRunSecondsValue: Double?
    /// How the week went, as the engine's raw outcome, once it's over.
    var outcomeValue: String?

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
    var kind: String { kindValue }
    var title: String { titleValue }
    var because: String { becauseValue }
    var startDate: Date? { startDateValue }
    var plannedMeters: Double? { plannedMetersValue }
    var plannedSeconds: Double? { plannedSecondsValue }
    var longRunMeters: Double? { longRunMetersValue }
    var longRunSeconds: Double? { longRunSecondsValue }
    var outcome: String? { outcomeValue }

    var workouts: [CoachWorkout] {
        (workoutsValue ?? []).sorted { ($0.dayOffset, $0.order) < ($1.dayOffset, $1.order) }
    }

    /// The session copied from the engine session with this id.
    func workout(withSessionID id: UUID) -> CoachWorkout? {
        (workoutsValue ?? []).first { $0.sessionID == id }
    }

    /// Updates the copy from the engine's week.
    func update(
        kind: String,
        title: String,
        because: String,
        startDate: Date?,
        plannedMeters: Double?,
        plannedSeconds: Double?,
        longRunMeters: Double?,
        longRunSeconds: Double?,
        outcome: String?
    ) {
        kindValue = kind
        titleValue = title
        becauseValue = because
        startDateValue = startDate
        plannedMetersValue = plannedMeters
        plannedSecondsValue = plannedSeconds
        longRunMetersValue = longRunMeters
        longRunSecondsValue = longRunSeconds
        outcomeValue = outcome
    }

    @discardableResult
    func addWorkout(sessionID: UUID? = nil, kind: String, dayOffset: Int) -> CoachWorkout {
        let workout = CoachWorkout(
            sessionID: sessionID,
            kind: kind,
            dayOffset: dayOffset,
            order: ((workoutsValue ?? []).map(\.order).max() ?? -1) + 1
        )
        workoutsValue = (workoutsValue ?? []) + [workout]
        return workout
    }

    func removeWorkout(_ workout: CoachWorkout) {
        workoutsValue?.removeAll { $0 === workout }
    }
}
