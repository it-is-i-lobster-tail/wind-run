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

/// One recorded run, with its GPS route, heart rate, and the pauses taken along the way.
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
    /// A stable id the coach refers to the run by.
    var runIDValue: UUID = UUID()
    /// The runner's answers after the run (how hard it felt and so on), as the coach's JSON.
    var checkInDataValue: Data?
    /// For a structured run, each step as it was actually run, as JSON.
    var stepLogDataValue: Data?
    /// Step counts from the run's workout session, for the coach's step-rate check, as JSON.
    var stepCountDataValue: Data?
    /// The barometer's climb and drop through the run, as JSON. Nil when it had no barometer.
    var altitudeDataValue: Data?
    /// Calories burned, in kilocalories, worked out when the run finished from its climb, pace and the
    /// runner's weight then. Nil when no weight was given.
    var activeCaloriesValue: Double?

    // To-many relationships are optional because iCloud sync requires it.
    @Relationship(deleteRule: .cascade, inverse: \RouteSample.runValue)
    var routeSamplesValue: [RouteSample]? = []

    @Relationship(deleteRule: .cascade, inverse: \RunPause.runValue)
    var pausesValue: [RunPause]? = []

    /// Empty unless heart rate was on for this run. Optional so iCloud sync can mirror it.
    @Relationship(deleteRule: .cascade, inverse: \HeartRateSample.runValue)
    var heartRateSamplesValue: [HeartRateSample]? = []

    /// The interval workout this run followed, if any. Deleting the plan keeps the run.
    @Relationship(deleteRule: .nullify)
    var intervalPlanValue: IntervalPlan?

    /// The coach session this run fulfilled, if any.
    @Relationship(deleteRule: .nullify)
    var coachWorkoutValue: CoachWorkout?

    /// The newest fix, cached so recording doesn't re-sort the whole route every second.
    @Transient private var lastSample: RouteSample? = nil
    @Transient private var lastHeartRateSample: HeartRateSample? = nil

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
    var runID: UUID { runIDValue }
    var checkInData: Data? { checkInDataValue }

    /// The route in the order it was recorded.
    var route: [RouteSample] {
        (routeSamplesValue ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    var pauses: [RunPause] {
        (pausesValue ?? []).sorted { $0.startDate < $1.startDate }
    }

    /// Heart rate readings in the order they were taken.
    var heartRateSamples: [HeartRateSample] {
        (heartRateSamplesValue ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    /// Heart rate is still climbing from near resting for the first minutes of a run, so the stats leave
    /// those out.
    static let heartRateSettlingTime: TimeInterval = 5 * 60

    /// Lowest, highest, mean and variance of the readings after the first five minutes of running, or of
    /// every reading when the run had none after that. Nil if there are none.
    var heartRateStats: HeartRateStats? {
        let timeline = heartRateTimeline
        let settled = timeline.filter { $0.activeTime >= Self.heartRateSettlingTime }
        return HeartRateStats((settled.isEmpty ? timeline : settled).map(\.beatsPerMinute))
    }

    /// Each reading against time spent running, for charting the whole run.
    var heartRateTimeline: [HeartRatePoint] {
        heartRateSamples.map { sample in
            HeartRatePoint(activeTime: activeTime(at: sample.timestamp), beatsPerMinute: sample.beatsPerMinute)
        }
    }

    /// When the run last recorded a GPS fix or heart rate reading, or nil if it never did.
    var lastRecordedDate: Date? {
        let lastFix = routeSamplesValue?.map(\.timestamp).max()
        let lastReading = heartRateSamplesValue?.map(\.timestamp).max()
        return [lastFix, lastReading].compactMap { $0 }.max()
    }

    var isFinished: Bool {
        status == .complete || status == .discarded
    }

    /// Time spent running, leaving out pauses.
    func activeDuration(at now: Date = .now) -> TimeInterval {
        activeTime(at: endDate ?? now)
    }

    /// Time spent running from the start up to `date`, leaving out the pauses before it.
    func activeTime(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSince(startDate) - pausedTime(at: date))
    }

    /// Time spent paused, by the runner or at a stop, up to `date`.
    func pausedTime(at date: Date) -> TimeInterval {
        (pausesValue ?? []).reduce(0) { $0 + $1.duration(at: date) }
    }

    /// Time spent paused in the whole run.
    func pausedDuration(at now: Date = .now) -> TimeInterval {
        pausedTime(at: endDate ?? now)
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
        pausesValue = (pausesValue ?? []) + [RunPause(startDate: date)]
    }

    func resume(at date: Date = .now) {
        guard status == .paused else {
            Logger.run.warning("Can only resume a paused run.")
            return
        }
        pausesValue?.first { $0.endDate == nil }?.end(at: date)
        statusValue = .active
    }

    func finish(at date: Date = .now) {
        guard !isFinished else {
            Logger.run.warning("Run is already finished.")
            return
        }
        pausesValue?.first { $0.endDate == nil }?.end(at: date)
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

    /// Stores the runner's after-run answers for the coach.
    func saveCheckIn(_ data: Data?) {
        checkInDataValue = data
    }

    /// Each step of a structured run as it was run, in order. Empty for other runs.
    var stepLog: [RecordedStep] {
        guard let stepLogDataValue else { return [] }
        return (try? JSONDecoder().decode([RecordedStep].self, from: stepLogDataValue)) ?? []
    }

    func saveStepLog(_ steps: [RecordedStep]) {
        stepLogDataValue = steps.isEmpty ? nil : try? JSONEncoder().encode(steps)
    }

    /// The step counts collected during the run, in order.
    var stepCounts: [StepCountSample] {
        guard let stepCountDataValue else { return [] }
        return (try? JSONDecoder().decode([StepCountSample].self, from: stepCountDataValue)) ?? []
    }

    func saveStepCounts(_ samples: [StepCountSample]) {
        stepCountDataValue = samples.isEmpty ? nil : try? JSONEncoder().encode(samples)
    }

    /// Steps taken while running, or nil when none were counted.
    var stepTotal: Double? {
        let counts = stepCounts
        return counts.isEmpty ? nil : counts.reduce(0) { $0 + $1.count }
    }

    /// Mean steps a minute over the time spent running, or nil when no steps were counted.
    var meanCadence: Double? {
        let seconds = activeDuration()
        guard let stepTotal, seconds > 0 else { return nil }
        return stepTotal / seconds * 60
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
        let last = lastSample ?? routeSamplesValue?.max { $0.timestamp < $1.timestamp }
        if let last, sample.timestamp <= last.timestamp {
            Logger.run.debug("Ignoring an out-of-order route sample.")
            return
        }
        if status == .active, let last {
            distanceMetersValue += sample.location.distance(from: last.location)
        }
        routeSamplesValue = (routeSamplesValue ?? []) + [sample]
        lastSample = sample
    }

    /// Adds a heart rate reading. Readings only count while the run is active, so standing
    /// still at a crossing doesn't pull the average down.
    func record(_ sample: HeartRateSample) {
        guard status == .active else {
            Logger.run.debug("Ignoring a heart rate reading while the run isn't active.")
            return
        }
        // HealthKit can hand over a reading from a pause just after the run resumes.
        guard !pauses.contains(where: { $0.contains(sample.timestamp) }) else {
            Logger.run.debug("Ignoring a heart rate reading taken during a pause.")
            return
        }
        guard sample.beatsPerMinute > 0 else { return }
        let last = lastHeartRateSample ?? heartRateSamplesValue?.max { $0.timestamp < $1.timestamp }
        if let last, sample.timestamp <= last.timestamp {
            Logger.run.debug("Ignoring an out-of-order heart rate reading.")
            return
        }
        heartRateSamplesValue = (heartRateSamplesValue ?? []) + [sample]
        lastHeartRateSample = sample
    }
}
