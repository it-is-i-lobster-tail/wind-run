//
//  HeartRateWindow.swift
//  Wind Run
//

import Foundation

/// One heart rate reading on its way to the Live Activity.
nonisolated struct HeartRateReading: Hashable, Sendable {
    var date: Date
    var beatsPerMinute: Double
}

/// The last five minutes of heart rate, in even steps, small enough to send to a Live Activity.
///
/// A Live Activity's data has to stay under 4 KB, so readings are averaged into 60 steps of
/// five seconds, each kept as whole beats per minute. A step with no reading stays empty.
nonisolated struct HeartRateWindow: Codable, Hashable, Sendable {
    static let duration: TimeInterval = 5 * 60
    static let stepCount = 60
    static var stepDuration: TimeInterval { duration / Double(stepCount) }

    /// When the newest step ends.
    var end: Date
    /// Beats per minute for each step, oldest first. Zero means the step has no reading.
    var steps: [UInt8]

    /// A window with no readings yet.
    init(end: Date) {
        self.end = end
        self.steps = Array(repeating: 0, count: Self.stepCount)
    }

    /// Averages the readings into the steps of the five minutes up to `end`. Readings from
    /// before the window or after `end` are left out.
    init(readings: [HeartRateReading], end: Date) {
        self.init(end: end)
        let start = self.start
        var totals = Array(repeating: 0.0, count: Self.stepCount)
        var counts = Array(repeating: 0, count: Self.stepCount)
        for reading in readings where reading.date > start && reading.date <= end && reading.beatsPerMinute > 0 {
            // Each step takes in the readings up to and including its end.
            let offset = reading.date.timeIntervalSince(start) / Self.stepDuration
            let index = min(Self.stepCount - 1, max(0, Int(offset.rounded(.up)) - 1))
            totals[index] += reading.beatsPerMinute
            counts[index] += 1
        }
        for index in steps.indices where counts[index] > 0 {
            let average = (totals[index] / Double(counts[index])).rounded()
            steps[index] = UInt8(clamping: max(1, Int(average)))
        }
    }

    var start: Date { end.addingTimeInterval(-Self.duration) }

    /// The steps that have a reading, each placed at the time it ends.
    var points: [Point] {
        steps.indices.compactMap { index in
            guard steps[index] > 0 else { return nil }
            let date = start.addingTimeInterval(Double(index + 1) * Self.stepDuration)
            return Point(date: date, beatsPerMinute: Int(steps[index]))
        }
    }

    nonisolated struct Point: Hashable, Identifiable, Sendable {
        var date: Date
        var beatsPerMinute: Int

        var id: Date { date }
    }
}
