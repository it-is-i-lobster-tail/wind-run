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
/// Deleting a run can take its workout out of Health too, when the runner asks.
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
    /// The run's calories, so Fitness credits the Move ring.
    private let energyType = HKQuantityType(.activeEnergyBurned)

    private var shareTypes: Set<HKSampleType> {
        [workoutType, routeType, distanceType, energyType]
    }

    /// Runs this device finished that belong in Health but couldn't be saved yet, as run ids: Health's
    /// question wasn't answered yet, or the save failed, such as while the iPhone was locked. Kept on this
    /// device only, so a run another device saves is never saved twice.
    static let pendingKey = "healthSavesPending"
    /// Runs being saved right now, so trying again can't save one twice.
    private var saving: Set<UUID> = []

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

    /// Weight, so calories can use Health's instead of asking (iPhone only).
    #if os(iOS)
    static let readTypes: Set<HKObjectType> = [HKQuantityType(.bodyMass)]
    #else
    static let readTypes: Set<HKObjectType> = []
    #endif

    /// Shows Health's permission sheet the first time. After that the answer lives in the
    /// Settings app, so this just reports it.
    func requestAccess() async -> Access {
        await requestAccess(toShare: shareTypes, read: Self.readTypes)
    }

    private func requestAccess(toShare share: Set<HKSampleType>, read: Set<HKObjectType>) async -> Access {
        guard isAvailable else { return .denied }
        do {
            try await store.requestAuthorization(toShare: share, read: read)
        } catch {
            Logger.health.error("Health permission request failed: \(error)")
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

    /// Turns heart rate and Save runs to Health on together, as first-open setup does, and asks Health once for
    /// both so its sheet shows one time. Both go back off if Health doesn't allow workouts, like turning either
    /// on alone.
    @discardableResult
    func turnOn(heartRate: Bool, saveRuns: Bool, defaults: UserDefaults = .standard) async -> Access {
        guard heartRate || saveRuns else { return access }
        if heartRate { defaults.set(true, forKey: HeartRateMonitor.storageKey) }
        if saveRuns { defaults.set(true, forKey: Self.enabledKey) }
        let read = heartRate ? HeartRateMonitor.readTypes : Self.readTypes
        // A heart rate session needs workouts allowed, even without saving runs.
        let access = await requestAccess(toShare: saveRuns ? shareTypes : [workoutType], read: read)
        if access == .denied {
            if heartRate { defaults.set(false, forKey: HeartRateMonitor.storageKey) }
            if saveRuns { defaults.set(false, forKey: Self.enabledKey) }
        }
        Trace.log(.health, "Setup asked Health", ["heartRate": heartRate, "saveRuns": saveRuns, "allowed": access == .allowed])
        return access
    }

    /// With Save runs to Health on, asks Health about anything Wind Run has started saving since it was
    /// turned on, such as a run's calories. Health shows its sheet only for what it hasn't asked about yet.
    func askForNewAccessIfOn() async {
        guard Self.isEnabled, access == .allowed else { return }
        _ = await requestAccess()
    }

    /// Saves a finished run in the background, if the runner has turned Health on and allowed it. A run
    /// that can't be saved yet is kept to try again with `retryPending`.
    func saveIfEnabled(_ run: Run, in context: ModelContext, defaults: UserDefaults = .standard) {
        guard Self.isEnabled, run.healthWorkoutID == nil, let workout = HealthWorkout(run) else {
            // Why a run isn't in Health, the question asked most.
            Trace.log(.health, "Health save skipped", [
                "enabled": Self.isEnabled,
                "alreadySaved": run.healthWorkoutID != nil,
                "complete": run.status == .complete,
            ])
            return
        }
        guard access == .allowed else {
            Logger.health.info("Health is on in Wind Run but writing isn't allowed, so the run wasn't saved there.")
            Trace.log(.health, "Health save waiting for permission", ["notAsked": access == .notDetermined])
            // Health's question may still be answered, so it's tried again then.
            if access == .notDetermined {
                Self.addPending(run.runIDValue, in: defaults)
            }
            return
        }
        let runID = run.runIDValue
        guard saving.insert(runID).inserted else { return }
        Task {
            defer { saving.remove(runID) }
            do {
                let id = try await save(workout)
                run.markSavedToHealth(as: id)
                context.saveQuietly()
                Self.removePending(runID, in: defaults)
                Logger.health.debug("Saved run to Health")
                Trace.log(.health, "Saved to Health", [
                    "segments": workout.distance.count,
                    "routeFixes": workout.route.count,
                    "pauses": workout.pauses.count,
                    "hasCalories": workout.activeCalories != nil,
                ])
            } catch {
                Logger.health.error("Couldn't save run to Health: \(error)")
                // Such as Health's store being locked with the iPhone: tried again when the app comes back.
                Self.addPending(runID, in: defaults)
            }
        }
    }

    /// Tries again to save this device's runs that couldn't be saved before. Call when the app comes to the
    /// front, which is also when a locked iPhone has been unlocked.
    func retryPending(in context: ModelContext, defaults: UserDefaults = .standard) {
        let pending = Self.pending(in: defaults)
        guard !pending.isEmpty else { return }
        guard Self.isEnabled else {
            // Turned off since: these runs stay out of Health, like any other.
            defaults.removeObject(forKey: Self.pendingKey)
            return
        }
        guard access == .allowed else { return }
        let unsaved = (try? context.fetch(FetchDescriptor<Run>(predicate: #Predicate { $0.healthWorkoutIDValue == nil }))) ?? []
        let runs = unsaved.filter { pending.contains($0.runIDValue) }
        // Runs deleted since, or saved some other way, are forgotten.
        let found = Set(runs.map(\.runIDValue))
        for id in pending where !found.contains(id) {
            Self.removePending(id, in: defaults)
        }
        Trace.log(.health, "Retrying Health saves", ["runs": runs.count])
        for run in runs {
            saveIfEnabled(run, in: context, defaults: defaults)
        }
    }

    static func pending(in defaults: UserDefaults = .standard) -> [UUID] {
        (defaults.stringArray(forKey: pendingKey) ?? []).compactMap(UUID.init(uuidString:))
    }

    private static func addPending(_ id: UUID, in defaults: UserDefaults) {
        var ids = pending(in: defaults)
        guard !ids.contains(id) else { return }
        ids.append(id)
        defaults.set(ids.map(\.uuidString), forKey: pendingKey)
    }

    private static func removePending(_ id: UUID, in defaults: UserDefaults) {
        let ids = pending(in: defaults).filter { $0 != id }
        if ids.isEmpty {
            defaults.removeObject(forKey: pendingKey)
        } else {
            defaults.set(ids.map(\.uuidString), forKey: pendingKey)
        }
    }

    /// Deletes a workout Wind Run saved, with its distance and route. Health only lets an app delete what it
    /// saved itself, and only while writing workouts is allowed, so otherwise the workout stays there.
    func deleteWorkout(_ id: UUID) async {
        guard access == .allowed else {
            Logger.health.info("Writing to Health isn't allowed, so the run's workout stays there.")
            return
        }
        do {
            let descriptor = HKSampleQueryDescriptor(
                predicates: [.workout(HKQuery.predicateForObject(with: id))],
                sortDescriptors: []
            )
            // An app can always read back what it saved, even without permission to read.
            guard let workout = try await descriptor.result(for: store).first else {
                Logger.health.info("The run's workout was already gone from Health.")
                return
            }
            // Deleting a workout leaves the samples saved with it, so they go first.
            let savedWithWorkout = HKQuery.predicateForObjects(from: workout)
            for type in [distanceType, energyType, routeType] as [HKSampleType] where canWrite(type) {
                _ = try await store.deleteObjects(of: type, predicate: savedWithWorkout)
            }
            try await store.delete(workout)
            Logger.health.debug("Deleted the run's workout from Health")
        } catch {
            Logger.health.error("Couldn't delete the run's workout from Health: \(error)")
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

        // Calories, so Fitness credits the Move ring. Health lets the runner switch these off on their own.
        let energy = workout.energySegments
        if canWrite(energyType), !energy.isEmpty {
            let samples = energy.map { segment in
                HKQuantitySample(
                    type: energyType,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: segment.kilocalories),
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
                Logger.health.error("Saved the workout but not its route: \(error)")
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
