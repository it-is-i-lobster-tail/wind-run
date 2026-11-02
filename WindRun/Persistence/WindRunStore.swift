//
//  WindRunStore.swift
//  Wind Run
//
//  Owns the iPhone app's model container and turns iCloud sync on or off.
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
}

@Observable
final class WindRunStore {
    /// Off until the runner turns it on.
    static let iCloudSyncKey = "settings.iCloudSync"

    /// Replaced when iCloud sync is switched, so views must rebuild from it.
    private(set) var container: ModelContainer
    private(set) var syncsWithICloud: Bool

    private let inMemory: Bool
    private let iCloud: any ICloudCopy
    private let defaults: UserDefaults

    /// An in-memory store never syncs, whatever the setting says.
    init(inMemory: Bool = false, iCloud: (any ICloudCopy)? = nil, defaults: UserDefaults = .standard) {
        self.inMemory = inMemory
        self.iCloud = iCloud ?? Self.defaultICloud(inMemory: inMemory)
        self.defaults = defaults
        let syncs = defaults.bool(forKey: Self.iCloudSyncKey)
        #if DEBUG
        if !inMemory, CloudKitSchemaSetup.isRequested {
            CloudKitSchemaSetup.run()
        }
        #endif
        syncsWithICloud = syncs
        container = WindRunSchema.makeContainer(inMemory: inMemory, syncsWithICloud: syncs)
        logSyncErrors()
    }

    /// Whether this iPhone is signed in to iCloud, so sync can actually run.
    func iCloudAccountAvailable() async -> Bool {
        await iCloud.accountIsAvailable()
    }

    /// Starts syncing. Needs an iCloud account, so "on" always means there's somewhere to sync to.
    func turnOnICloudSync() async throws {
        guard await iCloud.accountIsAvailable() else { throw ICloudSyncError.signedOut }
        useContainer(syncingWithICloud: true)
        defaults.set(true, forKey: Self.iCloudSyncKey)
        Logger.persistence.info("iCloud sync turned on")
    }

    /// Stops syncing, then deletes the copy in iCloud. Data on this iPhone is kept.
    /// If the copy can't be deleted, sync carries on and the error is thrown.
    func turnOffICloudSync() async throws {
        guard await iCloud.accountIsAvailable() else { throw ICloudSyncError.signedOut }

        // A syncing store that's still open would upload everything again once it saw the copy gone,
        // so close it first. The setting is saved only once the copy is gone.
        await stopSyncing()
        do {
            try await iCloud.delete()
        } catch {
            Logger.persistence.error("Couldn't delete the iCloud copy: \(error.localizedDescription)")
            useContainer(syncingWithICloud: true)
            throw ICloudSyncError.unreachable
        }
        defaults.set(false, forKey: Self.iCloudSyncKey)
        Logger.persistence.info("iCloud sync turned off and the iCloud copy deleted")
    }

    /// For a runner who is signed out of iCloud and agrees to leave the copy there.
    func turnOffICloudSyncKeepingCopy() {
        useContainer(syncingWithICloud: false)
        defaults.set(false, forKey: Self.iCloudSyncKey)
        Logger.persistence.info("iCloud sync turned off; the iCloud copy was kept")
    }

    private func useContainer(syncingWithICloud syncs: Bool) {
        syncsWithICloud = syncs
        container = WindRunSchema.makeContainer(inMemory: inMemory, syncsWithICloud: syncs)
    }

    /// Swaps in a store that doesn't sync and waits for the syncing one to close.
    private func stopSyncing() async {
        weak var syncingContainer = container
        useContainer(syncingWithICloud: false)
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
        Task {
            for await notification in NotificationCenter.default.notifications(named: NSPersistentCloudKitContainer.eventChangedNotification) {
                guard
                    let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                    event.endDate != nil,
                    let error = event.error
                else { continue }
                Logger.persistence.error("iCloud \(Self.name(of: event.type), privacy: .public) failed: \(String(describing: error), privacy: .public)")
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
