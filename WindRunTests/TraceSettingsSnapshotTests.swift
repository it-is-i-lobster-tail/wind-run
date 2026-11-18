//
//  TraceSettingsSnapshotTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The settings the trace compares leave out the keys system frameworks keep in the app's settings.
@MainActor
struct TraceSettingsSnapshotTests {
    @Test func systemKeysArentTheRunnersSettings() throws {
        let suiteName = "TraceSettingsSnapshotTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        defaults.set("miles", forKey: DistanceUnit.storageKey)
        for key in ["NSLanguages", "com.apple.foo", "_x", "AKThing", "AppleLocale", "WebKitThing", "PKThing", "MSVThing", "INNextThing", "CKThing"] {
            defaults.set("system", forKey: key)
        }

        let snapshot = TraceSettings.snapshot(defaults, domain: suiteName)
        #expect(snapshot == [DistanceUnit.storageKey: "miles"])
    }

    @Test func noDomainIsNoSettings() {
        #expect(TraceSettings.snapshot(.standard, domain: nil).isEmpty)
    }
}
