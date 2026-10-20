//
//  WindRunWatchApp.swift
//  Wind Run Watch
//

import SwiftData
import SwiftUI

@main
struct WindRunWatchApp: App {
    // The watch keeps its own local store for now. Syncing with the phone comes later.
    static let container = WindRunSchema.makeContainer(inMemory: WindRunSchema.runsInMemory)

    init() {
        SettingsSync.shared.start()
        // A run can't outlive the app, so a run still going is left over from one it was closed in.
        RunRecovery.finishLeftoverRuns(in: Self.container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .modelContainer(Self.container)
        }
    }
}
