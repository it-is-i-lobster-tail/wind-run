//
//  HeartRateActivityAttributes.swift
//  Wind Run
//

import ActivityKit
import Foundation

/// What the heart rate Live Activity shows, shared by the app and the Live Activity extension.
nonisolated struct HeartRateActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        /// The newest reading in whole beats per minute, or nil until one arrives.
        var beatsPerMinute: Int?
        /// The last five minutes, for the graph.
        var window: HeartRateWindow
    }

    /// When the run started.
    var startDate: Date
}
