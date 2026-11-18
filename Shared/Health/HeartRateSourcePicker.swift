//
//  HeartRateSourcePicker.swift
//  Wind Run
//

import Foundation

/// Works out what's measuring heart rate during one run, for `HeartRateMonitor`, from the live readings and
/// Health's records of them. Kept apart from the workout session so it can be tested.
///
/// The source whose records match the live readings wins, so a watch's readings synced to the iPhone don't
/// take over from the earbuds actually measuring. Until records match, it's the best source among those with
/// a reading within `HeartRateMonitor.sourceWindow` of the newest one, so a strap that drops out hands over
/// to the watch or earbuds.
struct HeartRateSourcePicker {
    /// What's measuring now, or nil until one is found.
    private(set) var source: HeartRateSource?

    /// The newest reading seen from each source.
    private var lastSeen: [HeartRateSource: Date] = [:]
    /// Health's records of the last couple of minutes of readings, to match each live reading to what
    /// measured it.
    private var recentSamples: [HeartRateSourceSample] = []
    /// The last couple of minutes of live readings, to match Health's records to as they come in.
    private var recentReadings: [(date: Date, beatsPerMinute: Double)] = []
    /// The source whose records last matched a live reading, and when.
    private var matched: (source: HeartRateSource, date: Date)?
    /// The devices already handed back by `saw`.
    private var devicesSeen: Set<DeviceInfo> = []
    /// How far back readings and records are kept for matching.
    private static let matchHistory: TimeInterval = 120

    /// Starts with `initial` as the source, such as the watch on the watch, until records say otherwise.
    init(initial: HeartRateSource? = nil) {
        source = initial
    }

    /// How many sources have had a reading, for trace lines.
    var sourcesSeen: Int { lastSeen.count }

    /// Takes a live reading and says what measured it: what Health says measured this very reading when its
    /// record is in already, otherwise what's measuring now.
    mutating func live(_ beatsPerMinute: Double, at date: Date) -> HeartRateSource? {
        recentReadings.append((date, beatsPerMinute))
        recentReadings.removeAll { date.timeIntervalSince($0.date) > Self.matchHistory }
        return HeartRateMonitor.match(beatsPerMinute, at: date, in: recentSamples) ?? source
    }

    /// Takes Health's records of the run's readings and updates `source`. Returns the devices behind them
    /// that weren't seen before, in the order they came.
    mutating func saw(_ found: [HeartRateSourceSample]) -> [DeviceInfo] {
        var newDevices: [DeviceInfo] = []
        for reading in found {
            lastSeen[reading.source] = max(lastSeen[reading.source] ?? reading.date, reading.date)
            if let device = reading.device, devicesSeen.insert(device).inserted {
                newDevices.append(device)
            }
            let matching = recentReadings.filter {
                HeartRateMonitor.isSameReading($0.beatsPerMinute, at: $0.date, reading.beatsPerMinute, at: reading.date)
            }
            if let date = matching.map(\.date).max(), date >= (matched?.date ?? .distantPast) {
                // Two sources matching the same reading: the better-ranked one.
                if date == matched?.date, let current = matched?.source {
                    matched = (HeartRateSource.best([current, reading.source]) ?? reading.source, date)
                } else {
                    matched = (reading.source, date)
                }
            }
        }
        recentSamples.append(contentsOf: found)
        if let newest = recentSamples.map(\.date).max() {
            recentSamples.removeAll { newest.timeIntervalSince($0.date) > Self.matchHistory }
        }
        guard let newest = lastSeen.values.max() else { return newDevices }
        if let matched, newest.timeIntervalSince(matched.date) <= HeartRateMonitor.sourceWindow {
            source = matched.source
        } else {
            let current = lastSeen.filter { newest.timeIntervalSince($0.value) <= HeartRateMonitor.sourceWindow }.keys
            source = HeartRateSource.best(current) ?? source
        }
        return newDevices
    }
}
