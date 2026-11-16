//
//  DisplayReadings.swift
//  Wind Run
//

import Foundation

/// A run's numbers at one moment, everything a display screen can show. The recorder makes these, so
/// every screen reads the run the same way.
struct RunSnapshot {
    var isPaused = false
    /// Running time, leaving out pauses.
    var elapsed: TimeInterval
    var meters: Double
    var unit: DistanceUnit
    /// Seconds per kilometer over the last 30 seconds, or nil with nothing to show.
    var currentPace: TimeInterval?
    /// Seconds per kilometer over the whole run, or nil until there's enough to say.
    var averagePace: TimeInterval?
    /// The newest reading, or nil when there is none.
    var beatsPerMinute: Double?
    /// Meters above the start, negative below, or nil with no height yet.
    var heightFromStart: Double?
    /// Steps a minute, or nil when step counting is off or the sensor hasn't said.
    var cadence: Double?
    /// A coach session's distance or time to run, which the distance or time caption names.
    var goalMeters: Double?
    var goalSeconds: TimeInterval?
    /// A coach session's pace range, seconds per kilometer, fastest first, which the current pace's caption names.
    var paceTarget: ClosedRange<TimeInterval>?
}

extension DisplayScreen {
    /// The screen's six spots as they read in `snapshot`. With `clockRunsAt`, elapsed time carries the date
    /// its clock started, so a screen that isn't redrawn every second can count on its own.
    func readings(_ snapshot: RunSnapshot, clockRunsAt date: Date? = nil) -> DisplayScreenReadings {
        func reading(_ metric: DisplayMetric) -> DisplayReading {
            var reading = metric.reading(snapshot)
            if metric == .elapsed, !snapshot.isPaused, let date {
                reading.clockStart = date.addingTimeInterval(-snapshot.elapsed)
            }
            return reading
        }
        return DisplayScreenReadings(
            primary: reading(primary),
            secondary: reading(secondary),
            tiles: tiles.map(reading)
        )
    }
}

extension DisplayMetric {
    /// How this reads in `snapshot`.
    func reading(_ snapshot: RunSnapshot) -> DisplayReading {
        let unit = snapshot.unit
        switch self {
        case .elapsed:
            let value = RunFormat.duration(snapshot.elapsed)
            let label = snapshot.goalSeconds.map { "OF \(RunFormat.duration($0))" } ?? "ELAPSED"
            return DisplayReading(metric: self, value: value, label: label, isDimmed: snapshot.isPaused, spoken: "Elapsed time, \(value)")
        case .distance:
            let value = RunFormat.distance(snapshot.meters, unit: unit, withUnit: false)
            let label = snapshot.goalMeters.map { "OF \(RunFormat.distance($0, unit: unit).uppercased())" } ?? "DISTANCE"
            return DisplayReading(metric: self, value: value, unit: unit.symbol, label: label, spoken: "Distance, \(value) \(unit.symbol)")
        case .currentPace, .averagePace:
            let pace = self == .currentPace ? (snapshot.isPaused ? nil : snapshot.currentPace) : snapshot.averagePace
            let value = RunFormat.pace(pace, unit: unit, withUnit: false)
            var label = self == .currentPace ? "CURRENT PACE" : "AVG PACE"
            var spoken = "\(name), \(pace == nil ? "none yet" : "\(value) per \(unit.symbol)")"
            if self == .currentPace, let target = snapshot.paceTarget {
                let fast = RunFormat.pace(target.lowerBound, unit: unit, withUnit: false)
                let slow = RunFormat.pace(target.upperBound, unit: unit, withUnit: false)
                let range = fast == slow ? fast : "\(fast)–\(slow)"
                label = "TARGET \(range)"
                spoken += ", target \(range)"
            }
            return DisplayReading(metric: self, value: value, unit: "/\(unit.symbol)", label: label, spoken: spoken)
        case .heartRate:
            let value = RunFormat.heartRate(snapshot.beatsPerMinute, withUnit: false)
            return DisplayReading(
                metric: self,
                value: value,
                unit: "bpm",
                label: "HEART RATE",
                symbol: "heart.fill",
                tint: .heartRate,
                spoken: snapshot.beatsPerMinute == nil ? "Heart rate, no reading" : "Heart rate, \(value) beats per minute"
            )
        case .heightFromStart:
            guard let height = snapshot.heightFromStart else {
                return DisplayReading(metric: self, value: "––", label: "ELEVATION", spoken: "Elevation from start, none yet")
            }
            let amount = RunFormat.elevation(abs(height), unit: unit)
            let parts = amount.split(separator: " ", maxSplits: 1).map(String.init)
            let number = parts.first ?? amount
            let symbolUnit = parts.count > 1 ? parts[1] : nil
            if number == "0" {
                return DisplayReading(metric: self, value: number, unit: symbolUnit, label: "AT START", symbol: "arrow.left.and.right", tint: .accent, spoken: "Level with the start")
            }
            let above = height > 0
            return DisplayReading(
                metric: self,
                value: number,
                unit: symbolUnit,
                label: above ? "ABOVE START" : "BELOW START",
                symbol: above ? "arrow.up" : "arrow.down",
                tint: .accent,
                spoken: "\(amount) \(above ? "above" : "below") the start"
            )
        case .cadence:
            let value = RunFormat.cadence(snapshot.cadence, withUnit: false)
            return DisplayReading(
                metric: self,
                value: value,
                unit: "spm",
                label: "CADENCE",
                spoken: snapshot.cadence == nil ? "Cadence, none yet" : "Cadence, \(value) steps a minute"
            )
        }
    }
}
