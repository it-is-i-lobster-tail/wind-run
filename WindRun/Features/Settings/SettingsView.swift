//
//  SettingsView.swift
//  Wind Run
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Distance", selection: $unit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.name).tag(unit)
                        }
                    }
                }

                HealthSyncSection()
                HeartRateSection()

                Section {
                    Label("Runs and routes stay on this device.", systemImage: "lock")
                    Label("No account, no tracking, no analytics.", systemImage: "eye.slash")
                } header: {
                    Text("Privacy")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview("Settings") {
    SettingsView()
}
