//
//  FootstepLog.swift
//  Wind Run
//

import Foundation

/// Turns the pedometer's running total into step counts over stretches of the run, in the same form the
/// workout session's step counts take, so the coach reads either the same way.
///
/// Steps taken while the run is paused are left out. Stretches are joined up to `bucket` long, so a long
/// run's counts stay small enough to sync.
struct FootstepLog {
    /// Joined stretches are at most this long. Well under the minute the coach's cadence check needs.
    static let bucket: TimeInterval = 15
    /// A gap between updates longer than this was a stop: the new steps are put at its end.
    static let longestGap: TimeInterval = 10

    private(set) var samples: [StepCountSample] = []
    /// Steps counted while the run was going.
    private(set) var total: Double = 0
    private var last: (date: Date, steps: Double)

    init(start: Date) {
        last = (start, 0)
    }

    /// Takes the pedometer's total since the run started, and its steps a minute when it knows them.
    /// Returns whether any new steps were taken.
    @discardableResult
    mutating func record(totalSteps: Double, cadence: Double?, at date: Date, counts: Bool) -> Bool {
        guard date > last.date else { return false }
        let count = totalSteps - last.steps
        defer { last = (date, max(last.steps, totalSteps)) }
        guard count > 0 else { return false }
        guard counts else { return true }

        var start = last.date
        if date.timeIntervalSince(start) > Self.longestGap {
            // Pedometer updates stop when the runner does, so this stretch was mostly standing.
            let walking = cadence.flatMap { $0 > 0 ? count / $0 * 60 : nil } ?? Self.longestGap
            start = max(start, date.addingTimeInterval(-min(walking, Self.longestGap)))
        }
        if var previous = samples.last, previous.end == start, date.timeIntervalSince(previous.start) <= Self.bucket {
            previous.end = date
            previous.count += count
            samples[samples.count - 1] = previous
        } else {
            samples.append(StepCountSample(start: start, end: date, count: count))
        }
        total += count
        return true
    }
}
