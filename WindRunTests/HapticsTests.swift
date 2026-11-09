//
//  HapticsTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The buzzes at step changes: which devices play them, and the pattern both devices share.
@MainActor
final class HapticsTests {
    private let suiteName = "HapticsTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test("Until the runner picks, both devices buzz in the standard pattern")
    func startsWithDefaults() {
        #expect(HapticDevices.current(in: defaults) == .both)
        #expect(HapticPattern.current(in: defaults) == .standard)
    }

    @Test("The iPhone buzzes only when the runner picked it or both")
    func devicesOnPhone() {
        #expect(HapticDevices.both.includesThisDevice)
        #expect(HapticDevices.iPhone.includesThisDevice)
        #expect(!HapticDevices.watch.includesThisDevice)
        #expect(!HapticDevices.off.includesThisDevice)
    }

    @Test("The choices read back from settings")
    func readsChoices() {
        defaults.set(HapticDevices.watch.rawValue, forKey: HapticDevices.storageKey)
        defaults.set(HapticPattern.strong.rawValue, forKey: HapticPattern.storageKey)
        #expect(HapticDevices.current(in: defaults) == .watch)
        #expect(HapticPattern.current(in: defaults) == .strong)
    }

    @Test("Standard keeps the taps the watch had before the setting")
    func standardPattern() {
        let pattern = HapticPattern.standard
        #expect(pattern.taps(for: .work) == [.start])
        #expect(pattern.taps(for: .easy) == [.stop])
        #expect(pattern.taps(for: .finished) == [.success])
        #expect(pattern.taps(for: .reminder) == [.notification])
        #expect(pattern.taps(for: .countdown) == [.click])
        #expect(pattern.taps(for: .paused) == [.down])
        #expect(pattern.taps(for: .resumed) == [.up])
    }

    @Test("Gentle skips the countdown, and strong buzzes more for work than for easy steps")
    func otherPatterns() {
        #expect(HapticPattern.gentle.taps(for: .countdown).isEmpty)
        #expect(HapticPattern.gentle.taps(for: .work) == [.click])
        #expect(HapticPattern.strong.taps(for: .work).count == 3)
        #expect(HapticPattern.strong.taps(for: .easy).count == 2)
    }

    @Test("Every pattern buzzes for every step change")
    func everyStepChangeBuzzes() {
        for pattern in HapticPattern.allCases {
            for haptic in StepHaptic.allCases where haptic != .countdown {
                #expect(!pattern.taps(for: haptic).isEmpty, "\(pattern) \(haptic)")
            }
        }
    }

    @Test("Both choices follow the runner to the watch and to iCloud")
    func choicesSync() {
        for key in [HapticDevices.storageKey, HapticPattern.storageKey] {
            #expect(SettingsSync.keys.contains(key))
            #expect(CloudSettings.keys.contains(key))
        }
    }
}
