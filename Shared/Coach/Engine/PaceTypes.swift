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
    /// Every valid race and test result kept (PZ-2), newest last: the forecast set and the personal k read them.
    var results: [RaceResult]
    /// A faster anchor whose paces are still being reached 1% at a time (PZ-7, PZ-7a).
    var anchorRaisePending: Bool
    /// PZ-2's volume adjustment is in force: weekly km under 60% of the month before the result, so quality paces
    /// run 5% slower (`volumeFactor`) until the volume is back.
    var volumeAdjusted: Bool
    /// A break of more than 28 days expired every result dated before this day (PZ-2).
    var expiredBefore: Date?

    init(
        easy: PaceBand? = nil,
        easySource: EasyPaceSource = .effortOnly,
        threshold: Double? = nil,
        interval: Double? = nil,
        racePace: Double? = nil,
        anchor: RaceResult? = nil,
        qualityFactor: Double = 1,
        lastRaise: Date? = nil,
        results: [RaceResult] = [],
        anchorRaisePending: Bool = false,
        volumeAdjusted: Bool = false,
        expiredBefore: Date? = nil
    ) {
        self.easy = easy
        self.easySource = easySource
        self.threshold = threshold
        self.interval = interval
        self.racePace = racePace
        self.anchor = anchor
        self.qualityFactor = qualityFactor
        self.lastRaise = lastRaise
        self.results = results
        self.anchorRaisePending = anchorRaisePending
        self.volumeAdjusted = volumeAdjusted
        self.expiredBefore = expiredBefore
    }

    /// A representative easy pace for converting between distance and time: the band's middle.
    var easyPace: Double? { easy?.middle }

    /// PZ-2: quality paces run 5% slower while weekly distance is under 60% of the month before the anchor.
    static let volumeSlowdown = 1.05

    /// The threshold pace sessions use: the base pace × PZ-7's factor, 5% slower under PZ-2's volume rule.
    var thresholdPace: Double? { threshold.map { $0 * qualityFactor * volumeFactor } }

    /// The interval pace sessions use, adjusted as `thresholdPace` is.
    var intervalPace: Double? { interval.map { $0 * qualityFactor * volumeFactor } }

    var volumeFactor: Double { volumeAdjusted ? Self.volumeSlowdown : 1 }
}

/// How a new race or test result moved the anchor and the paces (PZ-2, PZ-7, PZ-7a).
enum AnchorChange: Hashable {
    /// The first anchor: paces set at once.
    case first
    /// Faster by this fraction: forecasts move at once, quality paces 1% at a time.
    case faster(Double)
    /// Slower by this fraction: paces move down at once.
    case slower(Double)
    /// Within 1% of the anchor before it (SW-7a's "no clear change").
    case noClearChange
    /// Not the anchor in force: older than it, on a very hilly course, or already recorded.
    case notUsed
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
    /// The result the slowest forecast came from (PZ-2's forecast set).
    var anchorID: UUID? = nil
    /// From a controlled test (PZ-2, PZ-3).
    var lowPrecision: Bool = false
    /// The durability check failed or had no qualifying run (PZ-4): the conservative k, and run-walk offered (EF-4).
    var durabilityFailed: Bool = false

    /// Plan pace, seconds per km.
    var pace: Double { central / distance.meters * 1_000 }
}

/// What a forecast needs besides the results (PZ-4, EF-1).
struct ForecastContext: Hashable {
    /// No finish at the distance in about 18 months (TI-3).
    var firstTime: Bool
    /// Weekly distance now, in meters.
    var weeklyMeters: Double
    var age: Int
    /// PZ-4's durability check for forecasts over 2 hours. Nil when no run qualifies, which counts as a fail.
    var durable: Bool?
    /// Fully missed plan weeks: +1 range point each, at most 4 (PZ-4, EF-1).
    var missedWeeks: Int

    init(firstTime: Bool, weeklyMeters: Double, age: Int, durable: Bool? = nil, missedWeeks: Int = 0) {
        self.firstTime = firstTime
        self.weeklyMeters = weeklyMeters
        self.age = age
        self.durable = durable
        self.missedWeeks = missedWeeks
    }
}

/// Heart-rate source (IN-17). The app finds it from each run's readings; the runner never picks it. When more
/// than one is worn, a strap or other sensor wins, then Apple Watch, then earbuds.
enum HeartRateDevice: String, Codable, CaseIterable {
    case off
    case appleWatch
    /// A chest strap or another sensor paired in Settings.
    case chestStrap
    /// AirPods Pro 3 or Powerbeats Pro 2: shown only, never used.
    case earbuds

    var name: String {
        switch self {
        case .off: "None"
        case .appleWatch: "Apple Watch"
        case .chestStrap: "Strap or sensor"
        case .earbuds: "AirPods or Powerbeats"
        }
    }
}

/// The runner's heart-rate settings (IN-17). Kept on the device, never in iCloud.
struct HeartRateSettings: Codable, Hashable {
    /// "Use heart rate?": the one question setup asks.
    var enabled: Bool
    /// The source to read with: the app sets it to the one found on the latest run with heart rate
    /// (`detectingSource(from:)`). Off until one is found, or when heart rate isn't used.
    var device: HeartRateDevice
    /// "Use heart rate for coaching: On / Show only", in plan settings. Off means Show only, for any reason.
    var useForCoaching: Bool
    /// A lab-measured max heart rate replaces the estimate only if lower (PZ-11).
    var labMax: Double?

    init(device: HeartRateDevice = .off, useForCoaching: Bool = true, labMax: Double? = nil, enabled: Bool? = nil) {
        self.enabled = enabled ?? (device != .off)
        self.device = device
        self.useForCoaching = useForCoaching
        self.labMax = labMax
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, device, useForCoaching, labMax
    }

    /// Settings saved before `enabled` existed were on whenever a source was picked.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let device = try container.decodeIfPresent(HeartRateDevice.self, forKey: .device) ?? .off
        self.init(
            device: device,
            useForCoaching: try container.decodeIfPresent(Bool.self, forKey: .useForCoaching) ?? true,
            labMax: try container.decodeIfPresent(Double.self, forKey: .labMax),
            enabled: try container.decodeIfPresent(Bool.self, forKey: .enabled)
        )
    }

    static let off = HeartRateSettings()

    static let question = "Your plan works without it. With it, Coach can fine-tune your effort on steady runs and longer intervals, and spot when you're getting fitter."
    static let sourceNote = "Wind Run picks the best sensor you're wearing: a heart rate strap or sensor, then Apple Watch, then AirPods or Powerbeats, which are shown during runs but not used for coaching yet."
    static let showOnlyHint = "If a medicine or condition affects your heart rate, choose Show only."
    static let showOnlySetupHint = "If a medicine or condition affects your heart rate, you can set it to Show only in Plan settings."
    static let privacyNote = "Heart rate stays on this device and is never stored in iCloud."

    /// Whether the runner lets heart rate coach at all, whatever the source turns out to be.
    var coachingAllowed: Bool { enabled && useForCoaching }

    /// Whether heart rate can feed any rule at all.
    var canCoach: Bool { coachingAllowed && (device == .appleWatch || device == .chestStrap) }
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
