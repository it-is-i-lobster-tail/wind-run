//
//  RunCalories.swift
//  Wind Run
//

import Foundation

extension Run {
    /// Calories worked out when the run finished, or nil when no weight was given then.
    var activeCalories: Double? { activeCaloriesValue }

    /// The run's calories for each kilogram of the runner, from its climb and pace. Nil without a route.
    var calorieEstimate: CalorieEstimate? {
        CalorieEstimator.estimate(energyLegs)
    }

    /// Works out the finished run's calories at the runner's weight and keeps them, so a later change of
    /// weight leaves this run as it was. Does nothing without a weight, as on the watch.
    func settleCalories(bodyMass: Double?) {
        guard status == .complete, let bodyMass, let estimate = calorieEstimate else { return }
        activeCaloriesValue = estimate.kilocalories(bodyMass: bodyMass)
    }

    /// The stretches between fixes taken while running, each with its smoothed climb. Ground covered while
    /// paused is left out. Without a usable height, every stretch counts as flat.
    var energyLegs: [EnergyLeg] {
        let fixes = activeRoute
        guard fixes.count > 1 else { return [] }
        let heights = Self.smoothedHeights(altitudeTrack, fixes: fixes)
        var legs: [EnergyLeg] = []
        for index in fixes.indices.dropFirst() where fixes[index].stretch == fixes[index - 1].stretch {
            let climb: Double
            if let to = heights[index], let from = heights[index - 1] {
                climb = to - from
            } else {
                climb = 0
            }
            legs.append(EnergyLeg(
                meters: fixes[index].meters - fixes[index - 1].meters,
                seconds: fixes[index].time - fixes[index - 1].time,
                climb: climb
            ))
        }
        return legs
    }

    /// Meters either side of a fix whose heights are averaged into its height. GPS height jumps by meters
    /// from fix to fix; the barometer's barely moves.
    static func smoothingReach(for source: AltitudeSource) -> Double {
        switch source {
        case .barometer: 10
        case .gps: 50
        }
    }

    /// Each fix's height, averaged with the heights around it on the same stretch between pauses. A fix
    /// with no height near it takes one from the heights either side. Nil on a stretch with no heights.
    static func smoothedHeights(_ track: AltitudeTrack?, fixes: [ActiveFix]) -> [Double?] {
        guard let track else { return Array(repeating: nil, count: fixes.count) }
        let reach = smoothingReach(for: track.source)
        let byStretch = Dictionary(grouping: track.points, by: \.stretch)
        // Running totals of height, so each window's average is one subtraction.
        let totals = byStretch.mapValues { points in
            points.reduce(into: [0.0]) { $0.append($0.last! + $1.altitude) }
        }

        /// The first point at or past `meters`.
        func firstIndex(in points: [AltitudeTrack.Point], atOrPast meters: Double) -> Int {
            var low = 0
            var high = points.count
            while low < high {
                let middle = (low + high) / 2
                if points[middle].meters < meters { low = middle + 1 } else { high = middle }
            }
            return low
        }

        return fixes.map { fix in
            guard let points = byStretch[fix.stretch], let total = totals[fix.stretch], !points.isEmpty else { return nil }
            let low = firstIndex(in: points, atOrPast: fix.meters - reach)
            let high = firstIndex(in: points, atOrPast: (fix.meters + reach).nextUp)
            if high > low {
                return (total[high] - total[low]) / Double(high - low)
            }
            // Nothing within reach: the heights either side, in proportion, or the nearest at an end.
            let after = firstIndex(in: points, atOrPast: fix.meters)
            if after == 0 { return points[0].altitude }
            if after == points.count { return points[points.count - 1].altitude }
            let a = points[after - 1], b = points[after]
            let fraction = b.meters > a.meters ? (fix.meters - a.meters) / (b.meters - a.meters) : 0
            return a.altitude + (b.altitude - a.altitude) * fraction
        }
    }
}
