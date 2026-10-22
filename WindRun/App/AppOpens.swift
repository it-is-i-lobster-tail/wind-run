//
//  AppOpens.swift
//  Wind Run
//

import Foundation

/// When the app was last opened, for coach setup: after more than 12 weeks away, a new plan asks "Your running so
/// far" and "Your running lately" again (Brendon, 2026-10-22). Kept on this device; it isn't a setting.
enum AppOpens {
    static let lastOpenedKey = "lastOpenedDate"
    static let longBreakKey = "backAfterLongBreak"

    /// Records an app open. One more than 12 weeks after the last marks the runner as back from a long break until
    /// their next plan starts.
    static func record(now: Date = .now, calendar: Calendar = .current, defaults: UserDefaults = .standard) {
        if let last = defaults.object(forKey: lastOpenedKey) as? Date,
           IntakeFlow.days(from: last, to: now, calendar: calendar) > 84 {
            defaults.set(true, forKey: longBreakKey)
        }
        defaults.set(now, forKey: lastOpenedKey)
    }

    static func backAfterLongBreak(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: longBreakKey)
    }

    /// A plan started, so the running screens have been asked.
    static func clearLongBreak(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: longBreakKey)
    }
}
