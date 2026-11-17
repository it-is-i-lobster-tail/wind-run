//
//  CoachHeartRateStore.swift
//  Wind Run
//

import Foundation

/// The coach's heart-rate settings (IN-17), kept with the app's settings rather than in the coach
/// state. Like every setting, they go to the runner's private iCloud while iCloud Sync is on.
///
/// "Use heart rate" is the same switch as Heart rate in Settings (`HeartRateMonitor.storageKey`), so the
/// coach never says heart rate is on while runs record none. The rest (Show only, a lab-tested maximum)
/// is kept here.
enum CoachHeartRateStore {
    static let storageKey = "coachHeartRateSettings"

    /// The saved settings, with `enabled` read from the Heart rate switch. Off until the runner turns it
    /// on, here, in Settings, or on the first-open question.
    static func load(from defaults: UserDefaults = .standard) -> HeartRateSettings {
        var settings = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(HeartRateSettings.self, from: $0) }
            ?? HeartRateSettings()
        settings.enabled = defaults.bool(forKey: HeartRateMonitor.storageKey)
        return settings
    }

    /// Saves the coach's choices and sets the Heart rate switch to match. Turning it on here doesn't ask
    /// Health for access: callers do that with `HeartRateMonitor.turnOn()`.
    static func save(_ settings: HeartRateSettings, to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(settings), forKey: storageKey)
        defaults.set(settings.enabled, forKey: HeartRateMonitor.storageKey)
    }
}
