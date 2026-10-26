//
//  AppearanceTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
import UIKit
@testable import WindRun

/// Following the iPhone's light or dark setting, or a pick of the runner's own.
@MainActor
final class AppearanceTests {
    private let suiteName = "AppearanceTests-\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let cloud = InMemoryKeyValueStore()

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test("Until the runner picks, the app follows the iPhone")
    func followsSystemByDefault() {
        #expect(Appearance.current(in: defaults) == .system)
        #expect(Appearance.system.interfaceStyle == .unspecified)

        defaults.set("sepia", forKey: Appearance.storageKey)
        #expect(Appearance.current(in: defaults) == .system)
    }

    @Test("Light and Dark hold whatever the iPhone is set to")
    func picksOverrideSystem() {
        defaults.set(Appearance.dark.rawValue, forKey: Appearance.storageKey)
        #expect(Appearance.current(in: defaults) == .dark)
        #expect(Appearance.dark.interfaceStyle == .dark)
        #expect(Appearance.light.interfaceStyle == .light)
    }

    @Test("The pick goes to iCloud with the other settings, and comes back on a new iPhone")
    func syncsThroughICloud() {
        #expect(CloudSettings.keys.contains(Appearance.storageKey))

        defaults.set(Appearance.light.rawValue, forKey: Appearance.storageKey)
        CloudSettings(defaults: defaults, cloud: cloud) { _, _ in }.startSyncing()
        #expect(cloud.object(forKey: CloudSettings.cloudPrefix + Appearance.storageKey) as? String == "light")

        let newPhone = UserDefaults(suiteName: suiteName + "-new")!
        defer { UserDefaults().removePersistentDomain(forName: suiteName + "-new") }
        CloudSettings(defaults: newPhone, cloud: cloud) { _, _ in }.startSyncing()
        #expect(Appearance.current(in: newPhone) == .light)
    }
}
