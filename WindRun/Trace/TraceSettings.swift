//
//  TraceSettings.swift
//  Wind Run
//

import Foundation

/// Which setting changes the trace shows the new value of. Every write to the app's settings gets a line,
/// but only settings that are plain choices, such as units or a switch, show what they became. Weight,
/// heart rate zones, dates and saved workouts only show that they changed.
enum TraceSettings {
    /// Settings whose values say nothing about who the runner is.
    static let shownKeys: Set<String> = [
        DistanceUnit.storageKey,
        Appearance.storageKey,
        PaceCalloutSettings.modeKey,
        PaceCalloutSettings.distanceKey,
        PaceCalloutSettings.secondsKey,
        PaceCalloutSettings.pacesKey,
        HapticDevices.storageKey,
        HapticPattern.storageKey,
        HealthSync.enabledKey,
        HeartRateMonitor.storageKey,
        MotionMonitor.stepsKey,
        AutoPause.storageKey,
        TermsAcceptance.versionKey,
        PromptQueue.answeredKey,
        WindRunStore.iCloudSyncKey,
        Trace.storageKey,
    ]

    /// Keys system frameworks keep in the app's settings, which aren't the runner's doing.
    private static let systemPrefixes = ["com.apple.", "Apple", "NS", "WebKit", "AK", "PK", "MSV", "INNext", "CK", "_"]

    /// The app's own settings as text, for comparing.
    static func snapshot(_ defaults: UserDefaults = .standard) -> [String: String] {
        let domain = Bundle.main.bundleIdentifier.flatMap(defaults.persistentDomain(forName:)) ?? [:]
        var values: [String: String] = [:]
        for (key, value) in domain where !systemPrefixes.contains(where: key.hasPrefix) {
            values[key] = String(describing: value)
        }
        return values
    }

    /// One entry per changed setting: its key and what the trace shows of its new value.
    static func changes(from old: [String: String], to new: [String: String]) -> [(key: String, value: String)] {
        let keys = Set(old.keys).union(new.keys).filter { old[$0] != new[$0] }
        return keys.sorted().map { key in
            guard let value = new[key] else { return (key, "removed") }
            return (key, shownKeys.contains(key) ? value : "changed (hidden)")
        }
    }
}
