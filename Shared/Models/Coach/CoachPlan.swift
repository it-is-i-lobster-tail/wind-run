//
//  CoachPlan.swift
//  Wind Run
//

import Foundation
import OSLog
import SwiftData

/// What the coach is building toward.
enum CoachGoal: String, Codable, CaseIterable {
    /// Grow weekly distance gradually.
    case buildDistance
    /// Get faster with regular interval and tempo sessions.
    case speedWork
    /// Be ready for a race of a given distance on a given date.
    case event

    var name: String {
        switch self {
        case .buildDistance: "Build distance"
        case .speedWork: "Speed work"
        case .event: "Train for an event"
        }
    }

    var summary: String {
        switch self {
        case .buildDistance: "Add a little more each week, with easy weeks to recover."
        case .speedWork: "Regular intervals and tempo runs to lift your pace."
        case .event: "A plan that peaks on race day, from 5K to the marathon."
        }
    }

    var systemImage: String {
        switch self {
        case .buildDistance: "chart.line.uptrend.xyaxis"
        case .speedWork: "hare"
        case .event: "flag.checkered"
        }
    }
}

enum CoachPlanStatus: String, Codable {
    case active
    case complete
    case stopped
}

/// Common race distances, in meters.
enum EventDistance: Double, Codable, CaseIterable {
    case fiveK = 5_000
    case tenK = 10_000
    case halfMarathon = 21_097.5
    case marathon = 42_195

    var name: String {
        switch self {
        case .fiveK: "5K"
        case .tenK: "10K"
        case .halfMarathon: "Half marathon"
        case .marathon: "Marathon"
        }
    }
}

/// A coach plan: weeks of sessions toward one goal.
@Model
final class CoachPlan {
    static let runsPerWeekRange = 2...6
    static let weekRange = 1...26

    var goalValue: CoachGoal = CoachGoal.buildDistance
    var statusValue: CoachPlanStatus = CoachPlanStatus.active
    var startDateValue: Date = Date.now
    /// Race day, for event plans.
    var eventDateValue: Date?
    /// Race distance in meters, for event plans.
    var eventDistanceMetersValue: Double?
    /// What the runner covers in a typical week today, in meters. The plan builds from here.
    var baselineWeeklyMetersValue: Double = 0
    var runsPerWeekValue: Int = 3

    @Relationship(deleteRule: .cascade, inverse: \CoachWeek.planValue)
    var weeksValue: [CoachWeek] = []

    init(
        goal: CoachGoal,
        startDate: Date = .now,
        baselineWeeklyMeters: Double,
        runsPerWeek: Int,
        eventDate: Date? = nil,
        eventDistance: EventDistance? = nil
    ) {
        self.goalValue = goal
        self.startDateValue = startDate
        self.baselineWeeklyMetersValue = max(0, baselineWeeklyMeters)
        self.runsPerWeekValue = min(max(runsPerWeek, Self.runsPerWeekRange.lowerBound), Self.runsPerWeekRange.upperBound)
        self.eventDateValue = eventDate
        self.eventDistanceMetersValue = eventDistance?.rawValue
    }
}

extension CoachPlan {
    var goal: CoachGoal { goalValue }
    var status: CoachPlanStatus { statusValue }
    var startDate: Date { startDateValue }
    var eventDate: Date? { eventDateValue }
    var eventDistance: EventDistance? { eventDistanceMetersValue.flatMap(EventDistance.init(rawValue:)) }
    var baselineWeeklyMeters: Double { baselineWeeklyMetersValue }
    var runsPerWeek: Int { runsPerWeekValue }

    var weeks: [CoachWeek] {
        weeksValue.sorted { $0.order < $1.order }
    }

    /// Whole weeks from the start to race day, or nil for plans without an event.
    var weeksUntilEvent: Int? {
        guard goal == .event, let eventDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: startDate, to: eventDate).day ?? 0
        return days / 7
    }

    /// An event plan needs a race at least a week out; the others are always ready.
    var isValid: Bool {
        switch goal {
        case .event:
            guard eventDistance != nil, let weeksUntilEvent else { return false }
            return Self.weekRange.contains(weeksUntilEvent)
        case .buildDistance, .speedWork:
            return true
        }
    }

    @discardableResult
    func addWeek() -> CoachWeek {
        let week = CoachWeek(order: (weeks.last?.order ?? -1) + 1)
        weeksValue.append(week)
        return week
    }

    func complete() {
        guard status == .active else {
            Logger.coach.warning("Can only complete an active coach plan.")
            return
        }
        statusValue = .complete
    }

    func stop() {
        guard status == .active else {
            Logger.coach.warning("Can only stop an active coach plan.")
            return
        }
        statusValue = .stopped
    }
}

extension CoachPlan: StatusProviding {
    var isActive: Bool { status == .active }
}
