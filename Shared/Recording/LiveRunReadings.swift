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

/// The last 15 minutes of heart rate, for the line on the run screen.
struct HeartRateHistory {
    static let window: TimeInterval = 15 * 60

    struct Point: Equatable {
        var date: Date
        var beatsPerMinute: Double
    }

    /// The readings in the window, oldest first.
    private(set) var points: [Point] = []

    mutating func record(_ beatsPerMinute: Double, at date: Date) {
        guard beatsPerMinute.isFinite, beatsPerMinute > 0 else { return }
        if let last = points.last, date < last.date { return }
        points.append(Point(date: date, beatsPerMinute: beatsPerMinute))
        let start = date.addingTimeInterval(-Self.window)
        if let keep = points.firstIndex(where: { $0.date >= start }), keep > 0 {
            points.removeFirst(keep)
        }
    }

    /// The readings from the 15 minutes up to `date`. A run shorter than that has all of its readings.
    func recent(at date: Date) -> [Point] {
        let start = date.addingTimeInterval(-Self.window)
        return points.filter { $0.date >= start && $0.date <= date }
    }
}

/// How far above or below the start the runner is, from GPS heights, for when there's no barometer.
/// GPS height wanders, so only fixes with a usable height count.
struct GPSHeightFromStart {
    /// Fixes with a vertical accuracy worse than this have a height too rough to use.
    static let accuracy: Double = AltitudeTrack.gpsAccuracy

    private var start: Double?
    private var latest: Double?

    mutating func record(altitude: Double, verticalAccuracy: Double) {
        guard verticalAccuracy > 0, verticalAccuracy <= Self.accuracy else { return }
        if start == nil { start = altitude }
        latest = altitude
    }

    /// Meters above the first usable height, negative below, or nil before there is one.
    var change: Double? {
        guard let start, let latest else { return nil }
        return latest - start
    }
}
