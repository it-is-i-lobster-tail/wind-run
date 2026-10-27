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
}

extension NSUbiquitousKeyValueStore: CloudKeyValueStore {}

/// Settings kept in memory only, for previews and tests.
final class InMemoryKeyValueStore: CloudKeyValueStore {
    private(set) var values: [String: Any] = [:]

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
    /// Every setting kept in iCloud. Two things stay on each device on purpose: which first-open
    /// questions were answered, since permissions like Health's are per device, and the iCloud Sync
    /// switch itself, which a new iPhone needs turned on to get anything back.
    static let keys = [
        DistanceUnit.storageKey,
        Appearance.storageKey,
        PaceCalloutSettings.modeKey,
        PaceCalloutSettings.distanceKey,
        PaceCalloutSettings.secondsKey,
        HealthSync.enabledKey,
        HeartRateMonitor.storageKey,
        MotionMonitor.stepsKey,
        AutoPause.storageKey,
        BodyWeight.storageKey,
        BodyWeight.dateKey,
        CoachHeartRateStore.storageKey,
        CoachRunStart.heatAskedKey,
        CoachPlanView.restingCheckDayKey,
        TermsAcceptance.versionKey,
        TermsAcceptance.dateKey,
    ]
    /// Settings sit under their own prefix in iCloud, so nothing else there is taken for one.
    static let cloudPrefix = "settings."

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
    func startSyncing() {
        guard !isSyncing else { return }
        isSyncing = true
        cloud.synchronize()
        let before = snapshot()
        isApplyingCloud = true
        for key in Self.keys {
            if let value = cloud.object(forKey: Self.cloudPrefix + key) {
                defaults.set(value, forKey: key)
            } else if let value = defaults.object(forKey: key) {
                cloud.set(value, forKey: Self.cloudPrefix + key)
            }
        }
        isApplyingCloud = false
        lastSynced = snapshot()
        catchUpHealth(from: before)
        observe()
        cloud.synchronize()
        Logger.settings.info("Settings sync with iCloud")
    }

    /// Stops keeping settings in iCloud. The settings on this iPhone stay as they are.
    func stopSyncing(deletingCopy: Bool) {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers = []
        isSyncing = false
        guard deletingCopy else { return }
        for key in Self.keys {
            cloud.removeObject(forKey: Self.cloudPrefix + key)
        }
        cloud.synchronize()
        Logger.settings.info("Deleted the settings in iCloud")
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
                self?.cloudChanged(keys)
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
                cloud.set(value, forKey: Self.cloudPrefix + key)
            } else {
                cloud.removeObject(forKey: Self.cloudPrefix + key)
            }
        }
        lastSynced = current
    }

    /// Brings in settings another device changed. Nil keys means anything could have changed.
    func cloudChanged(_ cloudKeys: [String]?) {
        guard isSyncing else { return }
        let keys = cloudKeys.map { changed in
            Self.keys.filter { changed.contains(Self.cloudPrefix + $0) }
        } ?? Self.keys
        guard !keys.isEmpty else { return }
        let before = snapshot()
        isApplyingCloud = true
        for key in keys {
            // A setting deleted from iCloud, because another device turned sync off, stays here.
            guard let value = cloud.object(forKey: Self.cloudPrefix + key) else { continue }
            defaults.set(value, forKey: key)
        }
        isApplyingCloud = false
        lastSynced = snapshot()
        catchUpHealth(from: before)
        Logger.settings.debug("Applied settings from iCloud")
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
