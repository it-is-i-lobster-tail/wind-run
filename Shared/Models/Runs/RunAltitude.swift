//
//  RunAltitude.swift
//  Wind Run
//

import CoreLocation
import Foundation

/// One barometer reading: how far the runner had climbed or dropped since the barometer started.
nonisolated struct AltitudeSample: Codable, Hashable {
    var timestamp: Date
    /// Meters above where the run's readings started, negative below.
    var relativeMeters: Double
}

/// Where a run's heights come from. The barometer feels a meter of climb; GPS height can wander
/// by ten, so it only sets the level when there's a barometer.
nonisolated enum AltitudeSource: Equatable {
    case barometer
    case gps
}

/// One route fix taken while running.
nonisolated struct ActiveFix {
    /// Running time, leaving out pauses.
    let time: TimeInterval
    /// Distance covered so far.
    let meters: Double
    /// Counts up after each pause, so nothing reads across the ground covered while paused.
    let stretch: Int
    /// The fix itself, read out of the store once.
    let sample: RouteReading
}

@MainActor extension ActiveFix {
    init(time: TimeInterval, meters: Double, stretch: Int, sample: RouteSample) {
        self.init(time: time, meters: meters, stretch: stretch, sample: RouteReading(sample))
    }
}

/// The run's height at its fixes while running, from the best source it has.
nonisolated struct AltitudeTrack {
    struct Point {
        /// The fix's place in `Run.activeRoute`.
        let index: Int
        let time: TimeInterval
        let meters: Double
        let stretch: Int
        let altitude: Double
    }

    let source: AltitudeSource
    let points: [Point]
    /// True when no fix had a GPS height good enough to set the level, so the heights are the barometer's
    /// climb from where the run started rather than heights above the sea.
    var isRelative = false

    /// Fixes with a vertical accuracy worse than this have a height too rough to use.
    static let gpsAccuracy: Double = 20
    /// The barometer is used when it has a reading this close to at least `barometerCoverage` of the fixes.
    static let barometerReach: TimeInterval = 30
    static let barometerCoverage = 0.9
}

extension Run {
    /// The barometer's readings through the run, or empty when it had none.
    var barometricAltitude: [AltitudeSample] {
        Self.decodedJSON([AltitudeSample].self, from: altitudeDataValue) ?? []
    }

    func saveBarometricAltitude(_ samples: [AltitudeSample]) {
        altitudeDataValue = Self.encodedJSONUnlessEmpty(samples)
    }

    /// Measures a finished run's distance again with today's `DistanceEstimator`, when it was measured with
    /// the reported-speed method that read short. The new distance is the one the charts and sections add
    /// up to. Returns whether it changed anything.
    @discardableResult
    func remeasureDistance() -> Bool {
        guard status == .complete, distanceMethodValue == DistanceEstimator.speedMethod else { return false }
        let fixes = Self.activeRoute(routeReadings, clock: pauseClock, usesEstimator: true, sport: sport)
        distanceMetersValue = fixes.last?.meters ?? 0
        distanceMethodValue = DistanceEstimator.method
        return true
    }

    /// Route fixes taken while running, each with its running time and the distance covered so far.
    /// Fixes during a pause are left out, and so is the ground between a pause and the next fix.
    var activeRoute: [ActiveFix] {
        // Every fix and pause is read out of the store once: a long run has thousands of fixes, and each
        // stored read costs far more than the sums here.
        Self.activeRoute(routeReadings, clock: pauseClock, usesEstimator: distanceMethod != nil, sport: sport)
    }

    /// The same, from fixes already read in order and the run's pauses.
    nonisolated static func activeRoute(_ readings: [RouteReading], clock: PauseClock, usesEstimator: Bool, sport: WorkoutSport) -> [ActiveFix] {
        var fixes: [ActiveFix] = []
        fixes.reserveCapacity(readings.count)
        var previous: RouteReading?
        var meters = 0.0
        var stretch = 0
        // Measured the way the run's own distance is, so charts and sections add up to it.
        var estimator = DistanceEstimator(sport: sport)
        for sample in readings {
            guard !clock.contains(sample.timestamp) else {
                previous = nil
                continue
            }
            // A pause with no fix inside it still breaks the run.
            if let last = previous, clock.hasPauseStarting(from: last.timestamp, before: sample.timestamp) {
                previous = nil
            }
            if previous == nil {
                estimator = DistanceEstimator(sport: sport)
            }
            let step = estimator.add(DistanceEstimator.Fix(sample))
            if previous != nil {
                meters += usesEstimator ? step.meters : step.gap
            } else if !fixes.isEmpty {
                stretch += 1
            }
            fixes.append(ActiveFix(time: clock.activeTime(at: sample.timestamp), meters: meters, stretch: stretch, sample: sample))
            previous = sample
        }
        return fixes
    }

    /// Height at each fix taken while running. With the barometer, every fix gets the barometer's
    /// climb, lifted to the level GPS puts the run at. Without it, only fixes with a usable GPS height
    /// are kept. Nil when neither gives two heights.
    var altitudeTrack: AltitudeTrack? {
        altitudeTrack(for: activeRoute)
    }

    /// The same, from fixes already worked out with `activeRoute`, so a caller that has them doesn't walk
    /// the route again.
    func altitudeTrack(for fixes: [ActiveFix]) -> AltitudeTrack? {
        Self.altitudeTrack(for: fixes, barometer: barometricAltitude)
    }

    /// The same, from the barometer's readings already read out, so it can be worked out away from the screen.
    nonisolated static func altitudeTrack(for fixes: [ActiveFix], barometer readings: [AltitudeSample]) -> AltitudeTrack? {
        guard fixes.count > 1 else { return nil }
        let goodGPS = fixes.indices.filter {
            let accuracy = fixes[$0].sample.verticalAccuracyValue
            return accuracy > 0 && accuracy <= AltitudeTrack.gpsAccuracy
        }

        if let barometer = barometerHeights(readings, at: fixes.map(\.sample.timestamp)) {
            // The barometer only knows the climb from where it started. GPS says how high that start was.
            let offsets = goodGPS.map { fixes[$0].sample.altitudeValue - barometer[$0] }.sorted()
            let offset = offsets.isEmpty ? 0 : offsets[offsets.count / 2]
            let points = fixes.indices.map { index in
                AltitudeTrack.Point(index: index, time: fixes[index].time, meters: fixes[index].meters, stretch: fixes[index].stretch, altitude: barometer[index] + offset)
            }
            return AltitudeTrack(source: .barometer, points: points, isRelative: offsets.isEmpty)
        }

        guard goodGPS.count > 1 else { return nil }
        let points = goodGPS.map { index in
            AltitudeTrack.Point(index: index, time: fixes[index].time, meters: fixes[index].meters, stretch: fixes[index].stretch, altitude: fixes[index].sample.altitudeValue)
        }
        return AltitudeTrack(source: .gps, points: points)
    }

    /// The barometer's climb at each date, between the readings either side. Nil when the readings
    /// leave too many of the dates uncovered, such as when the barometer started late or stopped early.
    nonisolated static func barometerHeights(_ readings: [AltitudeSample], at dates: [Date]) -> [Double]? {
        guard readings.count > 1, !dates.isEmpty else { return nil }
        var heights: [Double] = []
        var covered = 0
        var after = 0
        for date in dates {
            while after < readings.count, readings[after].timestamp < date {
                after += 1
            }
            let before = after - 1
            let near = [before, after].filter { readings.indices.contains($0) }
                .map { abs(readings[$0].timestamp.timeIntervalSince(date)) }
                .min() ?? .infinity
            if near <= AltitudeTrack.barometerReach { covered += 1 }
            if before < 0 {
                heights.append(readings[0].relativeMeters)
            } else if after >= readings.count {
                heights.append(readings[readings.count - 1].relativeMeters)
            } else {
                let a = readings[before], b = readings[after]
                let span = b.timestamp.timeIntervalSince(a.timestamp)
                let fraction = span > 0 ? date.timeIntervalSince(a.timestamp) / span : 1
                heights.append(a.relativeMeters + (b.relativeMeters - a.relativeMeters) * fraction)
            }
        }
        guard Double(covered) >= AltitudeTrack.barometerCoverage * Double(dates.count) else { return nil }
        return heights
    }
}
