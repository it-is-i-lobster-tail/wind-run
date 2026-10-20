//
//  RunCadence.swift
//  Wind Run
//

import Foundation

/// Step rate from the step counts the run's workout session collected. Worked out on the device each
/// time the coach is called and never stored with the plan.
enum RunCadence {
    /// Step counts coarser than this can't show a lock against heart rate.
    static let finestUsable: TimeInterval = 60
    /// Step counts must cover this share of the running time to be read at all.
    static let minimumCoverage = 0.8
    /// PZ-10 check 4: heart rate within this many beats of step rate...
    static let lockMargin = 3.0
    /// ...for longer than this is a cadence lock.
    static let lockDuration: TimeInterval = 60

    /// Mean steps per minute over the running time, walks left out, or nil without usable counts.
    static func mean(_ samples: [StepCountSample], run: Run, walks: [ClosedRange<TimeInterval>]) -> Double? {
        let running = samples.filter { sample in
            let middle = run.activeTime(at: sample.start.addingTimeInterval(sample.end.timeIntervalSince(sample.start) / 2))
            return !walks.contains { $0.contains(middle) }
        }
        let seconds = running.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        guard seconds > 0 else { return nil }
        return running.reduce(0) { $0 + $1.count } / seconds * 60
    }

    /// Whether heart rate locked onto step rate for more than a minute (PZ-10 check 4). Nil when the
    /// counts are missing, patchy or coarser than a minute, so the check is unknown.
    static func lock(heartRate: [RunHeartRateReading.Sample], steps samples: [StepCountSample], movingSeconds: TimeInterval) -> Bool? {
        guard !samples.isEmpty, movingSeconds > 0,
              samples.allSatisfy({ $0.end.timeIntervalSince($0.start) <= finestUsable })
        else { return nil }
        let covered = samples.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        guard covered / movingSeconds >= minimumCoverage else { return nil }

        var lockedSince: Date?
        for reading in heartRate.sorted(by: { $0.date < $1.date }) {
            let rate = samples.first { $0.start <= reading.date && reading.date <= $0.end }?.stepsPerMinute
            if let rate, abs(reading.beatsPerMinute - rate) <= lockMargin {
                let since = lockedSince ?? reading.date
                lockedSince = since
                if reading.date.timeIntervalSince(since) > lockDuration { return true }
            } else {
                lockedSince = nil
            }
        }
        return false
    }
}
