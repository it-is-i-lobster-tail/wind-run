//
//  PaceCalculator.swift
//  Wind Run
//

import Foundation

/// Training paces and race forecasts from current ability, never from the goal (PZ-2 to PZ-8, PZ-11).
enum PaceCalculator {
    /// Anchors expire after 26 weeks (PZ-2).
    static let anchorWeeks = 26

    /// t2 = t1 × (d2 ÷ d1)^k (PZ-4).
    static func equivalent(seconds: Double, meters: Double, to distance: Double, k: Double = 1.07) -> Double {
        guard meters > 0 else { return 0 }
        return seconds * pow(distance / meters, k)
    }

    /// The anchor in force: the newest valid result up to 26 weeks old on a usable course (PZ-2).
    static func anchor(_ results: [RaceResult], now: Date, calendar: Calendar) -> RaceResult? {
        let oldest = calendar.date(byAdding: .weekOfYear, value: -anchorWeeks, to: now) ?? now
        return results
            .filter { $0.date >= oldest && $0.date <= now && $0.course != .veryHilly && $0.meters > 0 && $0.seconds > 0 }
            .max { $0.date < $1.date }
    }

    /// The first paces from intake (PZ-5): the easy band from the reported pace or the anchor (the band
    /// whose fast edge is slower when both exist), threshold and interval paces from the anchor.
    static func initialPaces(_ intake: CoachIntake, now: Date, calendar: Calendar) -> TrainingPaces {
        var paces = TrainingPaces()
        let anchor = anchor([intake.race].compactMap { $0 }, now: now, calendar: calendar)
        paces.anchor = anchor
        var bands: [(PaceBand, EasyPaceSource)] = []
        if let easy = intake.easyPace, easy > 0 {
            bands.append((PaceBand(fast: easy, slow: easy * 1.10), .reported))
        }
        if let anchor {
            let fiveK = equivalent(seconds: anchor.seconds, meters: anchor.meters, to: 5_000) / 5
            bands.append((PaceBand(fast: fiveK * 1.28, slow: fiveK * 1.40), .anchor))
            paces = withQualityPaces(paces, anchor: anchor)
        }
        if let slowest = bands.max(by: { $0.0.fast < $1.0.fast }) {
            paces.easy = slowest.0
            paces.easySource = slowest.1
        }
        return paces
    }

    /// Threshold (60-min race pace + 3%, never faster than 10K pace) and interval (5K pace, nil over 30:00) paces.
    static func withQualityPaces(_ paces: TrainingPaces, anchor: RaceResult) -> TrainingPaces {
        var paces = paces
        let d60 = anchor.meters * pow(3_600 / anchor.seconds, 1 / 1.07)
        let sixtyMinutePace = 3_600 / d60 * 1_000
        let tenKPace = equivalent(seconds: anchor.seconds, meters: anchor.meters, to: 10_000) / 10
        paces.threshold = max(sixtyMinutePace * 1.03, tenKPace)
        let fiveK = equivalent(seconds: anchor.seconds, meters: anchor.meters, to: 5_000)
        paces.interval = fiveK <= 30 * 60 ? fiveK / 5 : nil
        return paces
    }

    /// The race forecast from the anchor in force (PZ-4), or nil with effort only.
    static func forecast(
        _ distance: RaceDistance,
        paces: TrainingPaces,
        firstTime: Bool,
        weeklyMeters: Double,
        age: Int,
        now: Date,
        calendar: Calendar
    ) -> RaceForecast? {
        guard let anchor = paces.anchor else { return nil }
        var k = 1.07
        var central = equivalent(seconds: anchor.seconds, meters: anchor.meters, to: distance.meters, k: k)
        switch distance {
        case .halfMarathon:
            if firstTime || central > 2 * 3_600 || anchor.meters <= 5_000 || weeklyMeters < 25_000 { k = 1.10 }
        case .marathon:
            k = 1.12
            if firstTime || weeklyMeters < 40_000 || age >= 50 || anchor.meters <= 10_000 { k = 1.15 }
        default:
            break
        }
        central = equivalent(seconds: anchor.seconds, meters: anchor.meters, to: distance.meters, k: k)

        var range: Double
        if abs(anchor.meters - distance.meters) < 1 {
            range = 0.03
        } else {
            range = distance == .marathon ? 0.08 : 0.05
        }
        let fiveK = equivalent(seconds: anchor.seconds, meters: anchor.meters, to: 5_000)
        if distance == .marathon, central > 4.5 * 3_600 { range += 0.04 }
        if distance != .marathon, fiveK > 30 * 60 { range += 0.02 }
        let ageWeeks = (calendar.dateComponents([.day], from: anchor.date, to: now).day ?? 0) / 7
        if ageWeeks >= 13 { range += 0.03 }
        if anchor.course == .hilly { range += 0.02 }
        let confidence: ForecastConfidence = distance.meters > 4.5 * anchor.meters || anchor.treadmill ? .low : .normal
        return RaceForecast(
            distance: distance,
            central: central,
            low: central * (1 - range),
            high: central * (1 + range),
            k: k,
            confidence: confidence,
            rangeFraction: range
        )
    }

    /// PZ-11: max heart rate 208 − 0.7 × age, a lab value only if lower, raised by an observed max.
    static func heartRateZones(age: Int, settings: HeartRateSettings, observedMax: Double? = nil, threshold: Double? = nil) -> HeartRateZones {
        var zones = HeartRateZones.estimated(age: age, labMax: settings.labMax)
        if let observedMax, observedMax > zones.max {
            zones.max = observedMax
            zones.maxObserved = true
        }
        zones.threshold = threshold
        return zones
    }
}
