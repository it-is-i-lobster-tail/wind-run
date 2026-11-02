//
//  WindRunApp.swift
//  Wind Run
//

import SwiftData
import SwiftUI

@main
struct WindRunApp: App {
    static let store = WindRunStore(inMemory: WindRunSchema.runsInMemory)

    init() {
        SettingsSync.shared.start()
        // A run can't outlive the app, so a run still going, and its heart rate Live Activity,
        // are left over from a run the app was closed in the middle of.
        RunRecovery.finishLeftoverRuns(in: Self.store.container.mainContext)
        HeartRateActivityController.endLeftoverActivities()
    }

    var body: some Scene {
        WindowGroup {
            WindRunAppContent()
                .environment(Self.store)
        }
    }
}

/// The app's screens on the store's current container, which changes with iCloud sync.
struct WindRunAppContent: View {
    @Environment(WindRunStore.self) private var store

    var body: some View {
        WindRunRootView()
            .modelContainer(store.container)
    }
}
