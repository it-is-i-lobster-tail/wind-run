//
//  PaceTypes.swift
//  Wind Run
//

import Foundation

/// Where the easy band came from (PZ-5, PZ-8).
enum EasyPaceSource: String, Codable {
    /// The pace the runner gave at intake.
    case reported
    /// 5K pace × 1.28 to × 1.40, from the anchor.
    case anchor
    /// The median of the last easy runs rated 2-3.
    case logged
    /// No pace yet: effort targets only (PZ-6).
    case effortOnly
}

/// Training paces from current ability, never from the goal (PZ-5). Seconds per km.
struct TrainingPaces: Codable, Hashable {
    /// The easy and long-run band. Only its fast edge is a limit: there's no minimum speed.
    var easy: PaceBand?
    var easySource: EasyPaceSource
    /// 60-min race pace + 3%, never faster than 10K pace. Nil means effort only.
    var threshold: Double?
    /// Current 5K pace; nil when 5K is slower than 30:00 (RPE only).
    var interval: Double?
    /// The central race forecast, for steady and race-pace work (only when the time goal is Realistic or Stretch).
    var racePace: Double?
    /// The anchor in force (PZ-2), if any.
    var anchor: RaceResult?
    /// Quality paces' running adjustment from PZ-7: 0.99 is 1% faster, 1.03 is 3% slower.
    var qualityFactor: Double
    /// The last 1% raise, for HL-27's once per 2 weeks.
    var lastRaise: Date?

    init(
        easy: PaceBand? = nil,
        easySource: EasyPaceSource = .effortOnly,
        threshold: Double? = nil,
        interval: Double? = nil,
        racePace: Double? = nil,
        anchor: RaceResult? = nil,
        qualityFactor: Double = 1,
        lastRaise: Date? = nil
    ) {
        self.easy = easy
        self.easySource = easySource
        self.threshold = threshold
        self.interval = interval
        self.racePace = racePace
        self.anchor = anchor
        self.qualityFactor = qualityFactor
        self.lastRaise = lastRaise
    }

    /// A representative easy pace for converting between distance and time: the band's middle.
    var easyPace: Double? { easy?.middle }

    var thresholdPace: Double? { threshold.map { $0 * qualityFactor } }

    var intervalPace: Double? { interval.map { $0 * qualityFactor } }
}

/// How sure a forecast is (PZ-4).
enum ForecastConfidence: String, Codable {
    case normal
    /// The goal is more than 4.5 times the anchor distance, or the anchor is a treadmill result.
    case low
}

/// A race-time forecast from the anchors (PZ-4): "about 2 in 3 runners land inside" the range.
struct RaceForecast: Codable, Hashable {
    var distance: RaceDistance
    /// Central time in seconds; the plan pace is always the central value.
    var central: Double
    var low: Double
    var high: Double
    /// The exponent used: 1.07 up to the half, 1.12 for the marathon, or the conservative value.
    var k: Double
    var confidence: ForecastConfidence
    /// The range's half-width as a fraction (0.05 is ±5%).
    var rangeFraction: Double

    /// Plan pace, seconds per km.
    var pace: Double { central / distance.meters * 1_000 }
}

/// Heart-rate source (IN-17).
enum HeartRateDevice: String, Codable, CaseIterable {
    case off
    case appleWatch
    case chestStrap
    /// AirPods Pro 3 or Powerbeats Pro 2: shown only, never used.
    case earbuds

    var name: String {
        switch self {
        case .off: "Off"
        case .appleWatch: "Apple Watch"
        case .chestStrap: "Chest strap"
        case .earbuds: "AirPods or Powerbeats"
        }
    }

    var screenText: String? {
        switch self {
        case .off: nil
        case .appleWatch: "Your watch's heart rate is used on steady stretches and on reps of 4 minutes or more. In shorter reps, hills and strides, pace and effort lead."
        case .chestStrap: "Chest straps are the most accurate. Connect it before you start each run."
        case .earbuds: "AirPods and Powerbeats heart rate is shown during runs but not used for coaching yet."
        }
    }
}

/// The runner's heart-rate settings (IN-17). Kept on the device, never in iCloud.
struct HeartRateSettings: Codable, Hashable {
    var device: HeartRateDevice
    /// "Use heart rate for coaching: On / Show only". Off means Show only, for any reason.
    var useForCoaching: Bool
    /// A lab-measured max heart rate replaces the estimate only if lower (PZ-11).
    var labMax: Double?

    init(device: HeartRateDevice = .off, useForCoaching: Bool = true, labMax: Double? = nil) {
        self.device = device
        self.useForCoaching = useForCoaching
        self.labMax = labMax
    }

    static let off = HeartRateSettings()

    static let question = "Want to use heart rate? It's optional. Your plan works without it. With it, Coach can fine-tune your effort on steady runs and longer intervals, and spot when you're getting fitter."
    static let showOnlyHint = "If a medicine or condition affects your heart rate, choose Show only."
    static let privacyNote = "Heart rate stays on this device and is never stored in iCloud."

    /// Whether heart rate can feed any rule at all.
    var canCoach: Bool { useForCoaching && (device == .appleWatch || device == .chestStrap) }
}

/// Heart-rate numbers from age, or an observed or lab max (PZ-11, PZ-12). Bpm.
struct HeartRateZones: Codable, Hashable {
    /// 208 − 0.7 × age, or a lower lab value.
    var max: Double
    /// True when `max` was raised from races or tests (an observed HRmax).
    var maxObserved: Bool
    /// Threshold HR from a 40-70 min race or all-out run, if one exists.
    var threshold: Double?
    /// The mean HR of the latest easy runs that felt easy, once 3 or more exist (PZ-12).
    var personalEasyCeiling: Double?

    /// Easy and long runs: 75% of an estimated HRmax, 80% of an observed one, or the personal ceiling when lower.
    var easyCeiling: Double { Swift.min((max * (maxObserved ? 0.80 : 0.75)).rounded(), personalEasyCeiling ?? .infinity) }

    /// Threshold and tempo band: 95-100% of THR, or 85-90% of HRmax without one.
    var thresholdBand: ClosedRange<Double> {
        if let threshold {
            return (threshold * 0.95).rounded()...threshold.rounded()
        }
        return (max * 0.85).rounded()...(max * 0.90).rounded()
    }

    /// Steady segments never creep above threshold: the band's top.
    var steadyCeiling: Double { thresholdBand.upperBound }

    /// The in-run cue fires when HR is this far over a ceiling for 60 s: 5 bpm with a strap, 10 with a watch.
    static func cueMargin(for device: HeartRateDevice) -> Double {
        device == .chestStrap ? 5 : 10
    }

    /// PZ-11: the estimate from age, lowered by a lab value.
    static func estimated(age: Int, labMax: Double? = nil) -> HeartRateZones {
        let estimate = (208 - 0.7 * Double(age)).rounded()
        let maxValue = labMax.map { Swift.min($0, estimate) } ?? estimate
        return HeartRateZones(max: maxValue, maxObserved: false, threshold: nil)
    }

    static let easeOffCue = "Heart rate is above your ceiling. Ease off a little."
}
