//
//  HeartRateActivityController.swift
//  Wind Run
//

import ActivityKit
import Foundation
import OSLog

/// Shows a run on the Lock Screen and in the Dynamic Island: the runner's display screen, heart rate, and
/// the step under way in a structured run. An open step gets a Next button there, and every run a Pause or
/// Resume button.
///
/// Every run gets one. The app updates it on the device; nothing goes through a push server.
final class HeartRateActivityController {
    /// The system rations Live Activity updates, so readings are sent at most this often.
    static let updateInterval: TimeInterval = 5
    /// With no update for this long, the Lock Screen shows the readings as out of date. A paused run
    /// changes nothing, so it never goes out of date.
    static let staleAfter: TimeInterval = 60
    /// A heart rate older than this isn't shown, so a sensor that drops out shows a dash.
    static let heartRateFreshness: TimeInterval = 15
    /// A finished run's numbers stay on the Lock Screen this long, so the runner can see it was saved.
    static let finishedStays: TimeInterval = 15 * 60

    private var activity: Activity<HeartRateActivityAttributes>?
    private var readings: [HeartRateReading] = []
    private var lastUpdate: Date?
    private var step: RunStepState?
    private var display: DisplayScreenReadings?
    private var isPaused = false
    private var showsHeartRate = true
    /// Updates sent, and ones held back to keep within the system's ration, for the trace.
    private var sent = 0
    private var throttled = 0

    /// Starts the Live Activity, unless the runner has turned Live Activities off for Wind Run.
    func start(at date: Date, showsHeartRate: Bool = true, step: RunStepState? = nil) {
        guard activity == nil else { return }
        self.showsHeartRate = showsHeartRate
        self.step = step
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Logger.health.info("Live Activities are off for Wind Run, so heart rate and steps stay in the app.")
            Trace.log(.run, "Live Activity off for Wind Run")
            return
        }
        do {
            activity = try Activity.request(
                attributes: HeartRateActivityAttributes(startDate: date, showsHeartRate: showsHeartRate),
                content: content(at: date)
            )
            Trace.log(.run, "Live Activity started", ["heartRate": showsHeartRate, "steps": step != nil])
        } catch {
            Logger.health.error("Couldn't start the run's Live Activity: \(error)")
        }
    }

    func record(_ beatsPerMinute: Double, at date: Date) {
        guard activity != nil else { return }
        readings.append(HeartRateReading(date: date, beatsPerMinute: beatsPerMinute))
        readings.removeAll { $0.date <= date.addingTimeInterval(-HeartRateWindow.duration) }
        send(at: date, force: false)
    }

    /// Shows the step under way. A new step, a pause or a resume shows at once; a distance step's
    /// countdown follows at most every few seconds.
    func update(_ step: RunStepState?, at date: Date = .now) {
        guard activity != nil, step != self.step else { return }
        let changed = step?.number != self.step?.number || step?.isFinished != self.step?.isFinished
            || (step?.startDate == nil) != (self.step?.startDate == nil)
        self.step = step
        send(at: date, force: changed)
    }

    /// Shows the display screen's readings. They're sent at most every few seconds; a pause or a resume
    /// (`force`) shows at once, so the Lock Screen's clock stops and starts with the run.
    func update(display: DisplayScreenReadings, isPaused: Bool, at date: Date = .now, force: Bool = false) {
        guard activity != nil, display != self.display || isPaused != self.isPaused else { return }
        let pauseChanged = isPaused != self.isPaused
        self.display = display
        self.isPaused = isPaused
        send(at: date, force: force || pauseChanged)
    }

    private func send(at date: Date, force: Bool) {
        guard let activity else { return }
        if !force, let lastUpdate, date.timeIntervalSince(lastUpdate) < Self.updateInterval {
            throttled += 1
            return
        }
        lastUpdate = date
        sent += 1
        let content = content(at: date)
        Task { await activity.update(content) }
    }

    /// Takes the Live Activity away. A finished run leaves its final numbers, `finalDisplay`, on the Lock
    /// Screen for a while to show it was saved; a run thrown away goes at once.
    func end(showing finalDisplay: DisplayScreenReadings? = nil, at date: Date = .now) {
        guard let activity else { return }
        self.activity = nil
        Trace.log(.run, "Live Activity ended", ["updates": sent, "throttled": throttled, "keptOnLockScreen": finalDisplay != nil])
        guard let finalDisplay else {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        display = finalDisplay
        step = nil
        isPaused = false
        readings = []
        var state = content(at: date).state
        state.isFinished = true
        let content = ActivityContent(state: state, staleDate: nil)
        Task { await activity.end(content, dismissalPolicy: .after(date.addingTimeInterval(Self.finishedStays))) }
    }

    /// Ends any Live Activity left behind by a run that never finished, such as when the app was closed mid-run.
    static func endLeftoverActivities() {
        for activity in Activity<HeartRateActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func content(at date: Date) -> ActivityContent<HeartRateActivityAttributes.ContentState> {
        // Only a reading from the last few seconds, so a sensor that dropped out isn't shown as current.
        let latest = readings.last.flatMap { reading in
            date.timeIntervalSince(reading.date) <= Self.heartRateFreshness ? Int(reading.beatsPerMinute.rounded()) : nil
        }
        let state = HeartRateActivityAttributes.ContentState(
            beatsPerMinute: latest,
            window: HeartRateWindow(readings: readings, end: date),
            step: step,
            display: display,
            isPaused: isPaused
        )
        return ActivityContent(state: state, staleDate: isPaused ? nil : date.addingTimeInterval(Self.staleAfter))
    }
}
