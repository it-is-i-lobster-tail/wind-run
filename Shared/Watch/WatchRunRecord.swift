//
//  WatchRunRecord.swift
//  Wind Run
//

import Foundation
import OSLog
import SwiftData

/// A coached run finished on the watch, as it goes to the iPhone so the coach can count it. It goes straight
/// between the paired watch and iPhone: nothing passes through a server.
struct WatchRunRecord: Codable, Hashable {
    struct Fix: Codable, Hashable {
        var timestamp: Date
        var latitude: Double
        var longitude: Double
        var altitude: Double
        var horizontalAccuracy: Double
        var verticalAccuracy: Double
        var speed: Double
        var course: Double
    }

    struct Pause: Codable, Hashable {
        var start: Date
        var end: Date?
    }

    struct Beat: Codable, Hashable {
        var timestamp: Date
        var beatsPerMinute: Double
        var source: String?
    }

    var runID: UUID
    var kind: RunKind
    var start: Date
    var end: Date
    var meters: Double
    var route: [Fix]
    var pauses: [Pause]
    var heartRate: [Beat]
    var stepLog: Data?
    var stepCounts: Data?
    /// The coach session it ran, and the fingerprint of the steps it followed.
    var sessionID: UUID?
    var stepsSignature: String?
}

extension WatchRunRecord {
    /// A finished run's record, or nil while it's still going or was thrown away.
    init?(_ run: Run) {
        guard run.status == .complete, let end = run.endDate else { return nil }
        self.init(
            runID: run.runID,
            kind: run.kind,
            start: run.startDate,
            end: end,
            meters: run.distanceMeters,
            route: run.route.map {
                Fix(
                    timestamp: $0.timestampValue,
                    latitude: $0.latitudeValue,
                    longitude: $0.longitudeValue,
                    altitude: $0.altitudeValue,
                    horizontalAccuracy: $0.horizontalAccuracyValue,
                    verticalAccuracy: $0.verticalAccuracyValue,
                    speed: $0.speedValue,
                    course: $0.courseValue
                )
            },
            pauses: run.pauses.map { Pause(start: $0.startDate, end: $0.endDate) },
            heartRate: run.heartRateSamples.map { Beat(timestamp: $0.timestamp, beatsPerMinute: $0.beatsPerMinute, source: $0.sourceValue) },
            stepLog: run.stepLogDataValue,
            stepCounts: run.stepCountDataValue,
            sessionID: run.coachWorkout?.sessionID,
            stepsSignature: run.coachWorkout?.stepsSignature
        )
    }

    /// Adds the run to the iPhone's store, linked to the coach session it ran, and returns it. Nil when the
    /// run is already there, since the watch may send the same run twice.
    @discardableResult
    func insert(into context: ModelContext) -> Run? {
        let id = runID
        let existing = (try? context.fetchCount(FetchDescriptor<Run>(predicate: #Predicate { $0.runIDValue == id }))) ?? 0
        guard existing == 0 else { return nil }

        let run = Run(kind: kind, startDate: start)
        context.insert(run)
        run.runIDValue = runID
        run.endDateValue = end
        run.statusValue = .complete
        run.distanceMetersValue = meters
        run.routeSamplesValue = route.map {
            RouteSample(
                timestamp: $0.timestamp,
                latitude: $0.latitude,
                longitude: $0.longitude,
                altitude: $0.altitude,
                horizontalAccuracy: $0.horizontalAccuracy,
                verticalAccuracy: $0.verticalAccuracy,
                speed: $0.speed,
                course: $0.course
            )
        }
        run.pausesValue = pauses.map { pause in
            let copy = RunPause(startDate: pause.start)
            if let end = pause.end { copy.end(at: end) }
            return copy
        }
        run.heartRateSamplesValue = heartRate.map {
            HeartRateSample(timestamp: $0.timestamp, beatsPerMinute: $0.beatsPerMinute, source: $0.source.flatMap { HeartRateSource(rawValue: $0) })
        }
        run.stepCountDataValue = stepCounts

        if sessionID != nil {
            let wanted: UUID? = sessionID
            let workouts = (try? context.fetch(FetchDescriptor<CoachWorkout>(predicate: #Predicate { $0.sessionIDValue == wanted }))) ?? []
            if let workout = workouts.first {
                run.coachWorkoutValue = workout
                // The steps as run only make sense against the steps they were run from.
                if let plan = workout.intervalPlan, workout.stepsSignature == stepsSignature {
                    run.intervalPlanValue = plan
                    run.stepLogDataValue = stepLog
                }
            } else {
                Logger.recording.info("A run from the watch names a coach session this iPhone doesn't have.")
            }
        }
        context.saveQuietly()
        return run
    }

    // MARK: Sending

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) -> WatchRunRecord? {
        try? JSONDecoder().decode(WatchRunRecord.self, from: data)
    }
}
