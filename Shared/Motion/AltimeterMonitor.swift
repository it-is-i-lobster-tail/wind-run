//
//  AltimeterMonitor.swift
//  Wind Run
//

import CoreMotion
import Foundation
import OSLog

/// Climb and drop from the device's barometer, for one run.
///
/// GPS height wanders by several meters from fix to fix; the barometer feels a meter of climb, which is
/// what the run's elevation and calories need on rolling ground. It needs Motion & Fitness allowed, the
/// same as steps, and never asks for it during a run. Readings stay with the run, like its route.
final class AltimeterMonitor {
    /// Readings closer together than this are thinned out, so a long run keeps a few thousand at most.
    static let spacing: TimeInterval = 5

    /// The readings so far, `spacing` apart, then the newest.
    var samples: [AltitudeSample] {
        guard let pending, pending.timestamp > (kept.last?.timestamp ?? .distantPast) else { return kept }
        return kept + [pending]
    }

    private let altimeter = CMAltimeter()
    private var kept: [AltitudeSample] = []
    /// The newest reading, held until it's `spacing` past the last one kept.
    private var pending: AltitudeSample?

    /// Whether this device has a barometer. The simulator doesn't.
    static var isAvailable: Bool {
        CMAltimeter.isRelativeAltitudeAvailable()
    }

    static var isAllowed: Bool {
        CMAltimeter.authorizationStatus() == .authorized
    }

    /// Starts reading. Returns false without a barometer or without Motion & Fitness allowed.
    @discardableResult
    func start() -> Bool {
        guard Self.isAvailable, Self.isAllowed else { return false }
        altimeter.startRelativeAltitudeUpdates(to: .main) { @Sendable [weak self] data, error in
            if let error {
                let message = error.localizedDescription
                MainActor.assumeIsolated { Logger.recording.error("The barometer stopped: \(message)") }
                return
            }
            guard let data else { return }
            let meters = data.relativeAltitude.doubleValue
            // The reading's time is counted from when the device started up.
            let age = ProcessInfo.processInfo.systemUptime - data.timestamp
            MainActor.assumeIsolated {
                self?.receive(meters, at: Date.now.addingTimeInterval(-max(0, age)))
            }
        }
        return true
    }

    func stop() {
        altimeter.stopRelativeAltitudeUpdates()
    }

    func receive(_ meters: Double, at date: Date) {
        let sample = AltitudeSample(timestamp: date, relativeMeters: meters)
        if let last = kept.last, date.timeIntervalSince(last.timestamp) < Self.spacing {
            pending = sample
        } else {
            kept.append(sample)
            pending = nil
        }
    }
}
