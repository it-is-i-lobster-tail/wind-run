//
//  WindRunApp.swift
//  Wind Run
//

import SwiftData
import SwiftUI

@main
struct WindRunApp: App {
    static let store = WindRunStore(inMemory: WindRunSchema.runsInMemory)

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
