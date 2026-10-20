//
//  CoachPlan.swift
//  Wind Run
//

import Foundation
import OSLog
import SwiftData

enum CoachPlanStatus: String, Codable {
    case active
    /// On hold, for example after a severe injury, until the runner is ready again.
    case paused
    case complete
    case stopped
}

/// A coach plan toward one goal.
///
/// The coach engine keeps everything it knows about the plan in one state value, stored here as
/// JSON: the runner's answers, check-ins, injury reports and the weeks ahead. The weeks and
/// sessions below are a copy of the planned weeks for showing on screen and linking runs to.
/// A few fields are copied out of the state too, so lists can show a plan without decoding it.
@Model
final class CoachPlan {
    /// The engine's goal flavor, as its raw value.
    var flavorValue: String = ""
    var statusValue: CoachPlanStatus = CoachPlanStatus.active
    var startDateValue: Date = Date.now
    /// Race day, for event plans.
    var eventDateValue: Date?
    /// The distance the plan works toward, in meters.
    var goalDistanceMetersValue: Double?
    /// The version of the coach rules that last wrote the state.
    var rulesVersionValue: String = ""
    /// The engine's state, as JSON. It grows with every check-in, so it's stored outside the row.
    @Attribute(.externalStorage)
    var stateDataValue: Data?
    var updatedDateValue: Date = Date.now

    // Optional because iCloud sync requires it.
    @Relationship(deleteRule: .cascade, inverse: \CoachWeek.planValue)
    var weeksValue: [CoachWeek]? = []

    init(
        flavor: String,
        startDate: Date = .now,
        eventDate: Date? = nil,
        goalDistanceMeters: Double? = nil
    ) {
        self.flavorValue = flavor
        self.startDateValue = startDate
        self.eventDateValue = eventDate
        self.goalDistanceMetersValue = goalDistanceMeters
    }
}

extension CoachPlan {
    var flavor: String { flavorValue }
    var status: CoachPlanStatus { statusValue }
    var startDate: Date { startDateValue }
    var eventDate: Date? { eventDateValue }
    var goalDistanceMeters: Double? { goalDistanceMetersValue }
    var rulesVersion: String { rulesVersionValue }
    var stateData: Data? { stateDataValue }
    var updatedDate: Date { updatedDateValue }

    var weeks: [CoachWeek] {
        (weeksValue ?? []).sorted { $0.order < $1.order }
    }

    func week(at index: Int) -> CoachWeek? {
        (weeksValue ?? []).first { $0.order == index }
    }

    /// Whole weeks from the start to race day, or nil for plans without an event.
    var weeksUntilEvent: Int? {
        guard let eventDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: startDate, to: eventDate).day ?? 0
        return days / 7
    }

    /// Stores the engine's latest state, with the rules version that wrote it.
    func saveState(_ data: Data, rulesVersion: String, at date: Date = .now) {
        stateDataValue = data
        rulesVersionValue = rulesVersion
        updatedDateValue = date
    }

    func setFlavor(_ flavor: String) {
        guard flavorValue != flavor else { return }
        flavorValue = flavor
    }

    /// Copies the fields lists show out of the engine's state.
    func updateSummary(
        status: CoachPlanStatus,
        startDate: Date,
        eventDate: Date?,
        goalDistanceMeters: Double?
    ) {
        statusValue = status
        startDateValue = startDate
        eventDateValue = eventDate
        goalDistanceMetersValue = goalDistanceMeters
    }

    /// Adds the copy of an engine week.
    @discardableResult
    func addWeek(order: Int) -> CoachWeek {
        let week = CoachWeek(order: order)
        weeksValue = (weeksValue ?? []) + [week]
        return week
    }

    @discardableResult
    func addWeek() -> CoachWeek {
        addWeek(order: (weeks.last?.order ?? -1) + 1)
    }

    func removeWeek(_ week: CoachWeek) {
        weeksValue?.removeAll { $0 === week }
    }

    func stop() {
        guard status == .active || status == .paused else {
            Logger.coach.warning("Can only stop a current coach plan.")
            return
        }
        statusValue = .stopped
    }

    func complete() {
        guard status == .active || status == .paused else {
            Logger.coach.warning("Can only complete a current coach plan.")
            return
        }
        statusValue = .complete
    }
}

extension CoachPlan: StatusProviding {
    /// A paused plan is still the runner's current plan.
    var isActive: Bool { status == .active || status == .paused }
}
