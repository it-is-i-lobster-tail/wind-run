//
//  CoachHeartRateStore.swift
//  Wind Run
//

import Foundation

/// The coach's heart-rate settings (IN-17), kept on this device only and never in the coach state
/// or iCloud, since heart rate and anything derived from it stays on the device.
enum CoachHeartRateStore {
    static let storageKey = "coachHeartRateSettings"

    /// The saved settings, or heart rate on (with the source still to find) when the runner hasn't
    /// changed it: it's on by default, and plan settings turn it off.
    static func load(from defaults: UserDefaults = .standard) -> HeartRateSettings {
        guard let data = defaults.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(HeartRateSettings.self, from: data)
        else { return .defaultOn }
        return settings
    }

    static func save(_ settings: HeartRateSettings, to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: storageKey)
    }
}
