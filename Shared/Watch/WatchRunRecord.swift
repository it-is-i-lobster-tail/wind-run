//
//  WatchRunRecord.swift
//  Wind Run
//

import Foundation
import OSLog
import SwiftData

/// A finished watch run for transfer to its paired iPhone.
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
        /// Nil from a watch app that didn't send it.
        var speedAccuracy: Double?
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
    var workoutTypeValue: String?
    var kind: RunKind
    var start: Date
    var end: Date
    var meters: Double
    var route: [Fix]
    var pauses: [Pause]
    var heartRate: [Beat]
    var stepLog: Data?
    var stepCounts: Data?
    /// The barometer's readings, as `Run.altitudeDataValue` keeps them. Nil from a watch app that didn't send them.
    var altitude: Data?
    /// The coach session it ran, and the fingerprint of the steps it followed.
    var sessionID: UUID?
    var stepsSignature: String?
    /// How `meters` was measured, the old straight-line sum, Apple's distance and the devices behind the
    /// run. All nil from a watch app that didn't send them.
    var distanceMethod: String?
    var gpsTrackMeters: Double?
    var appleMeters: Double?
    var devices: RunDevices?
    var goalMeters: Double? = nil
    var goalSeconds: Double? = nil
    var savedWorkout: WatchSavedWorkout? = nil
    var activeCalories: Double? = nil
    var healthWorkoutID: UUID? = nil
}

extension WatchRunRecord {
    /// A finished run's record, or nil while it's still going or was thrown away.
    init?(_ run: Run) {
        guard run.status == .complete, let end = run.endDate else { return nil }
        self.init(
            runID: run.runID,
            workoutTypeValue: run.workoutTypeValue,
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
                    course: $0.courseValue,
                    speedAccuracy: $0.speedAccuracyValue
                )
            },
            pauses: run.pauses.map { Pause(start: $0.startDate, end: $0.endDate) },
            heartRate: run.heartRateSamples.map { Beat(timestamp: $0.timestamp, beatsPerMinute: $0.beatsPerMinute, source: $0.sourceValue) },
            stepLog: run.stepLogDataValue,
            stepCounts: run.stepCountDataValue,
            altitude: run.altitudeDataValue,
            sessionID: run.coachWorkout?.sessionID,
            stepsSignature: run.coachWorkout?.stepsSignature,
            distanceMethod: run.distanceMethod,
            gpsTrackMeters: run.gpsTrackMeters,
            appleMeters: run.appleDistanceMeters,
            devices: run.devices,
            goalMeters: run.goal?.meters,
            goalSeconds: run.goal?.seconds,
            savedWorkout: run.kind == .intervals ? run.intervalPlan.map { WatchSavedWorkout($0) } : nil,
            activeCalories: run.activeCalories,
            healthWorkoutID: run.healthWorkoutID
        )
    }

    /// Commits the run before the iPhone acknowledges it. Nil means the run was already saved.
    func save(into context: ModelContext) throws -> Run? {
        let id = runID
        var descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.runIDValue == id })
        descriptor.includePendingChanges = false
        let existing = try context.fetchCount(descriptor)
        guard existing == 0 else {
            Trace.log(.watch, "Watch run received", ["duplicate": true])
            return nil
        }

        let run = Run(kind: kind, sport: WorkoutSport(stored: workoutTypeValue), startDate: start)
        context.insert(run)
        run.runIDValue = runID
        run.endDateValue = end
        run.statusValue = .complete
        run.distanceMetersValue = meters
        run.distanceMethodValue = distanceMethod
        run.gpsTrackMetersValue = gpsTrackMeters
        run.appleDistanceMetersValue = appleMeters
        run.goalMetersValue = goalMeters
        run.goalSecondsValue = goalSeconds
        run.healthWorkoutIDValue = healthWorkoutID
        // An older watch app sent no devices: the run was still recorded on a watch.
        var devices = devices ?? RunDevices(recorder: DeviceInfo(kind: .appleWatch))
        devices.receivedBy = .current
        run.saveDevices(devices)
        run.routeSamplesValue = route.map {
            RouteSample(
                timestamp: $0.timestamp,
                latitude: $0.latitude,
                longitude: $0.longitude,
                altitude: $0.altitude,
                horizontalAccuracy: $0.horizontalAccuracy,
                verticalAccuracy: $0.verticalAccuracy,
                speed: $0.speed,
                course: $0.course,
                speedAccuracy: $0.speedAccuracy ?? -1
            )
        }
        // Packed straight from the record, which holds the whole route, without reading the fixes back.
        run.packRoute(route.sorted { $0.timestamp < $1.timestamp }.map {
            RouteReading(
                timestamp: $0.timestamp,
                latitude: $0.latitude,
                longitude: $0.longitude,
                altitude: $0.altitude,
                horizontalAccuracy: $0.horizontalAccuracy,
                verticalAccuracy: $0.verticalAccuracy,
                speed: $0.speed,
                course: $0.course,
                speedAccuracy: $0.speedAccuracy ?? -1
            )
        })
        run.pausesValue = pauses.map { pause in
            let copy = RunPause(startDate: pause.start)
            if let end = pause.end { copy.end(at: end) }
            return copy
        }
        run.heartRateSamplesValue = heartRate.map {
            HeartRateSample(timestamp: $0.timestamp, beatsPerMinute: $0.beatsPerMinute, source: $0.source.flatMap { HeartRateSource(rawValue: $0) })
        }
        run.stepCountDataValue = stepCounts
        run.altitudeDataValue = altitude

        var sessionMatched = false
        var stepsMatched = false
        if let savedWorkout, kind == .intervals {
            run.intervalPlanValue = savedWorkout.makePlan(in: context)
            if savedWorkout.sport == .hiking { run.workoutTypeValue = WorkoutSport.hiking.rawValue }
            run.stepLogDataValue = stepLog
            stepsMatched = true
        } else if sessionID != nil {
            let wanted: UUID? = sessionID
            let workouts = try context.fetch(FetchDescriptor<CoachWorkout>(predicate: #Predicate { $0.sessionIDValue == wanted }))
            if let workout = workouts.first {
                sessionMatched = true
                run.coachWorkoutValue = workout
                // The steps as run only make sense against the steps they were run from.
                if let plan = workout.intervalPlan, workout.stepsSignature == stepsSignature {
                    stepsMatched = true
                    run.intervalPlanValue = plan
                    run.stepLogDataValue = stepLog
                }
            } else {
                Logger.recording.info("A run from the watch names a coach session this iPhone doesn't have.")
            }
        }
        run.activeCaloriesValue = activeCalories
        if activeCalories == nil {
            run.settleCalories(bodyMass: BodyWeight.kilograms())
        }
        try context.save()
        // What came, never where or the readings themselves.
        Trace.log(.watch, "Watch run received", [
            "duplicate": false,
            "fixes": route.count,
            "beats": heartRate.count,
            "pauses": pauses.count,
            "sessionMatched": sessionMatched,
            "stepsMatched": stepsMatched,
            "hasSteps": stepLog != nil,
        ])
        return run
    }

    @discardableResult
    func insert(into context: ModelContext) -> Run? {
        do {
            return try save(into: context)
        } catch {
            Trace.error("Couldn't save a run from the watch", error)
            return nil
        }
    }

    // MARK: Sending

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(_ data: Data) -> WatchRunRecord? {
        do {
            return try JSONDecoder().decode(WatchRunRecord.self, from: data)
        } catch {
            Trace.error("Couldn't read a run from the watch", error)
            return nil
        }
    }
}
