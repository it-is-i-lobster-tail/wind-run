//
//  MorningCheckView.swift
//  Wind Run
//

import SwiftUI

/// The optional next-morning check (AD-2) after a long, hard or longest-yet run.
struct MorningCheckView: View {
    @Environment(\.dismiss) private var dismiss

    let actions: CoachActions
    let reportInjury: () -> Void

    @State private var fatigue: Int?
    @State private var soreness: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    scale("Tiredness", value: $fatigue)
                    scale("Soreness", value: $soreness)
                } footer: {
                    Text("1 is much better than normal, 4 is normal, 7 is much worse.")
                }
                Section {
                    Button("Something hurt? Report injury", systemImage: "bandage") {
                        save()
                        reportInjury()
                    }
                }
            }
            .navigationTitle("How do you feel this morning?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                }
            }
        }
    }

    private func scale(_ title: String, value: Binding<Int?>) -> some View {
        Picker(title, selection: value) {
            Text("Skip").tag(Int?.none)
            ForEach(1...7, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
        }
    }

    private func save() {
        let check = MorningCheck(date: .now, fatigue: fatigue, soreness: soreness)
        actions.perform { state, runs, now, calendar in
            CoachEngine.submitMorningCheck(check, state: state, runs: runs, now: now, calendar: calendar)
        }
    }
}
