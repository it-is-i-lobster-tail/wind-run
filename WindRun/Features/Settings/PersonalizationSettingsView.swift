//
//  PersonalizationSettingsView.swift
//  Wind Run
//
//  How Wind Run fits you: units, your weight for calories, and what you hear and feel while you run.
//

import SwiftUI

struct PersonalizationSettingsView: View {
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    @AppStorage(WorkoutSearchSession.toolSearchKey) private var toolSearch = false

    @AppStorage(WorkoutSearchFeedback.enabledKey) private var feedbackEnabled = false
    @State private var confirmClear = false
    @State private var clearFailed = false

    var body: some View {
        Form {
            Section {
                Picker("Units", selection: $unit) {
                    ForEach(DistanceUnit.allCases) { unit in
                        Text("\(unit.systemName) (\(unit.symbol))").tag(unit)
                    }
                }
            } header: {
                Text("Units")
            } footer: {
                Text("Distance, pace, height and weight all follow this.")
            }

            Section {
                BodyWeightRow(unit: unit)
            } header: {
                Text("Body")
            } footer: {
                Text("Used to work out the calories each workout burns. A newer weight in Apple Health replaces it. It syncs with your other settings when iCloud Sync is on.")
            }

            Section {
                Toggle("Use Apple Intelligence for search", isOn: $toolSearch)
            } header: {
                Text("Workout history")
            } footer: {
                Text("On supported devices, submitting a search can use the on-device model. Standard search is available on every device.")
            }

            Section {
                Toggle("Label empty searches", isOn: $feedbackEnabled)
                Button("Delete saved search feedback", role: .destructive) { confirmClear = true }
                    .confirmationDialog("Delete saved search feedback?", isPresented: $confirmClear) {
                        Button("Delete feedback", role: .destructive) {
                            do { try WorkoutSearchFeedback.clear() } catch { clearFailed = true }
                        }
                    }
                    .alert("Could not delete feedback", isPresented: $clearFailed) { Button("OK") {} }
            } header: {
                Text("Beta search feedback")
            } footer: {
                Text("When you label a search, its wording, date and your answer are saved on this device. Open Search history to compare the results.")
            }

            PaceCalloutSection()
            HapticsSection()
        }
        .navigationTitle("Personalization")
        .navigationBarTitleDisplayMode(.inline)
        .traceScreen("Personalization")
    }
}

/// The runner's weight in their units, for calories. Clearing it turns calories off.
private struct BodyWeightRow: View {
    let unit: DistanceUnit
    @AppStorage(BodyWeight.storageKey) private var kilograms: Double = 0

    var body: some View {
        OptionalNumberField(title: "Weight (\(unit.weightSymbol))", value: Binding(
            get: {
                guard BodyWeight.range.contains(kilograms) else { return nil }
                return BodyWeight.displayed(kilograms, unit: unit)
            },
            set: { value in
                guard let value else {
                    kilograms = 0
                    return
                }
                let typed = BodyWeight.kilograms(fromDisplayed: value, unit: unit)
                // Part way through typing, such as the 7 of 72, isn't a weight yet.
                if BodyWeight.range.contains(typed) { BodyWeight.save(typed) }
            }
        ))
        // The field reads its value when it appears, so it starts again when the units change.
        .id(unit)
    }
}

#Preview("Personalization") {
    NavigationStack { PersonalizationSettingsView() }
}
