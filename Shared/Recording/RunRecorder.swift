//
//  RunRecorder.swift
//  Wind Run
//

import CoreLocation
import Foundation
import Observation
import OSLog
import SwiftData

/// Drives one run from start to finish: listens for GPS fixes and feeds them to the `Run`.
///
/// Location stays on the device. Fixes go straight into the local store and nowhere else.
@Observable
final class RunRecorder {
    /// Fixes less accurate than this are dropped so GPS drift doesn't inflate distance.
    static let maximumHorizontalAccuracy: CLLocationAccuracy = 30

    private(set) var run: Run?
    private(set) var locationDenied = false

    private let modelContext: ModelContext
    private var updatesTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var session: CLServiceSession?
    #if os(iOS)
    /// Keeps GPS and call-outs going with the phone locked in a pocket.
    private var backgroundSession: CLBackgroundActivitySession?
    #endif
    /// Reads out each split as it ends, or nil when call-outs are off.
    private var paceCallouts: PaceCalloutTracker?
    private let speaker = CalloutSpeaker()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var isRecording: Bool {
        guard let run else { return false }
        return !run.isFinished
    }

    func start(kind: RunKind = .free, intervalPlan: IntervalPlan? = nil) {
        guard !isRecording else {
            Logger.recording.warning("A run is already being recorded.")
            return
        }
        let run = Run(kind: kind)
        run.intervalPlanValue = intervalPlan
        modelContext.insert(run)
        modelContext.saveQuietly()
        self.run = run
        paceCallouts = PaceCalloutTracker(settings: .current())
        startLocationUpdates()
        startClock()
    }

    func pause() {
        run?.pause()
        modelContext.saveQuietly()
    }

    func resume() {
        run?.resume()
        modelContext.saveQuietly()
    }

    func finish() {
        stopLocationUpdates()
        stopClock()
        run?.finish()
        modelContext.saveQuietly()
    }

    /// Throws the run away, along with its route.
    func discard() {
        stopLocationUpdates()
        stopClock()
        speaker.stop()
        if let run {
            run.discard()
            modelContext.delete(run)
            modelContext.saveQuietly()
        }
        run = nil
    }

    private func startLocationUpdates() {
        session = CLServiceSession(authorization: .whenInUse)
        #if os(iOS)
        backgroundSession = CLBackgroundActivitySession()
        #endif
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
        #if os(iOS)
        backgroundSession?.invalidate()
        backgroundSession = nil
        #endif
    }

    /// Time splits end whether or not a GPS fix arrives, so the clock is checked every second too.
    private func startClock() {
        guard paceCallouts != nil else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.checkPaceCallout(at: .now)
            }
        }
    }

    private func stopClock() {
        clockTask?.cancel()
        clockTask = nil
    }

    private func receive(_ location: CLLocation) {
        guard let run, !run.isFinished else { return }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.maximumHorizontalAccuracy
        else { return }
        run.record(RouteSample(location))
        checkPaceCallout(at: location.timestamp)
    }

    /// Reads out the split that just ended, if one did.
    private func checkPaceCallout(at date: Date) {
        guard let run, run.status == .active, paceCallouts != nil else { return }
        if let callout = paceCallouts?.update(elapsed: run.activeDuration(at: date), meters: run.distanceMeters) {
            speaker.speak(callout.spokenText)
        }
    }
}
