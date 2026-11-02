//
//  HeartRateActivityController.swift
//  Wind Run
//

import ActivityKit
import Foundation
import OSLog

/// Shows a run's heart rate, and the step under way in a structured run, on the Lock Screen and in the
/// Dynamic Island. An open step gets a Next button there.
///
/// Runs that measure heart rate or have steps get one. The app updates it on the device; nothing goes
/// through a push server.
final class HeartRateActivityController {
    /// The system rations Live Activity updates, so readings are sent at most this often.
    static let updateInterval: TimeInterval = 5
    /// With no update for this long, the Lock Screen shows the readings as out of date.
    static let staleAfter: TimeInterval = 60

    private var activity: Activity<HeartRateActivityAttributes>?
    private var readings: [HeartRateReading] = []
    private var lastUpdate: Date?
    private var step: RunStepState?
    private var showsHeartRate = true

    /// Starts the Live Activity, unless the runner has turned Live Activities off for Wind Run.
    func start(at date: Date, showsHeartRate: Bool = true, step: RunStepState? = nil) {
        guard activity == nil else { return }
        self.showsHeartRate = showsHeartRate
        self.step = step
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Logger.health.info("Live Activities are off for Wind Run, so heart rate and steps stay in the app.")
            return
        }
        do {
            activity = try Activity.request(
                attributes: HeartRateActivityAttributes(startDate: date, showsHeartRate: showsHeartRate),
                content: content(at: date)
            )
        } catch {
            Logger.health.error("Couldn't start the run's Live Activity: \(error.localizedDescription)")
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

    private func send(at date: Date, force: Bool) {
        guard let activity else { return }
        if !force, let lastUpdate, date.timeIntervalSince(lastUpdate) < Self.updateInterval {
            return
        }
        lastUpdate = date
        let content = content(at: date)
        Task { await activity.update(content) }
    }

    /// Takes the Live Activity away when the run is finished or thrown away.
    func end() {
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Ends any Live Activity left behind by a run that never finished, such as when the app was closed mid-run.
    static func endLeftoverActivities() {
        for activity in Activity<HeartRateActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private func content(at date: Date) -> ActivityContent<HeartRateActivityAttributes.ContentState> {
        let latest = readings.last.map { Int($0.beatsPerMinute.rounded()) }
        let state = HeartRateActivityAttributes.ContentState(
            beatsPerMinute: latest,
            window: HeartRateWindow(readings: readings, end: date),
            step: step
        )
        // Steps only update when they change, so without heart rate nothing goes out of date.
        return ActivityContent(state: state, staleDate: showsHeartRate ? date.addingTimeInterval(Self.staleAfter) : nil)
    }
}
