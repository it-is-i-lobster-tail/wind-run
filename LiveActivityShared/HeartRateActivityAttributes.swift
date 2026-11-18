//
//  HeartRateActivityAttributes.swift
//  Wind Run
//

import ActivityKit
import Foundation

/// What the run's Live Activity shows, shared by the app and the Live Activity extension: the runner's display
/// screen, heart rate for the Dynamic Island when the run measures it, and the step under way in a structured run.
nonisolated struct HeartRateActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// The newest reading in whole beats per minute, or nil until one arrives.
        var beatsPerMinute: Int?
        /// The last five minutes, for the graph.
        var window: HeartRateWindow
        /// The step under way, for a structured run.
        var step: RunStepState?
        /// The runner's display screen as the app last wrote it, the same readings as the run screen.
        var display: DisplayScreenReadings? = nil
        /// True while the run is paused. Nil from an older app, as not paused.
        var isPaused: Bool? = nil
        /// True once the run is finished and saved: the activity stays a while with the final numbers.
        var isFinished: Bool? = nil

        /// Whether the run is paused, with nil from an older app read as not paused.
        var runIsPaused: Bool { isPaused == true }
        /// Whether the run is finished and saved, with nil from an older app read as not finished.
        var runIsFinished: Bool { isFinished == true }
    }

    /// When the run started.
    var startDate: Date
    /// False for a run without heart rate.
    var showsHeartRate: Bool
}
