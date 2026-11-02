//
//  HeartRateActivityController.swift
//  Wind Run
//

import ActivityKit
import Foundation
import OSLog

/// Shows a run's heart rate on the Lock Screen and in the Dynamic Island.
///
/// Only runs that measure heart rate get one. The app updates it on the device; nothing goes
/// through a push server.
final class HeartRateActivityController {
    /// The system rations Live Activity updates, so readings are sent at most this often.
    static let updateInterval: TimeInterval = 5
    /// With no update for this long, the Lock Screen shows the readings as out of date.
    static let staleAfter: TimeInterval = 60

    private var activity: Activity<HeartRateActivityAttributes>?
    private var readings: [HeartRateReading] = []
    private var lastUpdate: Date?

    /// Starts the Live Activity, unless the runner has turned Live Activities off for Wind Run.
    func start(at date: Date) {
        guard activity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Logger.health.info("Live Activities are off for Wind Run, so heart rate stays in the app.")
            return
        }
        do {
            activity = try Activity.request(
                attributes: HeartRateActivityAttributes(startDate: date),
                content: content(at: date)
            )
        } catch {
            Logger.health.error("Couldn't start the heart rate Live Activity: \(error.localizedDescription)")
        }
    }

    func record(_ beatsPerMinute: Double, at date: Date) {
        guard let activity else { return }
        readings.append(HeartRateReading(date: date, beatsPerMinute: beatsPerMinute))
        readings.removeAll { $0.date <= date.addingTimeInterval(-HeartRateWindow.duration) }
        if let lastUpdate, date.timeIntervalSince(lastUpdate) < Self.updateInterval {
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
            window: HeartRateWindow(readings: readings, end: date)
        )
        return ActivityContent(state: state, staleDate: date.addingTimeInterval(Self.staleAfter))
    }
}
