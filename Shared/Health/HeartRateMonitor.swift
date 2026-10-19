//
//  HeartRateMonitor.swift
//  Wind Run
//

import Foundation
import HealthKit
import Observation
import OSLog

/// Live heart rate for one run, from a HealthKit workout session.
///
/// While the session runs, HealthKit passes along heart rate from whatever the runner wears:
/// Apple Watch, AirPods Pro 3, Powerbeats Pro 2, or a Bluetooth strap paired in Settings.
/// On the watch, the session also keeps the app running when the wrist goes down.
///
/// The session's own workout is always discarded. Readings go to the run in the local store,
/// and only "Save runs to Health" puts a run in Apple Health, so a run is never saved twice.
@Observable
final class HeartRateMonitor {
    /// Whether the runner turned heart rate on. Off until they do.
    static let storageKey = "heartRateEnabled"

    private static let store = HKHealthStore()

    /// The newest reading in beats per minute, or nil until one arrives.
    private(set) var beatsPerMinute: Double?

    /// Called on the main actor with each new reading.
    @ObservationIgnored var onReading: ((_ beatsPerMinute: Double, _ date: Date) -> Void)?

    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    // The session and builder hold their delegate weakly.
    @ObservationIgnored private var delegate: WorkoutSessionDelegate?

    /// Asks Health for what a workout session needs: sharing workouts and reading heart rate.
    ///
    /// A session can run once workouts are allowed. Health never says whether reading was
    /// allowed, so heart rate can still come up empty.
    static func requestAccess() async -> HealthSync.Access {
        guard HKHealthStore.isHealthDataAvailable() else { return .denied }
        do {
            try await store.requestAuthorization(
                toShare: [HKObjectType.workoutType()],
                read: [HKQuantityType(.heartRate)]
            )
        } catch {
            Logger.health.error("Heart rate permission request failed: \(error.localizedDescription)")
        }
        return HealthSync.shared.access
    }

    func start(at date: Date) {
        guard session == nil else {
            Logger.health.warning("A workout session is already running.")
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            Logger.health.info("Health isn't available on this device.")
            return
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor

        let session: HKWorkoutSession
        do {
            session = try HKWorkoutSession(healthStore: Self.store, configuration: configuration)
        } catch {
            Logger.health.error("Couldn't create a workout session: \(error.localizedDescription)")
            return
        }
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: Self.store, workoutConfiguration: configuration)

        let delegate = WorkoutSessionDelegate(
            onReading: { [weak self] beatsPerMinute, date in
                self?.receive(beatsPerMinute, at: date)
            },
            onFailure: { [weak self] message in
                Logger.health.error("Workout session failed: \(message)")
                self?.tearDown()
            }
        )
        session.delegate = delegate
        builder.delegate = delegate
        self.session = session
        self.builder = builder
        self.delegate = delegate

        session.startActivity(with: date)
        Task {
            do {
                try await builder.beginCollection(at: date)
            } catch {
                Logger.health.error("Couldn't start collecting heart rate: \(error.localizedDescription)")
            }
        }
    }

    func pause() {
        session?.pause()
    }

    func resume() {
        session?.resume()
    }

    /// Ends the session and throws its workout away.
    func stop() {
        guard let session, let builder else { return }
        builder.discardWorkout()
        session.end()
        tearDown()
    }

    private func receive(_ beatsPerMinute: Double, at date: Date) {
        self.beatsPerMinute = beatsPerMinute
        onReading?(beatsPerMinute, date)
    }

    private func tearDown() {
        session = nil
        builder = nil
        delegate = nil
        beatsPerMinute = nil
    }
}

/// Hears from HealthKit on its own queues and hands what matters to the main actor.
private nonisolated final class WorkoutSessionDelegate: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private let onReading: @MainActor (Double, Date) -> Void
    private let onFailure: @MainActor (String) -> Void

    init(
        onReading: @escaping @MainActor (Double, Date) -> Void,
        onFailure: @escaping @MainActor (String) -> Void
    ) {
        self.onReading = onReading
        self.onFailure = onFailure
        super.init()
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRate = HKQuantityType(.heartRate)
        guard collectedTypes.contains(heartRate),
              let statistics = workoutBuilder.statistics(for: heartRate),
              let quantity = statistics.mostRecentQuantity(),
              let interval = statistics.mostRecentQuantityDateInterval()
        else { return }
        let beatsPerMinute = quantity.doubleValue(for: .count().unitDivided(by: .minute()))
        let date = interval.end
        let onReading = onReading
        Task { @MainActor in onReading(beatsPerMinute, date) }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        let message = error.localizedDescription
        let onFailure = onFailure
        Task { @MainActor in onFailure(message) }
    }
}
