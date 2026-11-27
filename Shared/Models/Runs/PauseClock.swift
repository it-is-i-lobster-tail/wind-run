//
//  PauseClock.swift
//  Wind Run
//

import Foundation

/// A run's pauses as plain dates, sorted, for working out running time and whether a moment was paused at
/// thousands of moments, as the summary does for every fix. `Run.activeTime(at:)` reads every pause from the
/// store each time it's asked; this reads them once and looks each moment up with a binary search.
nonisolated struct PauseClock {
    private let start: Date
    private let starts: [Date]
    private let ends: [Date?]
    /// Paused time in the pauses before each one, counting an open pause as nothing.
    private let pausedBefore: [TimeInterval]
    /// Pauses that overlap, which recording never makes, are added up one by one, as the run does.
    private let overlaps: Bool

    init(start: Date, pauses: [(start: Date, end: Date?)]) {
        self.start = start
        let sorted = pauses.sorted { $0.start < $1.start }
        starts = sorted.map(\.start)
        ends = sorted.map(\.end)
        var total = 0.0
        var before: [TimeInterval] = []
        var overlaps = false
        for (index, pause) in sorted.enumerated() {
            before.append(total)
            total += max(0, (pause.end ?? pause.start).timeIntervalSince(pause.start))
            if index + 1 < sorted.count, (pause.end ?? .distantFuture) > sorted[index + 1].start { overlaps = true }
        }
        pausedBefore = before
        self.overlaps = overlaps
    }

    var isEmpty: Bool { starts.isEmpty }

    /// How many pauses start at or before `date`.
    private func count(startingBy date: Date) -> Int {
        var low = 0, high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] <= date { low = middle + 1 } else { high = middle }
        }
        return low
    }

    private func duration(_ index: Int, at date: Date) -> TimeInterval {
        let end = min(ends[index] ?? date, date)
        return max(0, end.timeIntervalSince(starts[index]))
    }

    /// Time spent paused up to `date`, the same as `Run.pausedTime(at:)`.
    func pausedTime(at date: Date) -> TimeInterval {
        if overlaps {
            return starts.indices.reduce(0) { $0 + duration($1, at: date) }
        }
        let count = count(startingBy: date)
        guard count > 0 else { return 0 }
        return pausedBefore[count - 1] + duration(count - 1, at: date)
    }

    /// Time spent running from the start up to `date`, the same as `Run.activeTime(at:)`.
    func activeTime(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSince(start) - pausedTime(at: date))
    }

    /// Whether `date` falls inside a pause, the same as asking each `RunPause.contains`.
    func contains(_ date: Date) -> Bool {
        if overlaps {
            return starts.indices.contains { date >= starts[$0] && date < (ends[$0] ?? .distantFuture) }
        }
        let count = count(startingBy: date)
        guard count > 0 else { return false }
        return date < (ends[count - 1] ?? .distantFuture)
    }

    /// Whether a pause starts at or after `from` and before `to`.
    func hasPauseStarting(from: Date, before to: Date) -> Bool {
        var low = 0, high = starts.count
        while low < high {
            let middle = (low + high) / 2
            if starts[middle] < from { low = middle + 1 } else { high = middle }
        }
        return low < starts.count && starts[low] < to
    }
}
