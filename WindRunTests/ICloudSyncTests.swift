//
//  ICloudSyncTests.swift
//  Wind Run Tests
//

import CloudKit
import Foundation
import SwiftData
import Testing
@testable import WindRun

/// Turning iCloud sync on and off, with a stand-in for iCloud.
@MainActor
struct ICloudSyncTests {
    // Each test gets its own defaults, so the app's real setting is never touched.
    private let suiteName = "ICloudSyncTests-\(UUID().uuidString)"
    private var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    private func makeStore(_ iCloud: TestICloud) -> WindRunStore {
        WindRunStore(inMemory: true, iCloud: iCloud, defaults: defaults)
    }

    @Test("Sync is off until the runner turns it on")
    func offByDefault() {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeStore(TestICloud())
        #expect(!store.syncsWithICloud)
    }

    @Test("Turning sync on swaps in a syncing store and remembers it")
    func turnOn() async throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeStore(TestICloud())
        let containerBefore = ObjectIdentifier(store.container)

        try await store.turnOnICloudSync()

        #expect(store.syncsWithICloud)
        #expect(ObjectIdentifier(store.container) != containerBefore)
        #expect(makeStore(TestICloud()).syncsWithICloud, "A relaunch should keep syncing")
    }

    @Test("Sync can't be turned on while signed out of iCloud")
    func turnOnNeedsAnAccount() async {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeStore(TestICloud(signedIn: false))

        await #expect(throws: ICloudSyncError.signedOut) {
            try await store.turnOnICloudSync()
        }
        #expect(!store.syncsWithICloud)
    }

    @Test("Turning sync off deletes the iCloud copy and remembers it")
    func turnOffDeletesCopy() async throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let iCloud = TestICloud()
        let store = makeStore(iCloud)
        try await store.turnOnICloudSync()
        let containerBefore = ObjectIdentifier(store.container)

        try await store.turnOffICloudSync()

        #expect(iCloud.deletes == 1)
        #expect(!store.syncsWithICloud)
        #expect(ObjectIdentifier(store.container) != containerBefore)
        #expect(!makeStore(TestICloud()).syncsWithICloud, "A relaunch should stay off")
    }

    @Test("The syncing store closes before the iCloud copy is deleted")
    func syncingStoreClosesFirst() async throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let iCloud = TestICloud()
        let store = makeStore(iCloud)
        try await store.turnOnICloudSync()
        weak var syncingContainer = store.container
        iCloud.beforeDelete = {
            // Otherwise it could upload everything again once it saw the copy gone.
            #expect(syncingContainer == nil)
        }

        try await store.turnOffICloudSync()

        #expect(iCloud.deletes == 1)
    }

    @Test("If iCloud can't be reached, sync stays on and nothing is deleted")
    func turnOffWhenUnreachable() async throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let iCloud = TestICloud()
        let store = makeStore(iCloud)
        try await store.turnOnICloudSync()
        iCloud.deleteError = CKError(.networkUnavailable)

        await #expect(throws: ICloudSyncError.unreachable) {
            try await store.turnOffICloudSync()
        }

        #expect(store.syncsWithICloud)
        #expect(makeStore(TestICloud()).syncsWithICloud, "The saved setting should still be on")
    }

    @Test("Signed out, turning sync off deletes nothing until the runner agrees to keep the copy")
    func turnOffWhenSignedOut() async throws {
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let iCloud = TestICloud()
        let store = makeStore(iCloud)
        try await store.turnOnICloudSync()
        iCloud.signedIn = false

        await #expect(throws: ICloudSyncError.signedOut) {
            try await store.turnOffICloudSync()
        }
        #expect(store.syncsWithICloud)

        store.turnOffICloudSyncKeepingCopy()

        #expect(!store.syncsWithICloud)
        #expect(iCloud.deletes == 0)
        #expect(!makeStore(TestICloud()).syncsWithICloud)
    }

    @Test("A missing iCloud copy counts as already deleted")
    func missingCopyIsAlreadyDeleted() {
        #expect(CloudKitCopy.meansNothingToDelete(CKError(.zoneNotFound)))
        #expect(CloudKitCopy.meansNothingToDelete(CKError(.userDeletedZone)))
        #expect(!CloudKitCopy.meansNothingToDelete(CKError(.networkUnavailable)))
        #expect(!CloudKitCopy.meansNothingToDelete(CKError(.notAuthenticated)))
    }

    @Test("Previews and tests never reach iCloud")
    func inMemoryStoreIsSignedOut() async {
        let store = WindRunStore(inMemory: true)
        #expect(await !store.iCloudAccountAvailable())
    }
}

/// Stands in for iCloud and counts what was asked of it.
@MainActor
private final class TestICloud: ICloudCopy {
    var signedIn: Bool
    var deleteError: Error?
    var beforeDelete: () -> Void = {}
    private(set) var deletes = 0

    init(signedIn: Bool = true) {
        self.signedIn = signedIn
    }

    func accountIsAvailable() async -> Bool {
        signedIn
    }

    func delete() async throws {
        beforeDelete()
        if let deleteError { throw deleteError }
        deletes += 1
    }
}
