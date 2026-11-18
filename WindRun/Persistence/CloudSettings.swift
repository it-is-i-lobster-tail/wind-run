//
//  CloudSettings.swift
//  Wind Run
//
//  Keeps the runner's settings in their private iCloud, alongside their runs.
//

import Foundation
import OSLog

/// What `CloudSettings` needs from iCloud's key-value store. Tests and previews swap in a dictionary.
protocol CloudKeyValueStore: AnyObject {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
    @discardableResult func synchronize() -> Bool
    /// Whether the store may not have iCloud's values yet the first time a device uses it. iCloud's own sends
    /// them down a moment later, and says so with a change.
    var downloadsFirst: Bool { get }
}

extension NSUbiquitousKeyValueStore: CloudKeyValueStore {
    var downloadsFirst: Bool { true }
}

/// Settings kept in memory only, for previews and tests.
final class InMemoryKeyValueStore: CloudKeyValueStore {
    private(set) var values: [String: Any] = [:]
    /// Set by a test to stand in for iCloud's first download.
    var downloadsFirst = false

    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
    func synchronize() -> Bool { true }
}

/// Copies every setting to the runner's private iCloud while iCloud Sync is on, and brings in the
/// ones changed on their other iPhones, so a new iPhone picks up right where they left off.
///
/// Turning iCloud Sync off deletes the settings there along with the runs. The watch gets its
/// units and call-outs from the iPhone (`SettingsSync`), so it doesn't use iCloud itself.
final class CloudSettings {
    /// Every setting kept in iCloud. Three things stay on each device on purpose: which first-open
    /// questions were answered, since permissions like Health's are per device, the iCloud Sync
    /// switch itself, which a new iPhone needs turned on to get anything back, and the Trace logging
    /// switch, which must only come on where the runner accepted its warning (`Trace.storageKey`).
    static let keys = [
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
        BodyWeight.storageKey,
        BodyWeight.dateKey,
        CoachHeartRateStore.storageKey,
        TermsAcceptance.versionKey,
        TermsAcceptance.dateKey,
        WorkoutGoalMemory.distanceKey,
        WorkoutGoalMemory.timeKey,
        DisplayScreen.storageKey,
        DisplayLibrary.screensKey,
        DisplayLibrary.defaultKey,
    ] + DisplayRunKind.storageKeys
    /// Settings sit under their own prefix in iCloud, so nothing else there is taken for one.
    static let cloudPrefix = "settings."
    /// Whether this device has had iCloud's settings since it last started syncing with a new account, so
    /// what it has that iCloud doesn't can go up without beating values iCloud hasn't sent yet. Kept on the
    /// device only.
    static let downloadedKey = "settings.iCloudSettingsDownloaded"
    /// How long a device's first sync waits for iCloud's settings before sending up its own.
    static let firstDownloadWait: Duration = .seconds(20)

    private(set) var isSyncing = false

    private let defaults: UserDefaults
    private let cloud: any CloudKeyValueStore
    /// Asks this device for Health's permission when a Health switch arrives turned on from iCloud.
    private let requestHealthAccess: @MainActor (_ heartRate: Bool, _ savesToHealth: Bool) async -> Void
    /// The values last sent or received, so applying a change from iCloud doesn't send it back.
    private var lastSynced: [String: NSObject] = [:]
    /// True while writing values that came from iCloud, which aren't a change made here.
    private var isApplyingCloud = false
    private var observers: [any NSObjectProtocol] = []
    /// The wait for iCloud's first settings, on a device that hasn't had them yet.
    private var firstDownload: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        cloud: any CloudKeyValueStore = NSUbiquitousKeyValueStore.default,
        askForHealth: @escaping @MainActor (_ heartRate: Bool, _ savesToHealth: Bool) async -> Void = {
            await CloudSettings.askForHealth(heartRate: $0, savesToHealth: $1)
        }
    ) {
        self.defaults = defaults
        self.cloud = cloud
        self.requestHealthAccess = askForHealth
    }

    /// Starts keeping settings in iCloud. What's already there wins, so a new iPhone takes the
    /// settings the runner left off with; anything iCloud doesn't have yet goes up from here.
    ///
    /// A device syncing for the first time may not have iCloud's settings yet, and its own would beat
    /// them, so it waits for iCloud to send them, or a short while, before sending its own.
    func startSyncing() {
        guard !isSyncing else { return }
        isSyncing = true
        cloud.synchronize()
        let before = snapshot()
        let hasDownloaded = !cloud.downloadsFirst || defaults.bool(forKey: Self.downloadedKey)
            || Self.keys.contains { cloud.object(forKey: Self.cloudKey($0)) != nil }
        let fromCloud = applyFromCloud(Self.keys)
        var uploaded = 0
        if hasDownloaded {
            defaults.set(true, forKey: Self.downloadedKey)
            uploaded = uploadOnlyHere()
        } else {
            waitForFirstDownload()
        }
        lastSynced = snapshot()
        catchUpHealth(from: before)
        observe()
        cloud.synchronize()
        Logger.settings.info("Settings sync with iCloud")
        Trace.log(.icloud, "Settings sync started", ["fromCloud": fromCloud, "uploaded": uploaded, "waitingForICloud": !hasDownloaded])
    }

    /// Stops keeping settings in iCloud. The settings on this iPhone stay as they are.
    func stopSyncing(deletingCopy: Bool) {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        firstDownload?.cancel()
        firstDownload = nil
        isSyncing = false
        Trace.log(.icloud, "Settings sync stopped", ["deletedCopy": deletingCopy])
        guard deletingCopy else { return }
        for key in Self.keys {
            cloud.removeObject(forKey: Self.cloudKey(key))
        }
        cloud.synchronize()
        Logger.settings.info("Deleted the settings in iCloud")
    }

    /// Sends up the settings this device has that iCloud doesn't, and says how many.
    private func uploadOnlyHere() -> Int {
        var count = 0
        for key in Self.keys where cloud.object(forKey: Self.cloudKey(key)) == nil {
            guard let value = defaults.object(forKey: key) else { continue }
            cloud.set(value, forKey: Self.cloudKey(key))
            count += 1
        }
        return count
    }

    /// Where a setting sits in iCloud.
    private static func cloudKey(_ key: String) -> String {
        cloudPrefix + key
    }

    /// Writes iCloud's value of each of these settings here, as values that came from iCloud rather than
    /// changes made here, and says how many there were.
    private func applyFromCloud(_ keys: [String]) -> Int {
        isApplyingCloud = true
        defer { isApplyingCloud = false }
        var applied = 0
        for key in keys {
            // A setting deleted from iCloud, because another device turned sync off, stays here.
            guard let value = cloud.object(forKey: Self.cloudKey(key)) else { continue }
            defaults.set(value, forKey: key)
            applied += 1
        }
        return applied
    }

    private func waitForFirstDownload() {
        firstDownload?.cancel()
        firstDownload = Task { [weak self] in
            try? await Task.sleep(for: Self.firstDownloadWait)
            guard !Task.isCancelled else { return }
            self?.finishFirstDownload(after: "wait")
        }
    }

    /// iCloud has sent its settings, or the wait is over: what's only on this device goes up.
    private func finishFirstDownload(after reason: String) {
        firstDownload?.cancel()
        firstDownload = nil
        guard isSyncing, !defaults.bool(forKey: Self.downloadedKey) else { return }
        defaults.set(true, forKey: Self.downloadedKey)
        let uploaded = uploadOnlyHere()
        lastSynced = snapshot()
        cloud.synchronize()
        Trace.log(.icloud, "Settings sync caught up", ["after": reason, "uploaded": uploaded])
    }

    private func observe() {
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.localSettingsChanged() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: cloud,
            queue: .main
        ) { [weak self] notification in
            let keys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            MainActor.assumeIsolated {
                if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
                    Logger.settings.error("Settings are over iCloud's size limit")
                }
                self?.cloudChanged(keys, reason: reason)
            }
        })
    }

    /// The synced values as property-list objects, which both stores take as they are.
    private func snapshot() -> [String: NSObject] {
        var values: [String: NSObject] = [:]
        for key in Self.keys {
            if let value = defaults.object(forKey: key) as? NSObject {
                values[key] = value
            }
        }
        return values
    }

    /// Sends the settings changed on this iPhone to iCloud.
    func localSettingsChanged() {
        guard isSyncing, !isApplyingCloud else { return }
        let current = snapshot()
        for key in Self.keys where current[key] != lastSynced[key] {
            if let value = current[key] {
                cloud.set(value, forKey: Self.cloudKey(key))
            } else {
                cloud.removeObject(forKey: Self.cloudKey(key))
            }
        }
        lastSynced = current
    }

    /// Brings in settings another device changed. Nil keys means anything could have changed. `reason` is
    /// iCloud's, such as its first download to this device.
    func cloudChanged(_ cloudKeys: [String]?, reason: Int? = nil) {
        guard isSyncing else { return }
        if reason == NSUbiquitousKeyValueStoreAccountChange {
            // Another account's settings: this device waits for them as it did the first time.
            defaults.set(false, forKey: Self.downloadedKey)
        }
        let keys = cloudKeys.map { changed in
            Self.keys.filter { changed.contains(Self.cloudKey($0)) }
        } ?? Self.keys
        var applied = 0
        if !keys.isEmpty {
            let before = snapshot()
            applied = applyFromCloud(keys)
            lastSynced = snapshot()
            catchUpHealth(from: before)
            Logger.settings.debug("Applied settings from iCloud")
        }
        // Key names and counts only, never the values, which include weight.
        Trace.log(.icloud, "Settings changed in iCloud", ["reason": Self.name(ofReason: reason), "keys": keys.count, "applied": applied])
        switch reason {
        case NSUbiquitousKeyValueStoreInitialSyncChange, NSUbiquitousKeyValueStoreServerChange, NSUbiquitousKeyValueStoreAccountChange:
            finishFirstDownload(after: Self.name(ofReason: reason))
        default:
            break
        }
    }

    private static func name(ofReason reason: Int?) -> String {
        switch reason {
        case NSUbiquitousKeyValueStoreServerChange: "server"
        case NSUbiquitousKeyValueStoreInitialSyncChange: "firstDownload"
        case NSUbiquitousKeyValueStoreQuotaViolationChange: "overLimit"
        case NSUbiquitousKeyValueStoreAccountChange: "account"
        case nil: "none"
        default: "other"
        }
    }

    /// A Health switch turned on elsewhere still needs this device's permission, or it would
    /// look on and do nothing.
    private func catchUpHealth(from before: [String: NSObject]) {
        func turnedOn(_ key: String) -> Bool {
            defaults.bool(forKey: key) && !((before[key] as? Bool) ?? false)
        }
        let heartRate = turnedOn(HeartRateMonitor.storageKey)
        let savesToHealth = turnedOn(HealthSync.enabledKey)
        guard heartRate || savesToHealth else { return }
        Task { await requestHealthAccess(heartRate, savesToHealth) }
    }

    /// Health shows its sheet only for what this device hasn't been asked yet.
    static func askForHealth(heartRate: Bool, savesToHealth: Bool) async {
        if heartRate {
            _ = await HeartRateMonitor.requestAccess()
        }
        if savesToHealth {
            _ = await HealthSync.shared.requestAccess()
        }
    }
}
