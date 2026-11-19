//
//  CloudSettingsTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// Settings in iCloud, with a dictionary standing in for iCloud's key-value store.
@MainActor
final class CloudSettingsTests {
    private let suiteName = "CloudSettingsTests-\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let cloud = InMemoryKeyValueStore()
    private var healthAsks: [(heartRate: Bool, savesToHealth: Bool)] = []

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func makeSettings() -> CloudSettings {
        CloudSettings(defaults: defaults, cloud: cloud) { [weak self] heartRate, savesToHealth in
            self?.healthAsks.append((heartRate, savesToHealth))
        }
    }

    private func inCloud(_ key: String) -> Any? {
        cloud.object(forKey: CloudSettings.cloudPrefix + key)
    }

    @Test("Turning sync on sends up the settings iCloud doesn't have yet")
    func startUploads() {
        defaults.set(DistanceUnit.miles.rawValue, forKey: DistanceUnit.storageKey)
        defaults.set(400.0, forKey: PaceCalloutSettings.distanceKey)

        makeSettings().startSyncing()

        #expect(inCloud(DistanceUnit.storageKey) as? String == "miles")
        #expect(inCloud(PaceCalloutSettings.distanceKey) as? Double == 400)
    }

    /// A device's first sync may come before iCloud has sent what's there, and its own settings would beat the
    /// old iPhone's, so it waits for iCloud's first download before sending up anything.
    @Test("A first sync waits for iCloud's settings before sending up this iPhone's own")
    func firstSyncWaitsForICloud() {
        cloud.downloadsFirst = true
        defaults.set(DistanceUnit.kilometers.rawValue, forKey: DistanceUnit.storageKey)
        defaults.set(400.0, forKey: PaceCalloutSettings.distanceKey)
        let settings = makeSettings()

        settings.startSyncing()
        #expect(inCloud(DistanceUnit.storageKey) == nil)
        #expect(inCloud(PaceCalloutSettings.distanceKey) == nil)

        // The first download brings the old iPhone's units, which win; what iCloud didn't have then goes up.
        cloud.set(DistanceUnit.miles.rawValue, forKey: CloudSettings.cloudPrefix + DistanceUnit.storageKey)
        settings.cloudChanged([CloudSettings.cloudPrefix + DistanceUnit.storageKey], reason: NSUbiquitousKeyValueStoreInitialSyncChange)
        #expect(defaults.string(forKey: DistanceUnit.storageKey) == "miles")
        #expect(inCloud(DistanceUnit.storageKey) as? String == "miles")
        #expect(inCloud(PaceCalloutSettings.distanceKey) as? Double == 400)
        #expect(defaults.bool(forKey: CloudSettings.downloadedKey))
        #expect(!CloudSettings.keys.contains(CloudSettings.downloadedKey))
        settings.stopSyncing(deletingCopy: false)
    }

    @Test("A new iPhone takes the settings already in iCloud")
    func startRestores() {
        defaults.set(DistanceUnit.kilometers.rawValue, forKey: DistanceUnit.storageKey)
        cloud.set(DistanceUnit.miles.rawValue, forKey: CloudSettings.cloudPrefix + DistanceUnit.storageKey)
        cloud.set("draft-2026-10-19", forKey: CloudSettings.cloudPrefix + TermsAcceptance.versionKey)

        makeSettings().startSyncing()

        #expect(defaults.string(forKey: DistanceUnit.storageKey) == "miles")
        #expect(defaults.string(forKey: TermsAcceptance.versionKey) == "draft-2026-10-19")
    }

    @Test("Changes made here go up while syncing, including a setting cleared here")
    func localChangesGoUp() {
        let settings = makeSettings()
        defaults.set(PaceCalloutMode.distance.rawValue, forKey: PaceCalloutSettings.modeKey)
        settings.startSyncing()

        defaults.set(DistanceUnit.miles.rawValue, forKey: DistanceUnit.storageKey)
        defaults.removeObject(forKey: PaceCalloutSettings.modeKey)
        settings.localSettingsChanged()

        #expect(inCloud(DistanceUnit.storageKey) as? String == "miles")
        #expect(inCloud(PaceCalloutSettings.modeKey) == nil)
    }

    @Test("Nothing goes up or comes in while sync is off")
    func offDoesNothing() {
        let settings = makeSettings()
        defaults.set(DistanceUnit.miles.rawValue, forKey: DistanceUnit.storageKey)
        settings.localSettingsChanged()
        #expect(cloud.values.isEmpty)

        cloud.set(DistanceUnit.kilometers.rawValue, forKey: CloudSettings.cloudPrefix + DistanceUnit.storageKey)
        settings.cloudChanged(nil)
        #expect(defaults.string(forKey: DistanceUnit.storageKey) == "miles")
    }

    @Test("Changes from another iPhone come in, and only settings are taken")
    func cloudChangesComeIn() {
        let settings = makeSettings()
        settings.startSyncing()

        cloud.set(DistanceUnit.miles.rawValue, forKey: CloudSettings.cloudPrefix + DistanceUnit.storageKey)
        cloud.set(["heartRate"], forKey: CloudSettings.cloudPrefix + PromptQueue.answeredKey)
        settings.cloudChanged([
            CloudSettings.cloudPrefix + DistanceUnit.storageKey,
            CloudSettings.cloudPrefix + PromptQueue.answeredKey,
        ])

        #expect(defaults.string(forKey: DistanceUnit.storageKey) == "miles")
        #expect(defaults.object(forKey: PromptQueue.answeredKey) == nil)
    }

    @Test("A setting deleted from iCloud by another device stays here")
    func deletedInCloudStaysHere() {
        defaults.set(DistanceUnit.miles.rawValue, forKey: DistanceUnit.storageKey)
        let settings = makeSettings()
        settings.startSyncing()

        cloud.removeObject(forKey: CloudSettings.cloudPrefix + DistanceUnit.storageKey)
        settings.cloudChanged([CloudSettings.cloudPrefix + DistanceUnit.storageKey])

        #expect(defaults.string(forKey: DistanceUnit.storageKey) == "miles")
    }

    @Test("Turning sync off deletes the settings in iCloud, unless the copy is kept")
    func stopDeletes() {
        defaults.set(DistanceUnit.miles.rawValue, forKey: DistanceUnit.storageKey)
        let settings = makeSettings()

        settings.startSyncing()
        settings.stopSyncing(deletingCopy: false)
        #expect(inCloud(DistanceUnit.storageKey) as? String == "miles")

        settings.startSyncing()
        settings.stopSyncing(deletingCopy: true)
        #expect(cloud.values.isEmpty)
        #expect(defaults.string(forKey: DistanceUnit.storageKey) == "miles", "This iPhone keeps its settings")
        #expect(!settings.isSyncing)
    }

    @Test("A Health switch turned on elsewhere asks this iPhone for Health's permission")
    func healthSwitchAsks() async {
        let settings = makeSettings()
        settings.startSyncing()

        cloud.set(true, forKey: CloudSettings.cloudPrefix + HeartRateMonitor.storageKey)
        settings.cloudChanged([CloudSettings.cloudPrefix + HeartRateMonitor.storageKey])
        for _ in 0..<10 where healthAsks.isEmpty {
            await Task.yield()
        }

        #expect(healthAsks.count == 1)
        #expect(healthAsks.first?.heartRate == true)
        #expect(healthAsks.first?.savesToHealth == false)

        // Already on here, so nothing to ask.
        settings.cloudChanged([CloudSettings.cloudPrefix + HeartRateMonitor.storageKey])
        await Task.yield()
        #expect(healthAsks.count == 1)
    }

    @Test("Each device keeps its own prompt answers and iCloud Sync switch")
    func deviceOnlyKeys() {
        #expect(!CloudSettings.keys.contains(PromptQueue.answeredKey))
        #expect(!CloudSettings.keys.contains(WindRunStore.iCloudSyncKey))
        #expect(CloudSettings.keys.contains(DistanceUnit.storageKey))
    }

    @Test("Settings follow the iCloud Sync switch, and turning it off deletes them")
    func followsTheICloudSyncSwitch() async throws {
        defaults.set(DistanceUnit.miles.rawValue, forKey: DistanceUnit.storageKey)
        let settings = makeSettings()
        let store = WindRunStore(inMemory: true, iCloud: SignedInICloud(), defaults: defaults, settings: settings)
        #expect(!settings.isSyncing)

        try await store.turnOnICloudSync()
        #expect(settings.isSyncing)
        #expect(inCloud(DistanceUnit.storageKey) as? String == "miles")

        try await store.turnOffICloudSync()
        #expect(!settings.isSyncing)
        #expect(cloud.values.isEmpty)
    }

    @Test("Settings start syncing at launch when iCloud Sync is already on")
    func syncsAtLaunch() {
        defaults.set(true, forKey: WindRunStore.iCloudSyncKey)
        let settings = makeSettings()
        _ = WindRunStore(inMemory: true, iCloud: SignedInICloud(), defaults: defaults, settings: settings)
        #expect(settings.isSyncing)
    }
}

private struct SignedInICloud: ICloudCopy {
    func accountIsAvailable() async -> Bool { true }
    func delete() async throws {}
}

/// The three hand-kept settings key lists (iCloud, the watch and Trace), checked against each other.
@MainActor
struct SettingsKeyListTests {
    @Test func noListNamesAKeyTwice() {
        #expect(CloudSettings.keys.count == Set(CloudSettings.keys).count)
        #expect(SettingsSync.keys.count == Set(SettingsSync.keys).count)
    }

    @Test func watchSyncedKeysAreAlsoInICloud() {
        #expect(Set(SettingsSync.keys).isSubset(of: Set(CloudSettings.keys)))
        #expect(SettingsSync.numberKeys.isSubset(of: Set(SettingsSync.keys)))
        // The weight is stored as a number, so it must travel as one.
        #expect(SettingsSync.numberKeys.contains(BodyWeight.storageKey))
    }

    @Test func traceShowsOnlySyncedOrKnownDeviceKeys() {
        let known = Set(CloudSettings.keys).union([PromptQueue.answeredKey, WindRunStore.iCloudSyncKey, Trace.storageKey])
        #expect(TraceSettings.shownKeys.isSubset(of: known))
    }

    @Test func syncedKeysStayOutsideTheCloudPrefixAndTheWatchsOwnKeys() {
        for key in CloudSettings.keys + SettingsSync.keys {
            #expect(!key.hasPrefix(CloudSettings.cloudPrefix), "\(key)")
        }
        for deviceOnly in [SettingsSync.coachTodayKey, SettingsSync.savedWorkoutsKey] {
            #expect(!CloudSettings.keys.contains(deviceOnly))
            #expect(!SettingsSync.keys.contains(deviceOnly))
        }
    }
}
