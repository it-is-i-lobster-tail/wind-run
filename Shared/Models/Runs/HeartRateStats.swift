//
//  HeartRateStats.swift
//  Wind Run
//

import Foundation

/// Lowest, highest, mean and spread of a run's heart rate readings.
///
/// Every reading counts the same, however long the gap to the next one.
struct HeartRateStats: Equatable {
    let minimum: Double
    let maximum: Double
    let mean: Double
    /// How far readings stray from the mean, in beats per minute squared. Population
    /// variance, since the readings are the whole run rather than a sample of it.
    let variance: Double

    /// The spread in beats per minute, which reads more easily than variance.
    var standardDeviation: Double { variance.squareRoot() }

    /// Nil when there are no readings.
    init?(_ beatsPerMinute: [Double]) {
        guard let minimum = beatsPerMinute.min(), let maximum = beatsPerMinute.max() else { return nil }
        let count = Double(beatsPerMinute.count)
        let mean = beatsPerMinute.reduce(0, +) / count
        self.minimum = minimum
        self.maximum = maximum
        self.mean = mean
        self.variance = beatsPerMinute.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / count
    }
}

/// One heart rate reading placed on the run's clock, for charting.
struct HeartRatePoint: Hashable {
    /// Time spent running when the reading was taken, leaving out pauses.
    let activeTime: TimeInterval
    let beatsPerMinute: Double
}
