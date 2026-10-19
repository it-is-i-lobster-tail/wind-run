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
        HeartRateSample.self,
        IntervalPlan.self,
        IntervalBlock.self,
        IntervalStep.self,
        CoachPlan.self,
        CoachWeek.self,
        CoachWorkout.self,
    ]

    static let schema = Schema(models)

    /// Runs live on this device only: no iCloud, no accounts, no analytics.
    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
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
