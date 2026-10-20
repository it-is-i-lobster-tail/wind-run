//
//  RunTrack.swift
//  Wind Run
//

import CoreLocation
import Foundation

/// What the coach reads from a run's GPS track: kilometer splits with their climb, how much of
/// the run had poor GPS, how much it climbed in each half, and the longest stretch run without
/// stopping.
struct RunTrack: Equatable {
    struct Split: Equatable {
        var meters: Double
        var seconds: TimeInterval
        var climb: Double
    }

    /// Each whole kilometer in order, then the part after the last one.
    var splits: [Split]
    /// Share of active time with poor GPS: long gaps between fixes or inaccurate fixes, 0...1.
    var poorGPSShare: Double
    /// Meters climbed in the first and second half of the distance.
    var climbFirstHalf: Double
    var climbSecondHalf: Double
    /// The longest stretch without a pause or a standstill.
    var longestNonStop: TimeInterval
    var longestNonStopMeters: Double
    /// Altitude at the start, when the fixes had a usable altitude.
    var startAltitude: Double?
    /// Running time, distance and climb so far at each fix, for reading any stretch of the run.
    var points: [Point]

    struct Point: Equatable {
        var elapsed: TimeInterval
        var meters: Double
        var climb: Double
    }

    /// A gap between fixes longer than this counts as poor GPS.
    static let poorGPSGap: TimeInterval = 15
    /// Fixes less accurate than this count as poor GPS.
    static let poorGPSAccuracy: CLLocationAccuracy = 20
    /// Moving slower than this for `standstillDuration` counts as stopping.
    static let standstillSpeed: Double = 0.5
    static let standstillDuration: TimeInterval = 30
    /// Altitude changes smaller than this are treated as GPS noise.
    static let climbNoise: Double = 2

    /// Seconds for each whole kilometer, for showing splits.
    var kilometerSplits: [TimeInterval] {
        splits.filter { $0.meters >= 999 }.map(\.seconds)
    }

    /// Reads a finished run. Nil when there's no route to read.
    init?(_ run: Run) {
        let route = run.route
        guard route.count > 1 else { return nil }
        let pauses = run.pauses

        func isPaused(_ date: Date) -> Bool {
            pauses.contains { $0.contains(date) }
        }

        // Distance and active time at each fix, counting only segments that end while running,
        // the same way the run adds up its distance while recording.
        var meters: [Double] = [0]
        var active: [TimeInterval] = [run.activeTime(at: route[0].timestamp)]
        for index in 1..<route.count {
            let step = isPaused(route[index].timestamp) ? 0 : route[index].location.distance(from: route[index - 1].location)
            meters.append(meters[index - 1] + step)
            active.append(run.activeTime(at: route[index].timestamp))
        }
        let totalMeters = meters.last ?? 0

        // Climb at each fix, ignoring altitude wobble below the noise level.
        var climbAt: [Double] = Array(repeating: 0, count: route.count)
        var reference = route[0].altitudeValue
        for index in 1..<route.count {
            let change = route[index].altitudeValue - reference
            if abs(change) >= Self.climbNoise {
                if change > 0 { climbAt[index] = change }
                reference = route[index].altitudeValue
            }
        }

        // Splits: each whole kilometer, then the rest, with the climb inside each.
        var splits: [Split] = []
        var splitStartTime = active[0]
        var splitStartMeters = 0.0
        var splitClimb = 0.0
        var nextKilometer = 1_000.0
        for index in 1..<route.count {
            splitClimb += climbAt[index]
            while meters[index] >= nextKilometer {
                let segment = meters[index] - meters[index - 1]
                let fraction = segment > 0 ? (nextKilometer - meters[index - 1]) / segment : 1
                let passed = active[index - 1] + (active[index] - active[index - 1]) * fraction
                splits.append(Split(meters: nextKilometer - splitStartMeters, seconds: passed - splitStartTime, climb: splitClimb))
                splitStartTime = passed
                splitStartMeters = nextKilometer
                splitClimb = 0
                nextKilometer += 1_000
            }
        }
        let rest = totalMeters - splitStartMeters
        if rest >= 1 {
            splits.append(Split(meters: rest, seconds: (active.last ?? 0) - splitStartTime, climb: splitClimb))
        }

        // Poor GPS: active time in long gaps or between inaccurate fixes.
        var poorTime: TimeInterval = 0
        for index in 1..<route.count {
            let gap = active[index] - active[index - 1]
            guard gap > 0 else { continue }
            let inaccurate = route[index].horizontalAccuracyValue > Self.poorGPSAccuracy
                || route[index - 1].horizontalAccuracyValue > Self.poorGPSAccuracy
            if gap > Self.poorGPSGap || inaccurate {
                poorTime += gap
            }
        }
        let totalActive = (active.last ?? 0) - (active.first ?? 0)
        let poorShare = totalActive > 0 ? min(1, poorTime / totalActive) : 0

        // Climb in each half of the distance.
        let halfway = totalMeters / 2
        var climbFirst = 0.0
        var climbSecond = 0.0
        for index in 1..<route.count where climbAt[index] > 0 {
            if meters[index] <= halfway { climbFirst += climbAt[index] } else { climbSecond += climbAt[index] }
        }

        // Longest stretch without a pause or a standstill of 30 s or more.
        var longest: TimeInterval = 0
        var longestMeters = 0.0
        var stretchStart = 0
        var slowSince: Int?
        func close(at end: Int) {
            let seconds = active[end] - active[stretchStart]
            if seconds > longest {
                longest = seconds
                longestMeters = meters[end] - meters[stretchStart]
            }
        }
        for index in 1..<route.count {
            let previous = route[index - 1]
            let sample = route[index]
            let pausedBetween = pauses.contains { $0.startDate >= previous.timestamp && $0.startDate < sample.timestamp }
            if pausedBetween {
                close(at: index - 1)
                stretchStart = index
                slowSince = nil
                continue
            }
            let dt = active[index] - active[index - 1]
            let speed = dt > 0 ? (meters[index] - meters[index - 1]) / dt : 0
            if speed < Self.standstillSpeed {
                let since = slowSince ?? (index - 1)
                slowSince = since
                if active[index] - active[since] >= Self.standstillDuration {
                    close(at: since)
                    stretchStart = index
                    slowSince = nil
                }
            } else {
                slowSince = nil
            }
        }
        close(at: route.count - 1)

        // The start altitude from the first fixes with a usable vertical accuracy.
        let altitudes = route.prefix(10).filter { $0.verticalAccuracyValue > 0 }.map(\.altitudeValue).sorted()
        self.splits = splits
        self.poorGPSShare = poorShare
        self.climbFirstHalf = climbFirst
        self.climbSecondHalf = climbSecond
        self.longestNonStop = max(0, longest)
        self.longestNonStopMeters = max(0, longestMeters)
        self.startAltitude = altitudes.isEmpty ? nil : altitudes[altitudes.count / 2]
        var climbSoFar = 0.0
        self.points = route.indices.map { index in
            climbSoFar += climbAt[index]
            return Point(elapsed: active[index], meters: meters[index], climb: climbSoFar)
        }
    }

    /// Distance and climb at a moment of running time, between the fixes either side.
    func position(at elapsed: TimeInterval) -> (meters: Double, climb: Double) {
        guard let first = points.first else { return (0, 0) }
        guard elapsed > first.elapsed else { return (first.meters, first.climb) }
        guard let after = points.firstIndex(where: { $0.elapsed >= elapsed }) else {
            return (points.last?.meters ?? 0, points.last?.climb ?? 0)
        }
        let a = points[after - 1], b = points[after]
        let fraction = b.elapsed > a.elapsed ? (elapsed - a.elapsed) / (b.elapsed - a.elapsed) : 1
        return (a.meters + (b.meters - a.meters) * fraction, a.climb + (b.climb - a.climb) * fraction)
    }

    /// Each whole kilometer between two moments of running time, then the part after the last one.
    func splits(from start: TimeInterval, to end: TimeInterval) -> [Split] {
        guard end > start else { return [] }
        let from = position(at: start), to = position(at: end)
        var splits: [Split] = []
        var mark = (elapsed: start, meters: from.meters, climb: from.climb)
        var next = from.meters + 1_000
        while next <= to.meters {
            let elapsed = time(atMeters: next, after: mark.elapsed)
            let climb = position(at: elapsed).climb
            splits.append(Split(meters: next - mark.meters, seconds: elapsed - mark.elapsed, climb: climb - mark.climb))
            mark = (elapsed, next, climb)
            next += 1_000
        }
        if to.meters - mark.meters >= 1 {
            splits.append(Split(meters: to.meters - mark.meters, seconds: end - mark.elapsed, climb: to.climb - mark.climb))
        }
        return splits
    }

    /// The running time at which the run reached a distance, at or after a moment.
    private func time(atMeters target: Double, after start: TimeInterval) -> TimeInterval {
        guard let after = points.firstIndex(where: { $0.meters >= target && $0.elapsed >= start }), after > 0 else {
            return points.last?.elapsed ?? start
        }
        let a = points[after - 1], b = points[after]
        let fraction = b.meters > a.meters ? (target - a.meters) / (b.meters - a.meters) : 1
        return max(start, a.elapsed + (b.elapsed - a.elapsed) * fraction)
    }
}

extension TrackSummary {
    /// The coach's reading of a recorded track.
    init(_ track: RunTrack) {
        self.init(
            splits: track.splits.map { Split(meters: $0.meters, seconds: $0.seconds, climbMeters: $0.climb) },
            poorGPSShare: track.poorGPSShare,
            climbFirstHalf: track.climbFirstHalf,
            climbSecondHalf: track.climbSecondHalf,
            longestNonStopSeconds: track.longestNonStop,
            longestNonStopMeters: track.longestNonStopMeters,
            startAltitude: track.startAltitude
        )
    }
}
