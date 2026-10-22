//
//  HealthSync.swift
//  Wind Run
//

import CoreLocation
import Foundation
import HealthKit
import OSLog
import SwiftData

/// Saves finished runs to Apple Health, only when the runner turns it on.
///
/// Off by default. This only writes to Health; the one thing Wind Run reads is live heart rate
/// during a run, when that's on (see `HeartRateMonitor`). Turning the setting off stops new runs
/// from being saved; workouts already in Health stay there, and so do the runs in Wind Run.
final class HealthSync {
    static let enabledKey = "savesRunsToHealth"
    static let shared = HealthSync()

    /// Whether Wind Run may write a workout to Health. Health never says whether you can read, but it does say this.
    enum Access {
        case notDetermined
        case allowed
        case denied
    }

    private let store = HKHealthStore()
    private let workoutType = HKObjectType.workoutType()
    private let routeType = HKSeriesType.workoutRoute()
    private let distanceType = HKQuantityType(.distanceWalkingRunning)

    private var shareTypes: Set<HKSampleType> {
        [workoutType, routeType, distanceType]
    }

    /// The runner's choice, read outside of views. Views use `@AppStorage(HealthSync.enabledKey)`.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    var isAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    var access: Access {
        guard isAvailable else { return .denied }
        switch store.authorizationStatus(for: workoutType) {
        case .sharingAuthorized: return .allowed
        case .sharingDenied: return .denied
        default: return .notDetermined
        }
    }

    /// Shows Health's permission sheet the first time. After that the answer lives in the
    /// Settings app, so this just reports it.
    func requestAccess() async -> Access {
        guard isAvailable else { return .denied }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: [])
        } catch {
            Logger.health.error("Health permission request failed: \(error.localizedDescription)")
        }
        return access
    }

    /// Turns "Save runs to Health" on and asks Health for access, turning it back off
    /// if Health doesn't allow saving workouts.
    @discardableResult
    func turnOn(defaults: UserDefaults = .standard) async -> Access {
        defaults.set(true, forKey: Self.enabledKey)
        let access = await requestAccess()
        if access == .denied {
            defaults.set(false, forKey: Self.enabledKey)
        }
        return access
    }

    /// Saves a finished run in the background, if the runner has turned Health on and allowed it.
    func saveIfEnabled(_ run: Run, in context: ModelContext) {
        guard Self.isEnabled, run.healthWorkoutID == nil, let workout = HealthWorkout(run) else { return }
        guard access == .allowed else {
            Logger.health.info("Health is on in Wind Run but writing isn't allowed, so the run wasn't saved there.")
            return
        }
        Task {
            do {
                let id = try await save(workout)
                run.markSavedToHealth(as: id)
                context.saveQuietly()
                Logger.health.debug("Saved run to Health")
            } catch {
                Logger.health.error("Couldn't save run to Health: \(error.localizedDescription)")
            }
        }
    }

    /// Writes one outdoor running workout with its distance, pauses and route. Returns the workout's ID.
    private func save(_ workout: HealthWorkout) async throws -> UUID {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        try await builder.beginCollection(at: workout.start)

        // The runner can switch off distance or routes on Health's sheet and still allow workouts.
        if canWrite(distanceType), !workout.distance.isEmpty {
            let samples = workout.distance.map { segment in
                HKQuantitySample(
                    type: distanceType,
                    quantity: HKQuantity(unit: .meter(), doubleValue: segment.meters),
                    start: segment.start,
                    end: segment.end
                )
            }
            try await builder.addSamples(samples)
        }

        // Pause and resume events keep paused time out of the workout's duration.
        let events = workout.pauses.flatMap { pause in
            [
                HKWorkoutEvent(type: .pause, dateInterval: DateInterval(start: pause.start, duration: 0), metadata: nil),
                HKWorkoutEvent(type: .resume, dateInterval: DateInterval(start: pause.end, duration: 0), metadata: nil),
            ]
        }
        if !events.isEmpty {
            try await builder.addWorkoutEvents(events)
        }

        try await builder.addMetadata([HKMetadataKeyIndoorWorkout: false])
        try await builder.endCollection(at: workout.end)
        guard let saved = try await builder.finishWorkout() else {
            throw HealthSyncError.workoutNotSaved
        }

        // The workout is already in Health, so a route that fails to save doesn't undo it.
        if canWrite(routeType), workout.route.count > 1 {
            do {
                let routeBuilder = HKWorkoutRouteBuilder(healthStore: store, device: .local())
                try await routeBuilder.insertRouteData(workout.route)
                try await routeBuilder.finishRoute(with: saved, metadata: nil)
            } catch {
                Logger.health.error("Saved the workout but not its route: \(error.localizedDescription)")
            }
        }
        return saved.uuid
    }

    private func canWrite(_ type: HKObjectType) -> Bool {
        store.authorizationStatus(for: type) == .sharingAuthorized
    }
}

enum HealthSyncError: Error {
    case workoutNotSaved
}
