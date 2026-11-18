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

/// One pace to read out, and which kind it is.
struct PaceReading: Equatable {
    let kind: PaceKind
    /// Nil when the runner barely moved.
    let secondsPerKilometer: TimeInterval?
}

/// One split to read out: where the runner is, and the paces they picked to hear.
struct PaceCallout: Equatable {
    enum Mark: Equatable {
        /// Total distance covered when the split ended.
        case distance(meters: Double)
        /// Total running time when the split ended.
        case time(seconds: TimeInterval)
    }

    let mark: Mark
    /// In the order they're said.
    let readings: [PaceReading]
    let unit: DistanceUnit

    init(mark: Mark, readings: [PaceReading], unit: DistanceUnit) {
        self.mark = mark
        self.readings = readings
        self.unit = unit
    }

    /// "Quarter mile, pace 2 minutes 13 seconds per mile." With more paces picked:
    /// "1 kilometer, pace 5 minutes per kilometer, average pace 5 minutes 20 seconds per kilometer."
    var spokenText: String {
        let lead: String = switch mark {
        case .distance(let meters): SpokenFormat.distance(meters, unit: unit)
        case .time(let seconds): SpokenFormat.duration(seconds)
        }
        let paces = readings.compactMap { reading in
            SpokenFormat.pace(reading.secondsPerKilometer, unit: unit).map { "\(reading.kind.spokenLabel(unit: unit)) \($0)" }
        }
        return ([lead.capitalizingFirstLetter] + paces).joined(separator: ", ") + "."
    }

    /// What a call-out partway into a run would sound like, for the settings screen: a 5:20 /km split,
    /// a 5:10 last kilometer or mile, a 5:30 average, and 5:15 right now.
    static func sample(for settings: PaceCalloutSettings) -> PaceCallout? {
        let mark: Mark
        switch settings.trigger {
        case .distance(let meters): mark = .distance(meters: meters)
        case .time(let seconds): mark = .time(seconds: seconds)
        case nil: return nil
        }
        let readings = settings.paces.map { kind in
            let pace: TimeInterval = switch kind {
            case .split: 320
            case .lastUnit: 310
            case .average: 330
            case .current: 315
            }
            return PaceReading(kind: kind, secondsPerKilometer: pace)
        }
        return PaceCallout(mark: mark, readings: readings, unit: settings.unit)
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

        /// Where the run began. resume() doesn't move it, so average pace, and the last kilometer or mile
        /// before the first whole one, stay measured from here.
        static let runStart = Point(elapsed: 0, meters: 0)
    }

    let trigger: PaceCalloutTrigger
    let unit: DistanceUnit
    let paces: [PaceKind]

    private var splitsDone = 0
    /// Where the last split ended.
    private var splitStart = Point(elapsed: 0, meters: 0)
    /// The newest update, for time splits.
    private var latest = Point(elapsed: 0, meters: 0)
    /// The newest update that added distance, for distance splits. Clock ticks between
    /// GPS fixes don't move it, so a split's end is placed between two real fixes.
    private var latestMove = Point(elapsed: 0, meters: 0)
    /// The updates the tracker went by, oldest first, back far enough to cover the last
    /// kilometer or mile and the last 30 seconds. Starts at the start of the run.
    private var history = [Point(elapsed: 0, meters: 0)]

    init(trigger: PaceCalloutTrigger, unit: DistanceUnit, paces: [PaceKind] = PaceCalloutSettings.defaultPaceKinds) {
        self.trigger = trigger
        self.unit = unit
        self.paces = paces
    }

    init?(settings: PaceCalloutSettings) {
        guard let trigger = settings.trigger else { return nil }
        self.init(trigger: trigger, unit: settings.unit, paces: settings.paces)
    }

    /// Carries on from partway into a run, such as one picked up again after the app was closed, so the
    /// splits already run aren't read out again. The split under way is measured from here.
    mutating func resume(elapsed: TimeInterval, meters: Double) {
        let point = Point(elapsed: elapsed, meters: meters)
        switch trigger {
        case .distance(let interval): splitsDone = interval > 0 ? Int(meters / interval) : 0
        case .time(let interval): splitsDone = interval > 0 ? Int(elapsed / interval) : 0
        }
        splitStart = point
        latest = point
        latestMove = point
        history = [point]
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
        history.append(latestMove)

        return passSplits(upTo: meters, interval: interval, end: { mark in
            let fraction = (mark - from.meters) / (meters - from.meters)
            let reachedAt = from.elapsed + fraction * (elapsed - from.elapsed)
            return Point(elapsed: reachedAt, meters: mark)
        }, mark: { .distance(meters: $0) })
    }

    private mutating func updateTime(elapsed: TimeInterval, meters: Double, interval: TimeInterval) -> PaceCallout? {
        // A GPS fix can be stamped a moment before the last clock tick. The next tick picks up its distance.
        guard elapsed >= latest.elapsed else { return nil }
        let from = latest
        latest = Point(elapsed: elapsed, meters: meters)
        history.append(latest)

        return passSplits(upTo: elapsed, interval: interval, end: { mark in
            let fraction = elapsed > from.elapsed ? (mark - from.elapsed) / (elapsed - from.elapsed) : 1
            return Point(elapsed: mark, meters: from.meters + fraction * (meters - from.meters))
        }, mark: { .time(seconds: $0) })
    }

    /// Ends every split that `value` has reached, distance or running time, and returns the newest one's
    /// call-out. `end` places a split's end between the last two updates, from where along the axis it is,
    /// and `mark` says where it is for the runner. Each split is measured from where the one before ended.
    private mutating func passSplits(
        upTo value: Double,
        interval: Double,
        end: (Double) -> Point,
        mark: (Double) -> PaceCallout.Mark
    ) -> PaceCallout? {
        var callout: PaceCallout?
        var passed = 0
        while value >= Double(splitsDone + 1) * interval {
            let target = Double(splitsDone + 1) * interval
            let splitEnd = end(target)
            callout = PaceCallout(mark: mark(target), readings: readings(at: splitEnd), unit: unit)
            splitStart = splitEnd
            splitsDone += 1
            passed += 1
        }
        Self.traceSkipped(passed, upTo: splitsDone)
        forgetOld()
        return callout
    }

    /// One update that finished more than one split, such as a GPS jump out of a tunnel, reads out only the
    /// newest. Traced so a runner's "it skipped a call-out" can be told apart from one that never fired.
    private static func traceSkipped(_ passed: Int, upTo split: Int) {
        guard passed > 1 else { return }
        Trace.log(.callout, "Splits passed at once", ["count": passed, "spoken": 1, "split": split])
    }

    /// The picked paces for a split ending at `end`.
    private func readings(at end: Point) -> [PaceReading] {
        paces.compactMap { kind in
            switch kind {
            case .split:
                return PaceReading(kind: kind, secondsPerKilometer: Self.pace(from: splitStart, to: end))
            case .lastUnit:
                // When every split is exactly one kilometer or mile, this would just say the split's pace again.
                if paces.contains(.split), case .distance(let interval) = trigger, abs(interval - unit.meters) < 1 {
                    return nil
                }
                // Before the first whole unit, it's the pace since the start.
                let start = end.meters > unit.meters
                    ? Point(elapsed: elapsed(atMeters: end.meters - unit.meters), meters: end.meters - unit.meters)
                    : Point.runStart
                return PaceReading(kind: kind, secondsPerKilometer: Self.pace(from: start, to: end))
            case .average:
                return PaceReading(kind: kind, secondsPerKilometer: Self.pace(from: Point.runStart, to: end))
            case .current:
                let back = max(0, end.elapsed - PaceKind.currentWindow)
                let start = Point(elapsed: back, meters: meters(atElapsed: back))
                return PaceReading(kind: kind, secondsPerKilometer: Self.pace(from: start, to: end))
            }
        }
    }

    /// Drops updates no future call-out reaches back to, keeping one before the cutoff to measure from.
    private mutating func forgetOld() {
        guard let newest = history.last else { return }
        let meters = newest.meters - unit.meters
        let elapsed = newest.elapsed - PaceKind.currentWindow
        var drop = 0
        while drop + 2 < history.count, history[drop + 1].meters <= meters, history[drop + 1].elapsed <= elapsed {
            drop += 1
        }
        history.removeFirst(drop)
    }

    /// When the runner had covered `target` meters, between the updates either side of it.
    private func elapsed(atMeters target: Double) -> TimeInterval {
        guard let after = history.firstIndex(where: { $0.meters >= target }) else { return history.last?.elapsed ?? 0 }
        guard after > 0 else { return history[after].elapsed }
        let a = history[after - 1], b = history[after]
        guard b.meters > a.meters else { return b.elapsed }
        return a.elapsed + (target - a.meters) / (b.meters - a.meters) * (b.elapsed - a.elapsed)
    }

    /// How far the runner had gone at `target` seconds of running, between the updates either side of it.
    private func meters(atElapsed target: TimeInterval) -> Double {
        guard let after = history.firstIndex(where: { $0.elapsed >= target }) else { return history.last?.meters ?? 0 }
        guard after > 0 else { return history[after].meters }
        let a = history[after - 1], b = history[after]
        guard b.elapsed > a.elapsed else { return b.meters }
        return a.meters + (target - a.elapsed) / (b.elapsed - a.elapsed) * (b.meters - a.meters)
    }

    private static func pace(from start: Point, to end: Point) -> TimeInterval? {
        let seconds = end.elapsed - start.elapsed
        let meters = end.meters - start.meters
        guard meters > 0, seconds > 0 else { return nil }
        return seconds / (meters / 1_000)
    }
}

private extension String {
    var capitalizingFirstLetter: String {
        prefix(1).uppercased() + dropFirst()
    }
}
