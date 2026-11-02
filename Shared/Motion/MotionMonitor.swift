//
//  MotionMonitor.swift
//  Wind Run
//

import CoreMotion
import Foundation
import Observation
import OSLog

/// Footsteps and what the runner is doing, from the device's own motion sensor, for one run.
///
/// It works alongside GPS: GPS still measures distance and pace, while motion counts steps, gives live
/// cadence, and tells auto-pause when the runner has stopped. It needs Motion & Fitness allowed, and
/// it reads nothing from before the run. Nothing leaves the device except with the run, the same as GPS.
@Observable
final class MotionMonitor {
    /// Whether the runner turned on step counting. Off until they do.
    static let stepsKey = "motionStepsEnabled"

    /// Steps a minute, or nil until the sensor says. Zero once the runner stops.
    private(set) var cadence: Double?

    /// Called on the main actor with the steps counted since the run started, the steps a minute when
    /// known, and when.
    @ObservationIgnored var onSteps: ((_ totalSteps: Double, _ cadence: Double?, _ date: Date) -> Void)?
    /// Called on the main actor when the motion sensor's read of the runner changes.
    @ObservationIgnored var onActivity: ((_ activity: MotionActivity, _ date: Date) -> Void)?
    /// Called on the main actor if the sensor stops, for example when Motion & Fitness is turned off mid-run.
    @ObservationIgnored var onFailure: (() -> Void)?

    @ObservationIgnored private let pedometer = CMPedometer()
    @ObservationIgnored private let activityManager = CMMotionActivityManager()
    @ObservationIgnored private var lastStepDate: Date?
    /// Cadence drops to zero once no step has come in for this long.
    private static let cadenceTimeout: TimeInterval = 5

    /// Whether this device can count steps at all. The simulator can't.
    static var isAvailable: Bool {
        CMPedometer.isStepCountingAvailable()
    }

    static var isAllowed: Bool {
        CMPedometer.authorizationStatus() == .authorized
    }

    static var isDenied: Bool {
        let status = CMPedometer.authorizationStatus()
        return status == .denied || status == .restricted
    }

    /// Asks for Motion & Fitness, if it hasn't been asked on this device, by reading the last minute of
    /// steps, which is what brings up the system's question. Returns whether it's allowed.
    static func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        if CMPedometer.authorizationStatus() == .notDetermined {
            let pedometer = CMPedometer()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                pedometer.queryPedometerData(from: .now.addingTimeInterval(-60), to: .now) { @Sendable _, _ in
                    continuation.resume()
                }
            }
            withExtendedLifetime(pedometer) {}
        }
        return isAllowed
    }

    /// Turns step counting and auto-pause on and asks for Motion & Fitness. Steps go back off if it isn't
    /// allowed; auto-pause stays on and uses GPS alone.
    @discardableResult
    static func turnOn(defaults: UserDefaults = .standard) async -> Bool {
        defaults.set(true, forKey: stepsKey)
        defaults.set(true, forKey: AutoPause.storageKey)
        let allowed = await requestAccess()
        if !allowed {
            defaults.set(false, forKey: stepsKey)
        }
        return allowed
    }

    /// Starts counting from the run's start. Returns false if motion isn't allowed or available.
    @discardableResult
    func start(at date: Date) -> Bool {
        guard Self.isAvailable, Self.isAllowed else { return false }
        pedometer.startUpdates(from: date) { @Sendable [weak self] data, error in
            if let error {
                let message = error.localizedDescription
                Task { @MainActor [weak self] in
                    Logger.recording.error("Step counting stopped: \(message)")
                    self?.onFailure?()
                }
                return
            }
            guard let data else { return }
            let steps = data.numberOfSteps.doubleValue
            // The sensor gives steps a second.
            let cadence = data.currentCadence.map { $0.doubleValue * 60 }
            let end = data.endDate
            Task { @MainActor [weak self] in self?.receive(steps: steps, cadence: cadence, at: end) }
        }
        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: .main) { @Sendable [weak self] activity in
                guard let activity else { return }
                let read = Self.read(activity)
                let date = activity.startDate
                MainActor.assumeIsolated { self?.onActivity?(read, date) }
            }
        }
        return true
    }

    func stop() {
        pedometer.stopUpdates()
        activityManager.stopActivityUpdates()
        onSteps = nil
        onActivity = nil
        onFailure = nil
    }

    /// Lets cadence fall to zero when steps stop coming, since the pedometer goes quiet rather than saying so.
    func tick(at date: Date) {
        guard let lastStepDate, cadence != 0, date.timeIntervalSince(lastStepDate) >= Self.cadenceTimeout else { return }
        cadence = 0
    }

    private func receive(steps: Double, cadence: Double?, at date: Date) {
        lastStepDate = date
        if let cadence {
            self.cadence = cadence
        }
        onSteps?(steps, cadence, date)
    }

    private nonisolated static func read(_ activity: CMMotionActivity) -> MotionActivity {
        // A low-confidence read is as good as no read.
        guard activity.confidence != .low else { return .other }
        if activity.walking || activity.running { return .onFoot }
        if activity.automotive || activity.cycling { return .other }
        if activity.stationary { return .stationary }
        return .other
    }
}
