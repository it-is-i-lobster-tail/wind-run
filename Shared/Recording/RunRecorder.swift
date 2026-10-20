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
    private var clockTask: Task<Void, Never>?
    private var session: CLServiceSession?
    #if os(iOS)
    /// Keeps GPS and call-outs going with the phone locked in a pocket.
    private var backgroundSession: CLBackgroundActivitySession?
    #endif
    /// Reads out each split as it ends, or nil when call-outs are off.
    private var paceCallouts: PaceCalloutTracker?
    private let speaker = CalloutSpeaker()
    /// A cue to speak, checked about once a second with the run's active time, distance and recent
    /// heart rate, such as the coach's heart-rate cue. Set it before `start`. When it and a split
    /// read-out land together, only the cue plays.
    var spokenCue: ((_ elapsed: TimeInterval, _ meters: Double, _ beatsPerMinute: Double?) -> String?)?
    /// The newest heart-rate reading, for `spokenCue`.
    private var latestHeartRate: (beatsPerMinute: Double, date: Date)?
    /// Readings older than this count as no reading.
    private static let heartRateFreshness: TimeInterval = 15
    #if os(iOS)
    /// Heart rate on the Lock Screen and in the Dynamic Island, while this run measures it.
    private var heartRateActivity: HeartRateActivityController?
    #endif

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var isRecording: Bool {
        guard let run else { return false }
        return !run.isFinished
    }

    func start(
        kind: RunKind = .free,
        intervalPlan: IntervalPlan? = nil,
        coachWorkout: CoachWorkout? = nil,
        measuresHeartRate: Bool = false
    ) {
        guard !isRecording else {
            Logger.recording.warning("A run is already being recorded.")
            return
        }
        let run = Run(kind: coachWorkout == nil ? kind : .coached)
        run.intervalPlanValue = intervalPlan ?? coachWorkout?.intervalPlan
        run.coachWorkoutValue = coachWorkout
        modelContext.insert(run)
        modelContext.saveQuietly()
        self.run = run
        paceCallouts = PaceCalloutTracker(settings: .current())
        startLocationUpdates()
        startClock()
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
        stopClock()
        guard let run else { return }
        run.finish()
        modelContext.saveQuietly()
        HealthSync.shared.saveIfEnabled(run, in: modelContext)
    }

    /// Throws the run away, along with its route and heart rate.
    func discard() {
        stopLocationUpdates()
        stopHeartRate()
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
        guard paceCallouts != nil || spokenCue != nil else { return }
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

    private func startHeartRate(at date: Date) {
        // With workouts no longer allowed, HealthKit runs the session but never collects.
        guard HealthSync.shared.access == .allowed else {
            Logger.health.info("Heart rate is on, but Health doesn't allow workouts, so this run has none.")
            return
        }
        let monitor = HeartRateMonitor()
        monitor.onReading = { [weak self] beatsPerMinute, date in
            self?.latestHeartRate = (beatsPerMinute, date)
            self?.run?.record(HeartRateSample(timestamp: date, beatsPerMinute: beatsPerMinute))
            #if os(iOS)
            self?.heartRateActivity?.record(beatsPerMinute, at: date)
            #endif
        }
        guard monitor.start(at: date) else { return }
        heartRate = monitor
        #if os(iOS)
        let activity = HeartRateActivityController()
        activity.start(at: date)
        heartRateActivity = activity
        #endif
    }

    private func stopHeartRate() {
        heartRate?.stop()
        heartRate = nil
        #if os(iOS)
        heartRateActivity?.end()
        heartRateActivity = nil
        #endif
    }

    private func receive(_ location: CLLocation) {
        guard let run, !run.isFinished else { return }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.maximumHorizontalAccuracy
        else { return }
        run.record(RouteSample(location))
        checkPaceCallout(at: location.timestamp)
    }

    /// Reads out the split that just ended, if one did, unless a cue is due at the same moment.
    private func checkPaceCallout(at date: Date) {
        guard let run, run.status == .active, paceCallouts != nil || spokenCue != nil else { return }
        let elapsed = run.activeDuration(at: date)
        let callout = paceCallouts?.update(elapsed: elapsed, meters: run.distanceMeters)
        let heartRate = latestHeartRate.flatMap { abs(date.timeIntervalSince($0.date)) <= Self.heartRateFreshness ? $0.beatsPerMinute : nil }
        if let cue = spokenCue?(elapsed, run.distanceMeters, heartRate) {
            speaker.speak(cue)
        } else if let callout {
            speaker.speak(callout.spokenText)
        }
    }
}
