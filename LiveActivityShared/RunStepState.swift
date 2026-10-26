//
//  RunStepState.swift
//  Wind Run
//

import AppIntents
import Foundation

/// The step a structured run is on, for the Live Activity. The app writes the words; the Live Activity
/// only lays them out, and counts time on its own between updates.
nonisolated struct RunStepState: Codable, Hashable, Sendable {
    /// "Work", "Walk".
    var name: String
    /// 1-based place in the workout, and how many steps it has.
    var number: Int
    var count: Int
    /// When the step started in clock time, while the run is going, for the step's own clock.
    var startDate: Date?
    /// When a timed step ends in clock time, while the run is going, for a countdown.
    var endDate: Date?
    /// What to show when the clock can't run on its own: distance left, or the time while paused.
    var detail: String?
    /// The Next button's title, for an open step that ends on a tap; nil for steps that end on their own.
    var nextTitle: String?
    /// True once every step is done.
    var isFinished: Bool
}

/// Ends the step under way, from the Live Activity's Next button. It runs in the app, which holds the run.
nonisolated struct NextStepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Next step"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run { ActiveRunControl.nextStep?() }
        return .result()
    }
}

/// How the Live Activity's buttons reach the run under way. The app sets it while a structured run records.
enum ActiveRunControl {
    @MainActor static var nextStep: (() -> Void)?
}
