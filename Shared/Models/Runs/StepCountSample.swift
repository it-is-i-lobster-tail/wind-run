//
//  StepCountSample.swift
//  Wind Run
//

import Foundation

/// Steps counted over a stretch of a run, as the workout session collected them.
struct StepCountSample: Codable, Equatable {
    var start: Date
    var end: Date
    var count: Double

    /// Steps per minute over the stretch.
    var stepsPerMinute: Double? {
        let seconds = end.timeIntervalSince(start)
        return seconds > 0 ? count / seconds * 60 : nil
    }
}
