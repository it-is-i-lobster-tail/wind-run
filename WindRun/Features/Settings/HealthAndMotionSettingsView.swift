//
//  HealthAndMotionSettingsView.swift
//  Wind Run
//
//  What Wind Run measures and where runs go: Apple Health, heart rate, steps and auto-pause.
//

import SwiftUI

struct HealthAndMotionSettingsView: View {
    var body: some View {
        Form {
            HealthSyncSection()
            HeartRateSection()
            MotionSection()
        }
        .navigationTitle("Health & Motion")
        .navigationBarTitleDisplayMode(.inline)
        .traceScreen("Health & Motion")
    }
}

#Preview("Health & Motion") {
    NavigationStack { HealthAndMotionSettingsView() }
}
