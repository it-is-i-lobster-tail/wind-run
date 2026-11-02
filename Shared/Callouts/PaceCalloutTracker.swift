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

    /// A call-out that says only this split's pace.
    init(mark: Mark, secondsPerKilometer: TimeInterval?, unit: DistanceUnit) {
        self.init(mark: mark, readings: [PaceReading(kind: .split, secondsPerKilometer: secondsPerKilometer)], unit: unit)
    }

    /// The pace of this split alone, not the whole run, when the runner hears it.
    var secondsPerKilometer: TimeInterval? {
        pace(.split)
    }

    func pace(_ kind: PaceKind) -> TimeInterval? {
        readings.first { $0.kind == kind }?.secondsPerKilometer
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

    init(trigger: PaceCalloutTrigger, unit: DistanceUnit, paces: [PaceKind] = [.split]) {
        self.trigger = trigger
        self.unit = unit
        self.paces = paces
    }

    init?(settings: PaceCalloutSettings) {
        guard let trigger = settings.trigger else { return nil }
        self.init(trigger: trigger, unit: settings.unit, paces: settings.paces)
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

        var callout: PaceCallout?
        while meters >= Double(splitsDone + 1) * interval {
            let mark = Double(splitsDone + 1) * interval
            let fraction = (mark - from.meters) / (meters - from.meters)
            let reachedAt = from.elapsed + fraction * (elapsed - from.elapsed)
            let end = Point(elapsed: reachedAt, meters: mark)
            callout = PaceCallout(mark: .distance(meters: mark), readings: readings(at: end), unit: unit)
            splitStart = end
            splitsDone += 1
        }
        forgetOld()
        return callout
    }

    private mutating func updateTime(elapsed: TimeInterval, meters: Double, interval: TimeInterval) -> PaceCallout? {
        // A GPS fix can be stamped a moment before the last clock tick. The next tick picks up its distance.
        guard elapsed >= latest.elapsed else { return nil }
        let from = latest
        latest = Point(elapsed: elapsed, meters: meters)
        history.append(latest)

        var callout: PaceCallout?
        while elapsed >= Double(splitsDone + 1) * interval {
            let mark = Double(splitsDone + 1) * interval
            let fraction = elapsed > from.elapsed ? (mark - from.elapsed) / (elapsed - from.elapsed) : 1
            let end = Point(elapsed: mark, meters: from.meters + fraction * (meters - from.meters))
            callout = PaceCallout(mark: .time(seconds: mark), readings: readings(at: end), unit: unit)
            splitStart = end
            splitsDone += 1
        }
        forgetOld()
        return callout
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
                    : Point(elapsed: 0, meters: 0)
                return PaceReading(kind: kind, secondsPerKilometer: Self.pace(from: start, to: end))
            case .average:
                return PaceReading(kind: kind, secondsPerKilometer: Self.pace(from: Point(elapsed: 0, meters: 0), to: end))
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
