//
//  WindRunSchema.swift
//  Wind Run
//

import Foundation
import OSLog
import SwiftData

enum WindRunSchema {
    /// Every model type. A new `@Model` must be added here.
    static let models: [any PersistentModel.Type] = [
        Run.self,
        RouteSample.self,
        RunPause.self,
        IntervalPlan.self,
        IntervalBlock.self,
        IntervalStep.self,
        CoachPlan.self,
        CoachWeek.self,
        CoachWorkout.self,
    ]

    static let schema = Schema(models)

    /// The runner's private iCloud database. Only they can read it.
    static let cloudKitContainerID = "iCloud.com.stanleycloud.WindRun"

    /// Runs live on this device, and in the runner's private iCloud only when they turn on
    /// iCloud sync. An in-memory store never syncs.
    static func makeContainer(inMemory: Bool = false, syncsWithICloud: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: syncsWithICloud && !inMemory ? .private(cloudKitContainerID) : .none
        )
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            Logger.persistence.fault("Couldn't open the store: \(error.localizedDescription)")
            fatalError("Couldn't open the Wind Run store: \(error)")
        }
    }

    /// Previews and unit tests never touch the real store.
    static var runsInMemory: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || environment["XCTestConfigurationFilePath"] != nil
    }
}

extension ModelContext {
    /// Saves, logging instead of throwing, for places that can't show an error.
    func saveQuietly() {
        do {
            try save()
        } catch {
            Logger.persistence.error("Save failed: \(error.localizedDescription)")
        }
    }
}
