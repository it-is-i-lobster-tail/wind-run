//
//  HeartRateTypes.swift
//  Wind Run
//

import Foundation

/// Heart-rate source (IN-17). The app finds it from each run's readings; the runner never picks it. When more
/// than one is worn, a strap or other sensor wins, then Apple Watch, then earbuds.
enum HeartRateDevice: String, Codable, CaseIterable {
    case off
    case appleWatch
    /// A chest strap or another sensor paired in Settings.
    case chestStrap
    /// AirPods Pro 3 or Powerbeats Pro 2: shown only, never used.
    case earbuds
}

/// The runner's heart-rate settings (IN-17). Kept on the device, never in iCloud.
struct HeartRateSettings: Codable, Hashable {
    /// "Use heart rate?": the one question setup asks.
    var enabled: Bool
    /// The source to read with. Off until one is found, or when heart rate isn't used.
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

    static let question = "Your plan works without it. With it, Coach tells you to ease off when your heart rate climbs too high on easy and long runs."
    static let sourceNote = "Wind Run picks the best sensor you're wearing: a heart rate strap or sensor, then Apple Watch, then AirPods or Powerbeats, which are shown during runs but not used for coaching yet."
    static let sameSwitchNote = "This is the same switch as Heart rate in Settings."
    static let showOnlyHint = "If a medicine or condition affects your heart rate, choose Show only."
    static let privacyNote = "Heart rate stays on this device and is never stored in iCloud."

    /// Whether the runner lets heart rate coach at all, whatever the source turns out to be.
    var coachingAllowed: Bool { enabled && useForCoaching }
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

    /// The in-run cue fires when HR is this far over a ceiling for 60 s: 5 bpm with a strap, 10 with a watch.
    static func cueMargin(for device: HeartRateDevice) -> Double {
        device == .chestStrap ? 5 : 10
    }

    /// A lab-tested maximum outside this is taken as a typo and left out, so it can't set a ceiling no one runs under.
    static let plausibleMax: ClosedRange<Double> = 120...230

    /// PZ-11: the estimate from age, lowered by a lab value.
    static func estimated(age: Int, labMax: Double? = nil) -> HeartRateZones {
        let estimate = (208 - 0.7 * Double(age)).rounded()
        let maxValue = labMax.flatMap { plausibleMax.contains($0) ? Swift.min($0, estimate) : nil } ?? estimate
        return HeartRateZones(max: maxValue, maxObserved: false, threshold: nil)
    }
}
