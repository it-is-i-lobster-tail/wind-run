//
//  Run.swift
//  Wind Run
//

import CoreLocation
import Foundation
import OSLog
import SwiftData

/// How a run was started: a plain run, an interval workout, or a coach session.
enum RunKind: String, Codable, CaseIterable {
    case free
    case intervals
    case coached

    var name: String {
        switch self {
        case .free: "Run"
        case .intervals: "Intervals"
        case .coached: "Coach"
        }
    }
}

enum RunStatus: String, Codable {
    case active
    case paused
    case complete
    case discarded
}

/// One recorded run, with its GPS route and the pauses taken along the way.
@Model
final class Run {
    var startDateValue: Date = Date.now
    var endDateValue: Date?
    var kindValue: RunKind = RunKind.free
    var statusValue: RunStatus = RunStatus.active
    /// Distance covered while running, in meters. Pauses don't add to it.
    var distanceMetersValue: Double = 0
    var notesValue: String = ""
    /// The Apple Health workout this run was saved as. Nil when it wasn't saved there.
    var healthWorkoutIDValue: UUID?

    @Relationship(deleteRule: .cascade, inverse: \RouteSample.runValue)
    var routeSamplesValue: [RouteSample] = []

    @Relationship(deleteRule: .cascade, inverse: \RunPause.runValue)
    var pausesValue: [RunPause] = []

    /// The interval workout this run followed, if any. Deleting the plan keeps the run.
    @Relationship(deleteRule: .nullify)
    var intervalPlanValue: IntervalPlan?

    /// The coach session this run fulfilled, if any.
    @Relationship(deleteRule: .nullify)
    var coachWorkoutValue: CoachWorkout?

    /// The newest fix, cached so recording doesn't re-sort the whole route every second.
    @Transient private var lastSample: RouteSample? = nil

    init(kind: RunKind = .free, startDate: Date = .now) {
        self.kindValue = kind
        self.startDateValue = startDate
        self.statusValue = .active
    }
}

// MARK: - Accessors

extension Run {
    var startDate: Date { startDateValue }
    var endDate: Date? { endDateValue }
    var kind: RunKind { kindValue }
    var status: RunStatus { statusValue }
    var distanceMeters: Double { distanceMetersValue }

    var notes: String {
        get { notesValue }
        set { notesValue = newValue }
    }

    var intervalPlan: IntervalPlan? { intervalPlanValue }
    var coachWorkout: CoachWorkout? { coachWorkoutValue }
    var healthWorkoutID: UUID? { healthWorkoutIDValue }

    /// The route in the order it was recorded.
    var route: [RouteSample] {
        routeSamplesValue.sorted { $0.timestamp < $1.timestamp }
    }

    var pauses: [RunPause] {
        pausesValue.sorted { $0.startDate < $1.startDate }
    }

    var isFinished: Bool {
        status == .complete || status == .discarded
    }

    /// Time spent running, leaving out pauses.
    func activeDuration(at now: Date = .now) -> TimeInterval {
        let end = endDate ?? now
        let total = end.timeIntervalSince(startDate)
        let paused = pausesValue.reduce(0) { $0 + $1.duration(at: end) }
        return max(0, total - paused)
    }

    /// Seconds per kilometer, or nil until there's enough distance to say.
    func pace(at now: Date = .now) -> TimeInterval? {
        guard distanceMeters >= 10 else { return nil }
        return activeDuration(at: now) / (distanceMeters / 1000)
    }
}

// MARK: - Lifecycle

extension Run {
    func pause(at date: Date = .now) {
        guard status == .active else {
            Logger.run.warning("Can only pause an active run.")
            return
        }
        statusValue = .paused
        pausesValue.append(RunPause(startDate: date))
    }

    func resume(at date: Date = .now) {
        guard status == .paused else {
            Logger.run.warning("Can only resume a paused run.")
            return
        }
        pausesValue.first { $0.endDate == nil }?.end(at: date)
        statusValue = .active
    }

    func finish(at date: Date = .now) {
        guard !isFinished else {
            Logger.run.warning("Run is already finished.")
            return
        }
        pausesValue.first { $0.endDate == nil }?.end(at: date)
        endDateValue = date
        statusValue = .complete
        Logger.run.debug("Finished run")
    }

    func discard(at date: Date = .now) {
        guard !isFinished else {
            Logger.run.warning("Run is already finished.")
            return
        }
        endDateValue = date
        statusValue = .discarded
    }

    /// Remembers the Health workout a finished run was saved as.
    func markSavedToHealth(as workoutID: UUID) {
        guard status == .complete else {
            Logger.run.warning("Only a completed run can be saved to Health.")
            return
        }
        healthWorkoutIDValue = workoutID
    }

    /// Adds a GPS fix. Distance only grows while the run is active, so a paused walk
    /// back to the start doesn't count.
    func record(_ sample: RouteSample) {
        guard !isFinished else {
            Logger.run.warning("Can't add route samples to a finished run.")
            return
        }
        let last = lastSample ?? routeSamplesValue.max { $0.timestamp < $1.timestamp }
        if let last, sample.timestamp <= last.timestamp {
            Logger.run.debug("Ignoring an out-of-order route sample.")
            return
        }
        if status == .active, let last {
            distanceMetersValue += sample.location.distance(from: last.location)
        }
        routeSamplesValue.append(sample)
        lastSample = sample
    }
}
