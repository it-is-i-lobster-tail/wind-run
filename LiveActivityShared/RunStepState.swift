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
    var phase: Phase?

    nonisolated enum Phase: String, Codable, CaseIterable, Sendable {
        case warmup
        case main
        case cooldown
    }

    /// How the step's clock reads on the Lock Screen and in the Dynamic Island.
    nonisolated enum Clock: Equatable, Sendable {
        /// Down to the end of a timed step while the run is going.
        case countdown(ClosedRange<Date>)
        /// What the app last wrote, such as the distance left or the time while paused.
        case text(String)
        /// Up from the start of an open step while the run is going.
        case countUp(Date)
        /// Nothing to show.
        case none
    }

    /// The step's clock: down to the end of a timed step, else what the app last wrote, else up from the
    /// start of an open one.
    var clock: Clock {
        if let start = startDate, let end = endDate, start <= end {
            .countdown(start...end)
        } else if let detail {
            .text(detail)
        } else if let start = startDate {
            .countUp(start)
        } else {
            .none
        }
    }
}

/// Ends the step under way, from the Live Activity's Next button. It runs in the app, which holds the run.
nonisolated struct NextStepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Next step"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run { ActiveRunControl.perform("Next step", ActiveRunControl.nextStep) }
        return .result()
    }
}

/// Pauses the run, from the Lock Screen or the Dynamic Island. It runs in the app, which holds the run.
nonisolated struct PauseRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause run"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run { ActiveRunControl.perform("Pause", ActiveRunControl.pause) }
        return .result()
    }
}

/// Starts a paused run again, from the Lock Screen or the Dynamic Island.
nonisolated struct ResumeRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume run"
    static let isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await MainActor.run { ActiveRunControl.perform("Resume", ActiveRunControl.resume) }
        return .result()
    }
}

/// How the Live Activity's buttons reach the run under way. The app sets them while a run records: Next step
/// for a structured run, Pause and Resume for every run.
enum ActiveRunControl {
    @MainActor static var nextStep: (() -> Void)?
    @MainActor static var pause: (() -> Void)?
    @MainActor static var resume: (() -> Void)?
    /// Hears each tap and whether a run was there to take it, for the app's trace.
    @MainActor static var tapped: ((_ control: String, _ handled: Bool) -> Void)?

    @MainActor static func perform(_ control: String, _ action: (() -> Void)?) {
        tapped?(control, action != nil)
        action?()
    }
}
