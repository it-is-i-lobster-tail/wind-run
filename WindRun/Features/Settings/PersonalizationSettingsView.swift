//
//  PersonalizationSettingsView.swift
//  Wind Run
//
//  How Wind Run fits you: units, your weight for calories, and what you hear and feel while you run.
//

import SwiftUI

struct PersonalizationSettingsView: View {
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

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
                Text("Used to work out the calories each run burns. A newer weight in Apple Health replaces it. It syncs with your other settings when iCloud Sync is on.")
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
        OptionalNumberField(title: unit == .miles ? "Weight (lb)" : "Weight (kg)", value: Binding(
            get: {
                guard BodyWeight.range.contains(kilograms) else { return nil }
                return unit == .miles ? kilograms / BodyWeight.kilogramsPerPound : kilograms
            },
            set: { value in
                guard let value else {
                    kilograms = 0
                    return
                }
                let typed = unit == .miles ? value * BodyWeight.kilogramsPerPound : value
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
