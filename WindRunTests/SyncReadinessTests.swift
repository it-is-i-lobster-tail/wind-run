//
//  SyncReadinessTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// What the models need so iCloud sync can mirror them.
@MainActor
struct SyncReadinessTests {
    @Test("The schema opens with CloudKit, so every model follows CloudKit's rules")
    func schemaOpensWithCloudKit() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let configuration = ModelConfiguration(
            schema: WindRunSchema.schema,
            url: url,
            cloudKitDatabase: .private(WindRunSchema.cloudKitContainerID)
        )

        // SwiftData refuses CloudKit when a property lacks a default, a relationship
        // isn't optional, or an inverse is missing.
        _ = try ModelContainer(for: WindRunSchema.schema, configurations: [configuration])
    }

    @Test("Switching sync on and off reopens the same store, so runs stay and can still be saved")
    func switchingKeepsRuns() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }

        func runCount(syncing: Bool, adding: Bool) throws -> Int {
            let configuration = ModelConfiguration(
                schema: WindRunSchema.schema,
                url: url,
                cloudKitDatabase: syncing ? .private(WindRunSchema.cloudKitContainerID) : .none
            )
            let container = try ModelContainer(for: WindRunSchema.schema, configurations: [configuration])
            let context = container.mainContext
            if adding {
                context.insert(Run())
                // A store opened without the history iCloud left behind would be read-only and fail here.
                try context.save()
            }
            return try context.fetchCount(FetchDescriptor<Run>())
        }

        #expect(try runCount(syncing: false, adding: true) == 1)
        #expect(try runCount(syncing: true, adding: true) == 2)
        #expect(try runCount(syncing: false, adding: true) == 3)
        #expect(try runCount(syncing: true, adding: false) == 3)
    }
}
