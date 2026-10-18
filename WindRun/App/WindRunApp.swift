//
//  WindRunApp.swift
//  Wind Run
//

import SwiftData
import SwiftUI

@main
struct WindRunApp: App {
    static let container = WindRunSchema.makeContainer(inMemory: WindRunSchema.runsInMemory)

    var body: some Scene {
        WindowGroup {
            WindRunRootView()
                .modelContainer(Self.container)
        }
    }
}
