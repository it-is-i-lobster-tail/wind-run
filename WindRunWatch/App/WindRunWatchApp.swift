//
//  WindRunWatchApp.swift
//  Wind Run Watch
//

import SwiftData
import SwiftUI
import WatchKit

@main
struct WindRunWatchApp: App {
    // The watch keeps its own local store for now. Syncing with the phone comes later.
    static let container = WindRunSchema.makeContainer(inMemory: WindRunSchema.runsInMemory)
    /// Hears when watchOS opens the app again to carry on a run's workout session.
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate

    init() {
        SettingsSync.shared.start()
        // A run still going is left over from an app that was closed in it. The one this watch was recording
        // waits a moment for watchOS to hand back its workout session, so it can carry on; the home screen
        // finishes it if none comes.
        RunRecovery.finishLeftoverRuns(in: Self.container.mainContext, sparingRecording: true)
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let demo = WatchRunScreenDemo.requested {
                WatchRunScreenDemo(kind: demo)
            } else {
                WatchRootView()
                    .modelContainer(Self.container)
            }
            #else
            WatchRootView()
                .modelContainer(Self.container)
            #endif
        }
    }
}
