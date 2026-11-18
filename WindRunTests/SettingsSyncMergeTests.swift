//
//  SettingsSyncMergeTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// Settings from the other device merged key by key: removed settings, ones that can't be read, an older
/// app's overall date, and the lists of what syncs where.
@MainActor
struct SettingsSyncMergeTests {
    private let defaults = UserDefaults(suiteName: "SettingsSyncMergeTests.\(UUID().uuidString)")!
    private let sent = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private let later = Date(timeIntervalSinceReferenceDate: 2_000_000)

    @Test func theirDateForEachKind() {
        let key = HapticPattern.storageKey
        let theirs = Date(timeIntervalSinceReferenceDate: 500)
        // An older app, with only an overall date.
        #expect(SettingsSync.theirChangeDate(for: key, theirDates: nil, ourDates: [key: later], received: sent) == sent)
        // Changed there.
        #expect(SettingsSync.theirChangeDate(for: key, theirDates: [key: theirs], ourDates: [key: later], received: sent) == theirs)
        // Changed on neither.
        #expect(SettingsSync.theirChangeDate(for: key, theirDates: [:], ourDates: [:], received: sent) == sent)
        // Changed only here: theirs loses.
        #expect(SettingsSync.theirChangeDate(for: key, theirDates: [:], ourDates: [key: later], received: sent) == .distantPast)
    }

    @Test func aSettingRemovedThereIsRemovedHere() {
        let sync = SettingsSync(defaults: defaults)
        defaults.set(HapticPattern.strong.rawValue, forKey: HapticPattern.storageKey)

        sync.receive([:], changedAt: later, keyChangedAt: [HapticPattern.storageKey: later], removed: [HapticPattern.storageKey])

        #expect(defaults.object(forKey: HapticPattern.storageKey) == nil)
        #expect(sync.keyChangedAt[HapticPattern.storageKey] == later)
    }

    @Test func aWeightThatIsNotANumberIsSkipped() {
        let sync = SettingsSync(defaults: defaults)
        defaults.set(70.0, forKey: BodyWeight.storageKey)

        sync.receive([BodyWeight.storageKey: "abc"], changedAt: later, keyChangedAt: [BodyWeight.storageKey: later])

        #expect(defaults.object(forKey: BodyWeight.storageKey) as? Double == 70)
        #expect(sync.keyChangedAt[BodyWeight.storageKey] == nil)
    }

    @Test func anOlderAppLeavesThePerKeyDatesAlone() {
        let sync = SettingsSync(defaults: defaults)

        sync.receive([DistanceUnit.storageKey: DistanceUnit.miles.rawValue], changedAt: sent)

        #expect(defaults.string(forKey: DistanceUnit.storageKey) == DistanceUnit.miles.rawValue)
        #expect(sync.keyChangedAt.isEmpty)
        #expect(sync.changedAt == sent)
    }

    @Test func watchSyncedSettingsAlsoGoToICloud() {
        #expect(Set(SettingsSync.keys).isSubset(of: Set(CloudSettings.keys)))
        #expect(SettingsSync.numberKeys.isSubset(of: Set(SettingsSync.keys)))
    }

    @Test func aWaitingRunIsFoundByItsFileName() {
        let id = UUID().uuidString
        #expect(SettingsSync.runID(fromPendingFileName: "run-\(id)") == id)
        #expect(SettingsSync.runID(fromPendingFileName: "other") == nil)
        #expect(SettingsSync.runID(fromPendingFileName: ".DS_Store") == nil)
    }
}
