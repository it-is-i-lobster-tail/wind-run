//
//  CloudKitSchemaSetup.swift
//  Wind Run
//
//  Writes every model field to the CloudKit Development schema.
//
//  CloudKit only adds a field to Development when a debug build uploads a value for it,
//  so new or rarely set fields can be missing, and TestFlight and App Store builds then
//  fail to upload. After changing a model:
//  1. Run the app from Xcode with the `-initCloudKitSchema` launch argument, signed in to iCloud.
//  2. In the CloudKit Console, check Development, then Deploy Schema Changes to Production.
//

#if DEBUG
import CoreData
import Foundation
import OSLog
import SwiftData

enum CloudKitSchemaSetup {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-initCloudKitSchema")
    }

    /// Uses a throwaway store, so the runner's data is never touched.
    static func run() {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: WindRunSchema.models) else {
            Logger.persistence.error("Could not build the model for the CloudKit schema")
            return
        }

        let storeURL = URL.temporaryDirectory.appending(path: "CloudKitSchemaSetup.store")
        let description = NSPersistentStoreDescription(url: storeURL)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: WindRunSchema.cloudKitContainerID
        )
        description.shouldAddStoreAsynchronously = false

        let container = NSPersistentCloudKitContainer(name: "CloudKitSchemaSetup", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }

        do {
            if let loadError { throw loadError }
            try container.initializeCloudKitSchema()
            Logger.persistence.info("Wrote every field to the CloudKit Development schema")
        } catch {
            Logger.persistence.error("Could not write the CloudKit schema: \(String(describing: error), privacy: .public)")
        }

        let coordinator = container.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try? coordinator.remove(store)
        }
        try? coordinator.destroyPersistentStore(at: storeURL, type: .sqlite)
    }
}
#endif
