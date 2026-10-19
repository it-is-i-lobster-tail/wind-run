//
//  WatchSettingsView.swift
//  Wind Run Watch
//

import SwiftUI

/// The watch keeps its own settings, since it records runs without the phone.
struct WatchSettingsView: View {
    var body: some View {
        List {
            HealthSyncSection()
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        WatchSettingsView()
    }
}
