//
//  HeartRateSample.swift
//  Wind Run
//

import Foundation
import SwiftData

/// One heart rate reading taken during a run.
@Model
final class HeartRateSample {
    var timestampValue: Date = Date.now
    var beatsPerMinuteValue: Double = 0
    /// What measured it (`HeartRateSource`'s raw value), or nil when it wasn't known, as for every
    /// reading recorded before sources were found on their own.
    var sourceValue: String?

    var runValue: Run?

    init(timestamp: Date, beatsPerMinute: Double, source: HeartRateSource? = nil) {
        self.timestampValue = timestamp
        self.beatsPerMinuteValue = beatsPerMinute
        self.sourceValue = source?.rawValue
    }
}

extension HeartRateSample {
    var timestamp: Date { timestampValue }
    var beatsPerMinute: Double { beatsPerMinuteValue }
    var source: HeartRateSource? { sourceValue.flatMap(HeartRateSource.init(rawValue:)) }
}
