//
//  CalorieEstimator.swift
//  Wind Run
//

import Foundation

/// What it costs to run or walk a meter on a slope, in joules per kilogram of body weight, from Minetti and
/// others, "Energy cost of walking and running at extreme uphill and downhill slopes" (J Appl Physiol 93:1039,
/// 2002). The curves were fitted from −45% to +45%, and give the cost above standing still, which is what
/// Apple Health calls active energy.
enum EnergyCost {
    /// 3.6 J/kg/m on the flat, about 0.86 kcal per kilogram per kilometer. Cheapest at about −20%.
    static func running(grade i: Double) -> Double {
        155.4 * pow(i, 5) - 30.4 * pow(i, 4) - 43.3 * pow(i, 3) + 46.3 * i * i + 19.5 * i + 3.6
    }

    /// 2.5 J/kg/m on the flat, at an easy walking speed. Close to running's cost on steep climbs, where
    /// walking is often the cheaper way up.
    static func walking(grade i: Double) -> Double {
        280.5 * pow(i, 5) - 58.7 * pow(i, 4) - 76.8 * pow(i, 3) + 51.9 * i * i + 19.6 * i + 2.5
    }
}

/// A stretch of a run between two fixes: how far it went over the ground, how long it took, and how
/// much it climbed (negative for a drop).
struct EnergyLeg: Equatable {
    var meters: Double
    var seconds: TimeInterval
    var climb: Double

    static let zero = EnergyLeg(meters: 0, seconds: 0, climb: 0)

    static func + (a: EnergyLeg, b: EnergyLeg) -> EnergyLeg {
        EnergyLeg(meters: a.meters + b.meters, seconds: a.seconds + b.seconds, climb: a.climb + b.climb)
    }

    func scaled(by fraction: Double) -> EnergyLeg {
        EnergyLeg(meters: meters * fraction, seconds: seconds * fraction, climb: climb * fraction)
    }
}

/// A run's calories for each kilogram of the runner, so the same estimate serves any weight.
struct CalorieEstimate: Equatable {
    /// Kilocalories for each kilogram of body weight.
    var perKilogram: Double
    /// The same run on flat ground, for saying what the hills added or saved.
    var flatPerKilogram: Double
    /// Ground covered slower than `CalorieEstimator.walkingSpeed`, counted as walking.
    var walkedMeters: Double

    func kilocalories(bodyMass: Double) -> Double {
        perKilogram * bodyMass
    }

    /// The share of the calories the hills added, negative when the run dropped more than it climbed
    /// and the downhills saved some.
    var hillShare: Double {
        perKilogram > 0 ? 1 - flatPerKilogram / perKilogram : 0
    }
}

/// Works out a run's calories 100 meters at a time: each stretch's slope from its climb, capped at 40%,
/// and its speed, which says whether it was run or walked. Then the slope's cost from Minetti's curves.
enum CalorieEstimator {
    /// The run is read in stretches of this much ground. Shorter ones make the slope mostly altitude noise.
    static let chunkMeters: Double = 100
    /// A last stretch shorter than this joins the one before it.
    static let shortestChunk: Double = 50
    /// Slopes steeper than this, up or down, count as this steep. Past it the curves weren't measured,
    /// and a slope that steep over 100 m is more likely a jump in altitude than a hill.
    static let maximumGrade = 0.40
    /// Slower than this, a stretch counts as walking: 1.8 m/s, about 9:15 a kilometer or 14:54 a mile.
    /// People change from walking to running at about 2 m/s, and this leaves room for a slow jog.
    static let walkingSpeed: Double = 1.8
    static let joulesPerKilocalorie: Double = 4_184

    /// Nil when the run covered no ground.
    static func estimate(_ legs: [EnergyLeg]) -> CalorieEstimate? {
        let chunks = chunks(legs)
        guard !chunks.isEmpty else { return nil }
        var joules = 0.0
        var flatJoules = 0.0
        var walked = 0.0
        for chunk in chunks {
            let grade = min(maximumGrade, max(-maximumGrade, chunk.climb / chunk.meters))
            // The curves count meters along the slope.
            let along = chunk.meters * (1 + grade * grade).squareRoot()
            let isWalking = chunk.seconds > 0 && along / chunk.seconds < walkingSpeed
            if isWalking {
                walked += chunk.meters
                joules += EnergyCost.walking(grade: grade) * along
                flatJoules += EnergyCost.walking(grade: 0) * chunk.meters
            } else {
                joules += EnergyCost.running(grade: grade) * along
                flatJoules += EnergyCost.running(grade: 0) * chunk.meters
            }
        }
        return CalorieEstimate(
            perKilogram: joules / joulesPerKilocalorie,
            flatPerKilogram: flatJoules / joulesPerKilocalorie,
            walkedMeters: walked
        )
    }

    /// The legs gathered into stretches of `chunkMeters`, a leg split where a stretch ends. The last
    /// stretch joins the one before it when it's shorter than `shortestChunk`.
    static func chunks(_ legs: [EnergyLeg]) -> [EnergyLeg] {
        var chunks: [EnergyLeg] = []
        var current = EnergyLeg.zero
        for leg in legs {
            var rest = leg
            while rest.meters > 0, current.meters + rest.meters >= chunkMeters {
                let fraction = (chunkMeters - current.meters) / rest.meters
                chunks.append(current + rest.scaled(by: fraction))
                rest = rest.scaled(by: 1 - fraction)
                current = .zero
            }
            current = current + rest
        }
        if current.meters > 0 {
            if current.meters < shortestChunk, let last = chunks.popLast() {
                chunks.append(last + current)
            } else {
                chunks.append(current)
            }
        }
        return chunks
    }
}
