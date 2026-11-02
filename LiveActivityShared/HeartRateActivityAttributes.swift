//
//  HeartRateActivityAttributes.swift
//  Wind Run
//

import ActivityKit
import Foundation

/// What the run's Live Activity shows, shared by the app and the Live Activity extension: heart rate when the
/// run measures it, and the step under way in a structured run.
nonisolated struct HeartRateActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// The newest reading in whole beats per minute, or nil until one arrives.
        var beatsPerMinute: Int?
        /// The last five minutes, for the graph.
        var window: HeartRateWindow
        /// The step under way, for a structured run.
        var step: RunStepState?
    }

    /// When the run started.
    var startDate: Date
    /// False for a structured run without heart rate, which shows only its steps.
    var showsHeartRate: Bool
}
