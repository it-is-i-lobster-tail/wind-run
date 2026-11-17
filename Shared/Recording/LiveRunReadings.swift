//
//  LiveRunReadings.swift
//  Wind Run
//

import Foundation

/// The pace right now, for the run screen: the last 30 seconds of running, so one slow stride or a
/// GPS wobble doesn't swing it, but a surge or an easing off shows within a few seconds.
struct RecentPace {
    /// The same stretch as the "current pace" call-out.
    static let window: TimeInterval = PaceKind.currentWindow
    /// With no fix for this long, the newest one says nothing about now.
    static let staleAfter: TimeInterval = 10
    /// Less than this much running or ground in the window is too little to say a pace.
    static let minimumSeconds: TimeInterval = 5
    static let minimumMeters: Double = 5

    private struct Point {
        var time: TimeInterval
        var meters: Double
    }

    /// Running time and distance at each fix, the newest last, going back just past the window.
    private var points: [Point] = []

    /// A fix taken while running, at `time` into the run with `meters` covered.
    mutating func record(time: TimeInterval, meters: Double) {
        if let last = points.last, time <= last.time {
            points[points.count - 1].meters = max(last.meters, meters)
            return
        }
        points.append(Point(time: time, meters: meters))
        // Keep one point at or before the window's start, so the window is always full once it can be.
        while points.count > 2, points[1].time <= time - Self.window {
            points.removeFirst()
        }
    }

    /// Seconds per kilometer over the last 30 seconds of running up to `time`, or nil until there's enough
    /// to say, or when the newest fix is too old.
    func pace(at time: TimeInterval) -> TimeInterval? {
        guard let newest = points.last, time - newest.time <= Self.staleAfter else { return nil }
        let start = newest.time - Self.window
        let base = points.first { $0.time >= start } ?? newest
        let seconds = newest.time - base.time
        let meters = newest.meters - base.meters
        guard seconds >= Self.minimumSeconds, meters >= Self.minimumMeters else { return nil }
        return seconds / meters * 1_000
    }
}

/// How far above or below the start the runner is, from GPS heights, for when there's no barometer.
/// GPS height wanders, so only fixes with a usable height count.
struct GPSHeightFromStart {
    /// Fixes with a vertical accuracy worse than this have a height too rough to use.
    static let accuracy: Double = AltitudeTrack.gpsAccuracy

    private var startValue: Double?
    private var latestValue: Double?

    mutating func record(altitude: Double, verticalAccuracy: Double) {
        guard verticalAccuracy > 0, verticalAccuracy <= Self.accuracy else { return }
        if startValue == nil { startValue = altitude }
        latestValue = altitude
    }

    /// Meters above the first usable height, negative below, or nil before there is one.
    var change: Double? {
        guard let startValue, let latestValue else { return nil }
        return latestValue - startValue
    }
}

extension GPSHeightFromStart {
    /// The first usable GPS height, meters above sea level.
    var startAltitude: Double? { startValue }
    /// The newest usable GPS height, meters above sea level.
    var latestAltitude: Double? { latestValue }
}

/// The kilometer or mile under way and the last whole one, for one unit's length. Fed the running time and
/// distance at each fix while running.
struct SplitClock {
    /// One kilometer or one mile, in meters.
    let length: Double
    /// Where the split under way started: running time and distance.
    private(set) var splitStart: (time: TimeInterval, meters: Double) = (0, 0)
    /// How long the last whole split took, or nil before the first one ends.
    private(set) var lastSplit: TimeInterval?
    private var previous: (time: TimeInterval, meters: Double)?

    init(length: Double) {
        self.length = length
    }

    mutating func record(time: TimeInterval, meters: Double) {
        if let previous, meters > previous.meters, time >= previous.time {
            var boundary = (floor(previous.meters / length) + 1) * length
            while meters >= boundary {
                // When the boundary was crossed, between the two fixes.
                let fraction = (boundary - previous.meters) / (meters - previous.meters)
                let at = previous.time + fraction * (time - previous.time)
                lastSplit = at - splitStart.time
                splitStart = (at, boundary)
                boundary += length
            }
        }
        previous = (time, meters)
    }

    /// Seconds per kilometer for the split under way, or nil until it has 10 m and 5 s in it.
    func pace(time: TimeInterval, meters: Double) -> TimeInterval? {
        let seconds = time - splitStart.time
        let distance = meters - splitStart.meters
        guard seconds >= 5, distance >= 10 else { return nil }
        return seconds / distance * 1_000
    }
}

/// The pace over the last stretch of ground, half a kilometer or half a mile.
struct RollingPace {
    /// The longest stretch asked for, so older points can go.
    static let longest: Double = 1_000

    private struct Point {
        var time: TimeInterval
        var meters: Double
    }

    private var points: [Point] = []

    mutating func record(time: TimeInterval, meters: Double) {
        if let last = points.last, meters <= last.meters { return }
        points.append(Point(time: time, meters: meters))
        while points.count > 2, points[1].meters <= meters - Self.longest {
            points.removeFirst()
        }
    }

    /// Seconds per kilometer over the last `window` meters, or nil until the run has covered that much.
    func pace(over window: Double) -> TimeInterval? {
        guard let newest = points.last, let base = points.last(where: { $0.meters <= newest.meters - window }) else { return nil }
        let seconds = newest.time - base.time
        let meters = newest.meters - base.meters
        guard seconds > 0, meters > 0 else { return nil }
        return seconds / meters * 1_000
    }
}

/// How steep the ground is and how fast the runner is climbing, from heights over the last stretch of the run.
struct SlopeTracker {
    /// Grade is read over about this much ground: shorter is mostly altitude noise.
    static let gradeMeters: Double = 50
    /// Vertical speed is read over about this long.
    static let verticalSeconds: TimeInterval = 60

    private struct Point {
        var time: TimeInterval
        var meters: Double
        var height: Double
    }

    private var points: [Point] = []

    mutating func record(time: TimeInterval, meters: Double, height: Double) {
        if let last = points.last, time <= last.time { return }
        points.append(Point(time: time, meters: meters, height: height))
        while points.count > 2,
              points[1].time <= time - Self.verticalSeconds * 2,
              points[1].meters <= meters - Self.gradeMeters * 2 {
            points.removeFirst()
        }
    }

    /// Rise over run, 0.08 for 8% uphill, or nil until there's 30 m of ground to read it over.
    var grade: Double? {
        guard let newest = points.last else { return nil }
        let base = points.last { $0.meters <= newest.meters - Self.gradeMeters } ?? points.first
        guard let base, newest.meters - base.meters >= 30 else { return nil }
        return (newest.height - base.height) / (newest.meters - base.meters)
    }

    /// Meters climbed an hour, negative dropping, or nil until there's 30 seconds to read it over.
    var metersPerHour: Double? {
        guard let newest = points.last else { return nil }
        let base = points.last { $0.time <= newest.time - Self.verticalSeconds } ?? points.first
        guard let base, newest.time - base.time >= 30 else { return nil }
        return (newest.height - base.height) / (newest.time - base.time) * 3_600
    }
}

/// Total climb and drop. A change counts once it passes `threshold`, so altitude noise on flat ground
/// doesn't add up to a hill.
struct ClimbCounter {
    let threshold: Double
    private var anchor: Double?
    private(set) var ascent: Double = 0
    private(set) var descent: Double = 0

    init(threshold: Double) {
        self.threshold = threshold
    }

    mutating func record(_ height: Double) {
        guard let anchor else {
            self.anchor = height
            return
        }
        let change = height - anchor
        if change >= threshold {
            ascent += change
            self.anchor = height
        } else if change <= -threshold {
            descent -= change
            self.anchor = height
        }
    }
}

/// Calories as the run goes, from Minetti's slope costs, per kilogram of the runner. The finished run's
/// figure is worked out again from the whole route, so the two can differ a little.
struct LiveCalories {
    private(set) var perKilogram: Double = 0

    mutating func add(meters: Double, seconds: TimeInterval, grade: Double?) {
        guard meters > 0 else { return }
        let slope = min(CalorieEstimator.maximumGrade, max(-CalorieEstimator.maximumGrade, grade ?? 0))
        let along = meters * (1 + slope * slope).squareRoot()
        let isWalking = seconds > 0 && along / seconds < CalorieEstimator.walkingSpeed
        let cost = isWalking ? EnergyCost.walking(grade: slope) : EnergyCost.running(grade: slope)
        perKilogram += cost * along / CalorieEstimator.joulesPerKilocalorie
    }
}
