import Foundation

/// The excluded wall-clock intervals, including the transitions into and out of each stop.
nonisolated struct ChartPauseBuffers {
    private let intervals: [ClosedRange<Date>]

    init(_ pauses: [(start: Date, end: Date?)] = []) {
        let buffer: TimeInterval = 15
        intervals = pauses.sorted { $0.start < $1.start }.map { pause in
            pause.start.addingTimeInterval(-buffer)...(pause.end?.addingTimeInterval(buffer) ?? .distantFuture)
        }
    }

    var isEmpty: Bool { intervals.isEmpty }

    /// Returns the stretch containing the whole measurement, or nil if any part touches a buffer.
    func segment(from start: Date, through end: Date) -> Int? {
        for (index, interval) in intervals.enumerated() {
            if end < interval.lowerBound { return index }
            if start <= interval.upperBound { return nil }
        }
        return intervals.count
    }
}

extension Array {
    /// One centered pass over the original chart values. Both ends of each stretch keep their readings.
    nonisolated func chartSmoothed(value: WritableKeyPath<Element, Double>, segment: KeyPath<Element, Int>) -> Self {
        guard count >= 3 else { return self }
        var result = self
        for i in 1..<(count - 1) {
            let previous = self[i - 1], current = self[i], next = self[i + 1]
            guard previous[keyPath: segment] == current[keyPath: segment],
                  next[keyPath: segment] == current[keyPath: segment] else { continue }
            result[i][keyPath: value] = 0.1 * previous[keyPath: value]
                + 0.8 * current[keyPath: value] + 0.1 * next[keyPath: value]
        }
        return result
    }
}
