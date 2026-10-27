//
//  WindRunApp.swift
//  Wind Run
//

import SwiftData
import SwiftUI

@main
struct WindRunApp: App {
    #if DEBUG
    static let store: WindRunStore = {
        guard WindRunSeed.isRequested else { return WindRunStore(inMemory: WindRunSchema.runsInMemory) }
        let store = WindRunStore(inMemory: true)
        WindRunSeed.addSampleRuns(to: store.container.mainContext)
        return store
    }()
    #else
    static let store = WindRunStore(inMemory: WindRunSchema.runsInMemory)
    #endif

    init() {
        // A coached run done on the watch joins the runs here, linked to its session, for the coach.
        SettingsSync.shared.runReceived = { data in
            WatchRunRecord.decode(data)?.insert(into: Self.store.container.mainContext)
        }
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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.system

    var body: some View {
        WindRunRootView()
            .modelContainer(store.container)
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                AppOpens.record()
                appearance.apply()
            }
            // Also follows a pick made on another iPhone, which arrives through iCloud.
            .onChange(of: appearance, initial: true) { _, appearance in
                appearance.apply()
            }
    }
}
