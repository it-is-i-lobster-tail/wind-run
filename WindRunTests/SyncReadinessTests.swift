//
//  SyncReadinessTests.swift
//  Wind Run Tests
//

import CoreData
import Foundation
import SwiftData
import Testing
@testable import WindRun

/// What the models need so iCloud sync can mirror them.
///
/// A store opened with CloudKit starts mirroring on its own queue. Closing it or deleting its file
/// before that setup finishes can crash the test host (a SIGTRAP inside Core Data, seen on CI's
/// iOS 26 simulators), so these tests wait for setup and run one at a time.
@MainActor
@Suite(.serialized)
struct SyncReadinessTests {
    @Test("The schema opens with CloudKit, so every model follows CloudKit's rules")
    func schemaOpensWithCloudKit() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        defer { Self.removeStore(at: url) }
        let configuration = ModelConfiguration(
            schema: WindRunSchema.schema,
            url: url,
            cloudKitDatabase: .private(WindRunSchema.cloudKitContainerID)
        )

        // SwiftData refuses CloudKit when a property lacks a default, a relationship
        // isn't optional, or an inverse is missing.
        let setup = CloudKitSetupWatcher()
        let container = try ModelContainer(for: WindRunSchema.schema, configurations: [configuration])
        await setup.waitUntilFinished()
        withExtendedLifetime(container) {}
    }

    @Test("Switching sync on and off reopens the same store, so runs stay and can still be saved")
    func switchingKeepsRuns() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        defer { Self.removeStore(at: url) }

        func runCount(syncing: Bool, adding: Bool) async throws -> Int {
            let configuration = ModelConfiguration(
                schema: WindRunSchema.schema,
                url: url,
                cloudKitDatabase: syncing ? .private(WindRunSchema.cloudKitContainerID) : .none
            )
            let setup = CloudKitSetupWatcher()
            let container = try ModelContainer(for: WindRunSchema.schema, configurations: [configuration])
            if syncing {
                await setup.waitUntilFinished()
            }
            let context = container.mainContext
            if adding {
                context.insert(Run())
                // A store opened without the history iCloud left behind would be read-only and fail here.
                try context.save()
            }
            return try context.fetchCount(FetchDescriptor<Run>())
        }

        #expect(try await runCount(syncing: false, adding: true) == 1)
        #expect(try await runCount(syncing: true, adding: true) == 2)
        #expect(try await runCount(syncing: false, adding: true) == 3)
        #expect(try await runCount(syncing: true, adding: false) == 3)
    }

    /// The store and the files SQLite keeps beside it.
    private static func removeStore(at url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(filePath: url.path(percentEncoded: false) + suffix))
        }
    }
}

/// Waits for CloudKit mirroring to finish setting up a store, whether it reached iCloud or not.
/// Made before the container, so the setup event can't be missed.
@MainActor
private final class CloudKitSetupWatcher {
    private var finished = false
    private var observer: (any NSObjectProtocol)?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
            guard let event, event.type == .setup, event.endDate != nil else { return }
            MainActor.assumeIsolated { self?.finished = true }
        }
    }

    /// Simulators without an iCloud account still finish setup, with an error. It can take seconds while other
    /// tests run, so the timeout is only a backstop.
    func waitUntilFinished(timeout: Duration = .seconds(30)) async {
        let deadline = ContinuousClock.now + timeout
        while !finished, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        observer = nil
    }
}
