//
//  PaceCalloutTracker.swift
//  Wind Run
//

import Foundation

/// When a split ends: every so many meters, or every so many seconds of running.
enum PaceCalloutTrigger: Equatable {
    case distance(meters: Double)
    case time(seconds: TimeInterval)
}

/// One split to read out: where the runner is, and how fast that split was.
struct PaceCallout: Equatable {
    enum Mark: Equatable {
        /// Total distance covered when the split ended.
        case distance(meters: Double)
        /// Total running time when the split ended.
        case time(seconds: TimeInterval)
    }

    let mark: Mark
    /// The pace of this split alone, not the whole run. Nil when the runner barely moved.
    let secondsPerKilometer: TimeInterval?
    let unit: DistanceUnit

    /// "Quarter mile, pace 2 minutes 13 seconds per mile."
    var spokenText: String {
        let lead: String = switch mark {
        case .distance(let meters): SpokenFormat.distance(meters, unit: unit)
        case .time(let seconds): SpokenFormat.duration(seconds)
        }
        guard let pace = SpokenFormat.pace(secondsPerKilometer, unit: unit) else {
            return lead.capitalizingFirstLetter + "."
        }
        return "\(lead.capitalizingFirstLetter), pace \(pace)."
    }

    /// What the first call-out of a run at a steady 5:20 /km would sound like, for the settings screen.
    static func sample(for settings: PaceCalloutSettings) -> PaceCallout? {
        let mark: Mark
        switch settings.trigger {
        case .distance(let meters): mark = .distance(meters: meters)
        case .time(let seconds): mark = .time(seconds: seconds)
        case nil: return nil
        }
        return PaceCallout(mark: mark, secondsPerKilometer: 320, unit: settings.unit)
    }
}

/// Follows a run's clock and distance and says when a split has ended.
///
/// Feed it every GPS fix and a clock tick about once a second. Time is running time, so pauses
/// don't count, and the exact moment a split ended is worked out between updates.
struct PaceCalloutTracker {
    private struct Point {
        var elapsed: TimeInterval
        var meters: Double
    }

    let trigger: PaceCalloutTrigger
    let unit: DistanceUnit

    private var splitsDone = 0
    /// Where the last split ended.
    private var splitStart = Point(elapsed: 0, meters: 0)
    /// The newest update, for time splits.
    private var latest = Point(elapsed: 0, meters: 0)
    /// The newest update that added distance, for distance splits. Clock ticks between
    /// GPS fixes don't move it, so a split's end is placed between two real fixes.
    private var latestMove = Point(elapsed: 0, meters: 0)

    init(trigger: PaceCalloutTrigger, unit: DistanceUnit) {
        self.trigger = trigger
        self.unit = unit
    }

    init?(settings: PaceCalloutSettings) {
        guard let trigger = settings.trigger else { return nil }
        self.init(trigger: trigger, unit: settings.unit)
    }

    /// Returns a call-out when this update finishes a split. If a GPS jump finishes more
    /// than one, only the newest is returned so the runner doesn't hear a backlog.
    mutating func update(elapsed: TimeInterval, meters: Double) -> PaceCallout? {
        switch trigger {
        case .distance(let interval):
            return updateDistance(elapsed: elapsed, meters: meters, interval: interval)
        case .time(let interval):
            return updateTime(elapsed: elapsed, meters: meters, interval: interval)
        }
    }

    private mutating func updateDistance(elapsed: TimeInterval, meters: Double, interval: Double) -> PaceCallout? {
        guard meters > latestMove.meters else { return nil }
        let from = latestMove
        latestMove = Point(elapsed: elapsed, meters: meters)

        var callout: PaceCallout?
        while meters >= Double(splitsDone + 1) * interval {
            let mark = Double(splitsDone + 1) * interval
            let fraction = (mark - from.meters) / (meters - from.meters)
            let reachedAt = from.elapsed + fraction * (elapsed - from.elapsed)
            callout = PaceCallout(
                mark: .distance(meters: mark),
                secondsPerKilometer: Self.pace(seconds: reachedAt - splitStart.elapsed, meters: interval),
                unit: unit
            )
            splitStart = Point(elapsed: reachedAt, meters: mark)
            splitsDone += 1
        }
        return callout
    }

    private mutating func updateTime(elapsed: TimeInterval, meters: Double, interval: TimeInterval) -> PaceCallout? {
        // A GPS fix can be stamped a moment before the last clock tick. The next tick picks up its distance.
        guard elapsed >= latest.elapsed else { return nil }
        let from = latest
        latest = Point(elapsed: elapsed, meters: meters)

        var callout: PaceCallout?
        while elapsed >= Double(splitsDone + 1) * interval {
            let mark = Double(splitsDone + 1) * interval
            let fraction = elapsed > from.elapsed ? (mark - from.elapsed) / (elapsed - from.elapsed) : 1
            let metersAtMark = from.meters + fraction * (meters - from.meters)
            callout = PaceCallout(
                mark: .time(seconds: mark),
                secondsPerKilometer: Self.pace(seconds: interval, meters: metersAtMark - splitStart.meters),
                unit: unit
            )
            splitStart = Point(elapsed: mark, meters: metersAtMark)
            splitsDone += 1
        }
        return callout
    }

    private static func pace(seconds: TimeInterval, meters: Double) -> TimeInterval? {
        guard meters > 0, seconds > 0 else { return nil }
        return seconds / (meters / 1_000)
    }
}

private extension String {
    var capitalizingFirstLetter: String {
        prefix(1).uppercased() + dropFirst()
    }
}
