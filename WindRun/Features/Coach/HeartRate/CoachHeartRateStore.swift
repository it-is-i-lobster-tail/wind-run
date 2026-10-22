//
//  CoachHeartRateStore.swift
//  Wind Run
//

import Foundation

/// The coach's heart-rate settings (IN-17), kept on this device only and never in the coach state
/// or iCloud, since heart rate and anything derived from it stays on the device.
enum CoachHeartRateStore {
    static let storageKey = "coachHeartRateSettings"

    static func load(from defaults: UserDefaults = .standard) -> HeartRateSettings {
        guard let data = defaults.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(HeartRateSettings.self, from: data)
        else { return .off }
        return settings
    }

    /// Whether the runner has answered the heart-rate question before, so setup doesn't ask it again.
    static var isAnswered: Bool {
        UserDefaults.standard.data(forKey: storageKey) != nil
    }

    static func save(_ settings: HeartRateSettings, to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: storageKey)
    }
}
