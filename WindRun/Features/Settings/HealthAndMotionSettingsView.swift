//
//  HealthAndMotionSettingsView.swift
//  Wind Run
//
//  What Wind Run measures and where runs go: Apple Health, heart rate, steps and auto-pause, and a
//  checkup for when one of them isn't coming in.
//

import SwiftUI

struct HealthAndMotionSettingsView: View {
    var body: some View {
        Form {
            HealthSyncSection()
            HeartRateSection()
            MotionSection()
            Section {
                SettingsPageLink(page: .sensorCheck)
            } footer: {
                Text("No heart rate, GPS or steps on a run? See what's set up, and test them for a minute.")
            }
        }
        .navigationTitle("Health & Motion")
        .navigationBarTitleDisplayMode(.inline)
        .traceScreen("Health & Motion")
    }
}

#Preview("Health & Motion") {
    NavigationStack { HealthAndMotionSettingsView() }
}
