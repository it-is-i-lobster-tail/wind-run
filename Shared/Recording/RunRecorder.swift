//
//  RunRecorder.swift
//  Wind Run
//

import CoreLocation
import Foundation
import Observation
import OSLog
import SwiftData

/// Drives one run from start to finish: listens for GPS fixes, and heart rate when it's on,
/// and feeds them to the `Run`.
///
/// Location stays on the device. Fixes go into the local store, and into Apple Health
/// only if the runner has turned that on.
@Observable
final class RunRecorder {
    /// Fixes less accurate than this are dropped so GPS drift doesn't inflate distance.
    static let maximumHorizontalAccuracy: CLLocationAccuracy = 30

    private(set) var run: Run?
    private(set) var locationDenied = false
    /// Live heart rate, or nil when heart rate is off for this run.
    private(set) var heartRate: HeartRateMonitor?

    private let modelContext: ModelContext
    private var updatesTask: Task<Void, Never>?
    private var session: CLServiceSession?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var isRecording: Bool {
        guard let run else { return false }
        return !run.isFinished
    }

    func start(kind: RunKind = .free, intervalPlan: IntervalPlan? = nil, measuresHeartRate: Bool = false) {
        guard !isRecording else {
            Logger.recording.warning("A run is already being recorded.")
            return
        }
        let run = Run(kind: kind)
        run.intervalPlanValue = intervalPlan
        modelContext.insert(run)
        modelContext.saveQuietly()
        self.run = run
        startLocationUpdates()
        if measuresHeartRate {
            startHeartRate(at: run.startDate)
        }
    }

    func pause() {
        run?.pause()
        heartRate?.pause()
        modelContext.saveQuietly()
    }

    func resume() {
        run?.resume()
        heartRate?.resume()
        modelContext.saveQuietly()
    }

    func finish() {
        stopLocationUpdates()
        stopHeartRate()
        guard let run else { return }
        run.finish()
        modelContext.saveQuietly()
        HealthSync.shared.saveIfEnabled(run, in: modelContext)
    }

    /// Throws the run away, along with its route and heart rate.
    func discard() {
        stopLocationUpdates()
        stopHeartRate()
        if let run {
            run.discard()
            modelContext.delete(run)
            modelContext.saveQuietly()
        }
        run = nil
    }

    private func startLocationUpdates() {
        session = CLServiceSession(authorization: .whenInUse)
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self, !Task.isCancelled else { return }
                    self.locationDenied = update.authorizationDenied || update.authorizationDeniedGlobally
                    Logger.recording.debug("Location update: fix \(update.location != nil), denied \(self.locationDenied), requestInProgress \(update.authorizationRequestInProgress), insufficient \(update.insufficientlyInUse)")
                    if let location = update.location {
                        self.receive(location)
                    }
                }
            } catch {
                Logger.recording.error("Location updates ended: \(error.localizedDescription)")
            }
        }
    }

    private func stopLocationUpdates() {
        updatesTask?.cancel()
        updatesTask = nil
        session?.invalidate()
        session = nil
    }

    private func startHeartRate(at date: Date) {
        let monitor = HeartRateMonitor()
        monitor.onReading = { [weak self] beatsPerMinute, date in
            self?.run?.record(HeartRateSample(timestamp: date, beatsPerMinute: beatsPerMinute))
        }
        monitor.start(at: date)
        heartRate = monitor
    }

    private func stopHeartRate() {
        heartRate?.stop()
        heartRate = nil
    }

    private func receive(_ location: CLLocation) {
        guard let run, !run.isFinished else { return }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.maximumHorizontalAccuracy
        else { return }
        run.record(RouteSample(location))
    }
}
