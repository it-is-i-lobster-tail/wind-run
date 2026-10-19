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

    var runValue: Run?

    init(timestamp: Date, beatsPerMinute: Double) {
        self.timestampValue = timestamp
        self.beatsPerMinuteValue = beatsPerMinute
    }
}

extension HeartRateSample {
    var timestamp: Date { timestampValue }
    var beatsPerMinute: Double { beatsPerMinuteValue }
}
