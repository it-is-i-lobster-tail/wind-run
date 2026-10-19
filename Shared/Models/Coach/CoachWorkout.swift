//
//  CoachWorkout.swift
//  Wind Run
//

import Foundation
import OSLog
import SwiftData

/// One planned session in a coach week, copied from the engine's plan for showing on screen and
/// for linking the run that does it.
@Model
final class CoachWorkout {
    /// The engine session this copies. Runs are linked through it.
    var sessionIDValue: UUID?
    var orderValue: Int = 0
    /// Days after the start of its week, 0...6.
    var dayOffsetValue: Int = 0
    var dateValue: Date?
    /// The engine's session kind, as its raw value.
    var kindValue: String = ""
    var titleValue: String = ""
    /// How the session goes, such as "10 min easy, 5 × 3 min hard with 2 min jogs, 10 min easy".
    var detailValue: String = ""
    var notesValue: String = ""
    var targetMetersValue: Double?
    /// Planned time, warm up and cool down included, in seconds.
    var targetSecondsValue: Double?
    /// The pace range to aim for, in seconds per kilometer: the faster end, then the slower end.
    var paceFastValue: Double?
    var paceSlowValue: Double?
    /// Effort out of 10 the session should feel like.
    var effortLowValue: Int?
    var effortHighValue: Int?
    /// A run-walk ratio, such as "4 min run, 1 min walk".
    var runWalkValue: String?
    var isKeySessionValue: Bool = false
    var isQualityValue: Bool = false
    /// Where the engine says the session stands, as its raw value.
    var statusValue: String = ""

    /// The structure for a session made of steps. Plans are shared, so deleting this session keeps it.
    /// The inverse is `IntervalPlan.coachWorkoutsValue`.
    @Relationship(deleteRule: .nullify)
    var intervalPlanValue: IntervalPlan?

    // Optional because iCloud sync requires it.
    @Relationship(deleteRule: .nullify, inverse: \Run.coachWorkoutValue)
    var runsValue: [Run]? = []

    var weekValue: CoachWeek?

    init(sessionID: UUID? = nil, kind: String, dayOffset: Int, order: Int = 0) {
        self.sessionIDValue = sessionID
        self.kindValue = kind
        self.dayOffsetValue = min(max(dayOffset, 0), 6)
        self.orderValue = order
    }
}

/// What a session asks for, as the screens show it.
struct CoachWorkoutTarget: Equatable {
    var title: String
    var detail: String
    var notes: String
    var meters: Double?
    var seconds: TimeInterval?
    /// Seconds per kilometer, the faster end first.
    var pace: ClosedRange<TimeInterval>?
    var effort: ClosedRange<Int>?
    var runWalk: String?
    var isKeySession: Bool
    var isQuality: Bool
}

extension CoachWorkout {
    var sessionID: UUID? { sessionIDValue }
    var order: Int { orderValue }
    var dayOffset: Int { dayOffsetValue }
    var date: Date? { dateValue }
    var kind: String { kindValue }
    var title: String { titleValue }
    var detail: String { detailValue }
    var notes: String { notesValue }
    var targetMeters: Double? { targetMetersValue }
    var targetSeconds: TimeInterval? { targetSecondsValue }
    var runWalk: String? { runWalkValue }
    var isKeySession: Bool { isKeySessionValue }
    var isQuality: Bool { isQualityValue }
    var status: String { statusValue }
    var intervalPlan: IntervalPlan? { intervalPlanValue }
    var week: CoachWeek? { weekValue }
    var runs: [Run] { runsValue ?? [] }

    /// The pace range to aim for, fastest first, in seconds per kilometer.
    var paceRange: ClosedRange<TimeInterval>? {
        guard let fast = paceFastValue, let slow = paceSlowValue, fast > 0, slow >= fast else { return nil }
        return fast...slow
    }

    var effortRange: ClosedRange<Int>? {
        guard let low = effortLowValue, let high = effortHighValue, low <= high else { return nil }
        return low...high
    }

    /// Done once a finished run is linked to it.
    var isDone: Bool {
        (runsValue ?? []).contains { $0.status == .complete }
    }

    /// The calendar day this session falls on.
    var scheduledDate: Date? {
        if let dateValue { return dateValue }
        guard let week = weekValue, let plan = week.plan else { return nil }
        return Calendar.current.date(byAdding: .day, value: week.order * 7 + dayOffset, to: plan.startDate)
    }

    var target: CoachWorkoutTarget {
        CoachWorkoutTarget(
            title: title,
            detail: detail,
            notes: notes,
            meters: targetMeters,
            seconds: targetSeconds,
            pace: paceRange,
            effort: effortRange,
            runWalk: runWalk,
            isKeySession: isKeySession,
            isQuality: isQuality
        )
    }

    /// Updates the copy from the engine's session.
    func update(kind: String, dayOffset: Int, date: Date?, order: Int, status: String, target: CoachWorkoutTarget) {
        kindValue = kind
        dayOffsetValue = min(max(dayOffset, 0), 6)
        dateValue = date
        orderValue = order
        statusValue = status
        titleValue = target.title
        detailValue = target.detail
        notesValue = target.notes
        targetMetersValue = target.meters
        targetSecondsValue = target.seconds
        paceFastValue = target.pace?.lowerBound
        paceSlowValue = target.pace?.upperBound
        effortLowValue = target.effort?.lowerBound
        effortHighValue = target.effort?.upperBound
        runWalkValue = target.runWalk
        isKeySessionValue = target.isKeySession
        isQualityValue = target.isQuality
    }

    /// Sets or clears the step structure for a session that can be guided.
    func setIntervalPlan(_ plan: IntervalPlan?) {
        intervalPlanValue = plan
    }

    /// Links a finished run to this session.
    func link(_ run: Run) {
        guard run.status == .complete else {
            Logger.coach.warning("Only a finished run can be linked to a coach session.")
            return
        }
        if run.coachWorkoutValue !== self {
            run.coachWorkoutValue = self
        }
    }
}
