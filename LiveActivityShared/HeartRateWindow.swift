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

    /// Populated steps that begin a new line after a buffered pause. Older activity payloads omit this.
    var breaks: [Int]?

    /// A window with no readings yet.
    init(end: Date) {
        self.end = end
        self.steps = Array(repeating: 0, count: Self.stepCount)
    }

    /// Averages the readings into the steps of the five minutes up to `end`. Readings from
    /// before the window or after `end` are left out.
    init(readings: [HeartRateReading], end: Date, buffers: ChartPauseBuffers = ChartPauseBuffers()) {
        self.init(end: end)
        let start = self.start
        var totals = Array(repeating: 0.0, count: Self.stepCount)
        var counts = Array(repeating: 0, count: Self.stepCount)
        for reading in readings where reading.date > start && reading.date <= end && reading.beatsPerMinute > 0 {
            // Each step takes in the readings up to and including its end.
            let offset = reading.date.timeIntervalSince(start) / Self.stepDuration
            let index = min(Self.stepCount - 1, max(0, Int(offset.rounded(.up)) - 1))
            let plottedDate = start.addingTimeInterval(Double(index + 1) * Self.stepDuration)
            guard buffers.segment(from: reading.date, through: plottedDate) != nil else { continue }
            totals[index] += reading.beatsPerMinute
            counts[index] += 1
        }
        var previousSegment: Int?
        var breaks: [Int] = []
        for index in steps.indices where counts[index] > 0 {
            let date = start.addingTimeInterval(Double(index + 1) * Self.stepDuration)
            let segment = buffers.segment(from: date, through: date)
            if let previousSegment, previousSegment != segment { breaks.append(index) }
            previousSegment = segment
            let average = (totals[index] / Double(counts[index])).rounded()
            steps[index] = UInt8(clamping: max(1, Int(average)))
        }
        self.breaks = breaks.isEmpty ? nil : breaks
    }

    var start: Date { end.addingTimeInterval(-Self.duration) }

    /// The steps that have a reading, each placed at the time it ends.
    var points: [Point] {
        var segment = 0
        let points: [Point] = steps.indices.compactMap { index in
            guard steps[index] > 0 else { return nil }
            let date = start.addingTimeInterval(Double(index + 1) * Self.stepDuration)
            if breaks?.contains(index) == true { segment += 1 }
            return Point(date: date, beatsPerMinute: Double(steps[index]), segment: segment)
        }
        return points.chartSmoothed(value: \.beatsPerMinute, segment: \.segment)
    }

    nonisolated struct Point: Hashable, Identifiable, Sendable {
        var date: Date
        var beatsPerMinute: Double
        var segment = 0

        var id: Date { date }
    }
}
