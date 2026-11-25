//
//  WindRunStore.swift
//  Wind Run
//
//  Owns the iPhone app's model container and turns iCloud sync on or off, for runs and settings.
//

import CoreData
import Foundation
import Observation
import OSLog
import SwiftData

/// Why iCloud sync couldn't be switched. Nothing changed when one is thrown.
enum ICloudSyncError: Error {
    /// This iPhone isn't signed in to iCloud.
    case signedOut
    /// iCloud couldn't be reached, so the copy there wasn't deleted.
    case unreachable
    /// The store couldn't be opened the new way, so it carries on as it was.
    case storeUnavailable
}

@Observable
final class WindRunStore {
    /// Off until the runner turns it on.
    static let iCloudSyncKey = "settings.iCloudSync"

    /// Replaced when iCloud sync is switched, so views must rebuild from it.
    private(set) var container: ModelContainer
    private(set) var syncsWithICloud: Bool
    /// Why this iPhone's store couldn't be opened at launch, or nil when it opened. While it's set the app
    /// says so instead of showing an empty store that wouldn't be kept.
    private(set) var openFailure: (any Error)?

    private let inMemory: Bool
    private let iCloud: any ICloudCopy
    private let defaults: UserDefaults
    /// The runner's settings, which go to iCloud and come back with the runs.
    let settings: CloudSettings

    /// An in-memory store never syncs, whatever the setting says.
    init(
        inMemory: Bool = false,
        iCloud: (any ICloudCopy)? = nil,
        defaults: UserDefaults = .standard,
        settings: CloudSettings? = nil
    ) {
        self.inMemory = inMemory
        self.iCloud = iCloud ?? Self.defaultICloud(inMemory: inMemory)
        self.defaults = defaults
        self.settings = settings ?? Self.defaultSettings(inMemory: inMemory, defaults: defaults)
        let syncs = defaults.bool(forKey: Self.iCloudSyncKey)
        #if DEBUG
        if !inMemory, CloudKitSchemaSetup.isRequested {
            CloudKitSchemaSetup.run()
        }
        #endif
        let opened = Self.open(inMemory: inMemory, syncingWithICloud: syncs)
        syncsWithICloud = opened.syncs
        container = opened.container
        openFailure = opened.failure
        if opened.syncs {
            self.settings.startSyncing()
        }
        logSyncErrors()
    }

    /// The store at launch: with iCloud as set, or without it when iCloud turns it down, or when even that
    /// fails, an empty one in memory with the reason.
    private static func open(inMemory: Bool, syncingWithICloud syncs: Bool) -> (container: ModelContainer, syncs: Bool, failure: (any Error)?) {
        do {
            return (try WindRunSchema.openContainer(inMemory: inMemory, syncsWithICloud: syncs), syncs, nil)
        } catch {
            // First, so a shared trace says why.
            Trace.error("Store open failed", error)
            Logger.persistence.fault("Couldn't open the store: \(error)")
            if syncs, let local = try? WindRunSchema.openContainer(inMemory: inMemory, syncsWithICloud: false) {
                // The runs are still here, without sync for now. The setting stays, so the next launch tries again.
                Logger.persistence.error("Opened the store without iCloud sync")
                return (local, false, nil)
            }
            return (WindRunSchema.makeContainer(inMemory: true), false, error)
        }
    }

    /// Tries the store again after it couldn't be opened at launch.
    func retryOpening() {
        guard openFailure != nil else { return }
        let opened = Self.open(inMemory: inMemory, syncingWithICloud: defaults.bool(forKey: Self.iCloudSyncKey))
        container = opened.container
        syncsWithICloud = opened.syncs
        openFailure = opened.failure
        Trace.log(.data, "Store opened again", ["ok": opened.failure == nil])
        if opened.failure == nil, opened.syncs {
            settings.startSyncing()
        }
    }

    /// Whether this iPhone is signed in to iCloud, so sync can actually run.
    func iCloudAccountAvailable() async -> Bool {
        await iCloud.accountIsAvailable()
    }

    /// Where this iPhone stands with iCloud, for saying what's wrong.
    func iCloudAccount() async -> ICloudAccount {
        await iCloud.account()
    }

    /// Starts syncing. Needs an iCloud account, so "on" always means there's somewhere to sync to.
    func turnOnICloudSync() async throws {
        guard await iCloud.accountIsAvailable() else { throw ICloudSyncError.signedOut }
        guard useContainer(syncingWithICloud: true) else { throw ICloudSyncError.storeUnavailable }
        defaults.set(true, forKey: Self.iCloudSyncKey)
        settings.startSyncing()
        Logger.persistence.info("iCloud sync turned on")
    }

    /// Stops syncing, then deletes the copy in iCloud. Data on this iPhone is kept.
    /// If the copy can't be deleted, sync carries on and the error is thrown.
    func turnOffICloudSync() async throws {
        guard await iCloud.accountIsAvailable() else { throw ICloudSyncError.signedOut }

        // A syncing store that's still open would upload everything again once it saw the copy gone,
        // so close it first. The setting is saved only once the copy is gone.
        try await stopSyncing()
        do {
            try await iCloud.delete()
        } catch {
            Logger.persistence.error("Couldn't delete the iCloud copy: \(error)")
            if !useContainer(syncingWithICloud: true) {
                // Sync can't come back on, so it stays off, with the copy left in iCloud.
                defaults.set(false, forKey: Self.iCloudSyncKey)
                settings.stopSyncing(deletingCopy: false)
            }
            throw ICloudSyncError.unreachable
        }
        defaults.set(false, forKey: Self.iCloudSyncKey)
        settings.stopSyncing(deletingCopy: true)
        Logger.persistence.info("iCloud sync turned off and the iCloud copy deleted")
    }

    /// For a runner who is signed out of iCloud and agrees to leave the copy there.
    func turnOffICloudSyncKeepingCopy() {
        guard useContainer(syncingWithICloud: false) else { return }
        defaults.set(false, forKey: Self.iCloudSyncKey)
        settings.stopSyncing(deletingCopy: false)
        Logger.persistence.info("iCloud sync turned off; the iCloud copy was kept")
    }

    /// Moves to a container that syncs or doesn't, saving what's waiting first. Keeps the one it has, and
    /// says no, when the new one can't be opened.
    @discardableResult
    private func useContainer(syncingWithICloud syncs: Bool) -> Bool {
        // Changes not autosaved yet would go with the old container.
        container.mainContext.saveQuietly()
        do {
            container = try WindRunSchema.openContainer(inMemory: inMemory, syncsWithICloud: syncs)
        } catch {
            Trace.error("Store switch failed", error)
            Logger.persistence.error("Couldn't open the store with iCloud sync \(syncs ? "on" : "off", privacy: .public): \(error)")
            return false
        }
        syncsWithICloud = syncs
        return true
    }

    /// Swaps in a store that doesn't sync and waits for the syncing one to close.
    private func stopSyncing() async throws {
        weak let syncingContainer = container
        guard useContainer(syncingWithICloud: false) else { throw ICloudSyncError.storeUnavailable }
        // The screens let go of the old container once they rebuild from the new one.
        for _ in 0..<30 where syncingContainer != nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if syncingContainer != nil {
            Logger.persistence.warning("The syncing store was still open when its iCloud copy was deleted")
        }
    }

    /// iCloud fails quietly, so log every failed sync to make it show up in Console.
    private func logSyncErrors() {
        Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification) {
                guard
                    let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                    event.endDate != nil
                else { continue }
                if event.type == .import, event.succeeded, let self, self.syncsWithICloud {
                    do {
                        try WorkoutMigration.migrateHikes(in: self.container.mainContext, defaults: self.defaults)
                    } catch {
                        Trace.error("Downloaded hike migration", error)
                    }
                }
                guard let error = event.error else { continue }
                Logger.persistence.error("iCloud \(Self.name(of: event.type), privacy: .public) failed: \(error, privacy: .public)")
            }
        }
    }

    private static func name(of eventType: NSPersistentCloudKitContainer.EventType) -> String {
        switch eventType {
        case .setup: "setup"
        case .import: "download"
        case .export: "upload"
        @unknown default: "sync"
        }
    }

    /// Settings in the real iCloud, except in previews and tests.
    private static func defaultSettings(inMemory: Bool, defaults: UserDefaults) -> CloudSettings {
        inMemory
            ? CloudSettings(defaults: defaults, cloud: InMemoryKeyValueStore(), askForHealth: { _, _ in })
            : CloudSettings(defaults: defaults)
    }

    /// The real iCloud, except in previews and tests, or when a debug build asks for a stand-in.
    private static func defaultICloud(inMemory: Bool) -> any ICloudCopy {
        #if DEBUG
        if let mode = FakeICloud.requestedMode {
            return FakeICloud(mode: mode)
        }
        if inMemory {
            return FakeICloud(mode: .signedOut)
        }
        #endif
        return CloudKitCopy()
    }
}
