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
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .modelContainer(Self.container)
        }
    }
}
