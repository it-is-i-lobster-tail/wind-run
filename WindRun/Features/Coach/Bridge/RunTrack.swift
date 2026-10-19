//
//  RunTrack.swift
//  Wind Run
//

import CoreLocation
import Foundation

/// What the coach reads from a run's GPS track: kilometer splits, how much of it had poor GPS,
/// how much it climbed in each half, and the longest stretch run without stopping.
struct RunTrack: Equatable {
    /// Active seconds for each whole kilometer, in order.
    var kilometerSplits: [TimeInterval]
    /// Share of active time with poor GPS: long gaps between fixes or inaccurate fixes, 0...1.
    var poorGPSShare: Double
    /// Meters climbed in the first and second half of the distance.
    var climbFirstHalf: Double
    var climbSecondHalf: Double
    /// The longest stretch without a pause or a standstill, in seconds.
    var longestNonStop: TimeInterval

    /// A gap between fixes longer than this counts as poor GPS.
    static let poorGPSGap: TimeInterval = 15
    /// Fixes less accurate than this count as poor GPS.
    static let poorGPSAccuracy: CLLocationAccuracy = 20
    /// Moving slower than this for `standstillDuration` counts as stopping.
    static let standstillSpeed: Double = 0.5
    static let standstillDuration: TimeInterval = 30
    /// Altitude changes smaller than this are treated as GPS noise.
    static let climbNoise: Double = 2

    init(
        kilometerSplits: [TimeInterval],
        poorGPSShare: Double,
        climbFirstHalf: Double,
        climbSecondHalf: Double,
        longestNonStop: TimeInterval
    ) {
        self.kilometerSplits = kilometerSplits
        self.poorGPSShare = poorGPSShare
        self.climbFirstHalf = climbFirstHalf
        self.climbSecondHalf = climbSecondHalf
        self.longestNonStop = longestNonStop
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
            let previous = route[index - 1]
            let sample = route[index]
            let step = isPaused(sample.timestamp) ? 0 : sample.location.distance(from: previous.location)
            meters.append(meters[index - 1] + step)
            active.append(run.activeTime(at: sample.timestamp))
        }

        // Kilometer splits: the active time at which each whole kilometer was passed.
        var splits: [TimeInterval] = []
        var lastMark: TimeInterval = active[0]
        var nextKilometer = 1_000.0
        for index in 1..<route.count where meters[index] >= nextKilometer {
            // Interpolate inside the segment for the moment the kilometer was passed.
            let segment = meters[index] - meters[index - 1]
            let fraction = segment > 0 ? (nextKilometer - meters[index - 1]) / segment : 1
            let passed = active[index - 1] + (active[index] - active[index - 1]) * fraction
            splits.append(passed - lastMark)
            lastMark = passed
            nextKilometer += 1_000
            // A long segment can pass more than one kilometer; the rest are caught next time round.
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
        let totalActive = max(active.last ?? 0, 0) - max(active.first ?? 0, 0)
        let poorShare = totalActive > 0 ? min(1, poorTime / totalActive) : 0

        // Climb in each half of the distance, ignoring altitude wobble below the noise level.
        let halfway = (meters.last ?? 0) / 2
        var climbFirst = 0.0
        var climbSecond = 0.0
        var reference = route[0].altitudeValue
        for index in 1..<route.count {
            let altitude = route[index].altitudeValue
            let change = altitude - reference
            if abs(change) >= Self.climbNoise {
                if change > 0 {
                    if meters[index] <= halfway { climbFirst += change } else { climbSecond += change }
                }
                reference = altitude
            }
        }

        // Longest stretch without a pause or a standstill of 30 s or more.
        var longest: TimeInterval = 0
        var stretchStart = active[0]
        var slowSince: TimeInterval?
        for index in 1..<route.count {
            let previous = route[index - 1]
            let sample = route[index]
            let dt = active[index] - active[index - 1]
            let pausedBetween = pauses.contains { $0.startDate >= previous.timestamp && $0.startDate < sample.timestamp }
            if pausedBetween {
                longest = max(longest, active[index - 1] - stretchStart)
                stretchStart = active[index]
                slowSince = nil
                continue
            }
            let speed = dt > 0 ? (meters[index] - meters[index - 1]) / dt : 0
            if speed < Self.standstillSpeed {
                let since = slowSince ?? active[index - 1]
                slowSince = since
                if active[index] - since >= Self.standstillDuration {
                    longest = max(longest, since - stretchStart)
                    stretchStart = active[index]
                    slowSince = nil
                }
            } else {
                slowSince = nil
            }
        }
        longest = max(longest, (active.last ?? 0) - stretchStart)

        self.init(
            kilometerSplits: splits,
            poorGPSShare: poorShare,
            climbFirstHalf: climbFirst,
            climbSecondHalf: climbSecond,
            longestNonStop: max(0, longest)
        )
    }
}
