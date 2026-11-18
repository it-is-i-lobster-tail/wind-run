//
//  WorkoutPacePage.swift
//  Wind Run
//

import SwiftUI

/// The main part's target pace: one pace, or a range from faster to slower, per kilometer or mile as the
/// runner counts. Each change goes straight into the workout; Remove takes it out.
struct WorkoutPacePage: View {
    @Environment(\.dismiss) private var dismiss

    let unit: DistanceUnit
    /// Sets the pace, seconds per kilometer, or nil to take it out.
    let apply: (ClosedRange<TimeInterval>?) -> Void

    @State private var entry: PaceEntry

    init(pace: ClosedRange<TimeInterval>?, unit: DistanceUnit, apply: @escaping (ClosedRange<TimeInterval>?) -> Void) {
        self.unit = unit
        self.apply = apply
        _entry = State(initialValue: PaceEntry(pace, unit: unit))
    }

    var body: some View {
        Form {
            Section {
                Picker("Target pace", selection: $entry.isRange.traced("Target pace", "Kind") { $0 ? "range" : "single" }) {
                    Text("Single pace").tag(false)
                    Text("Pace range").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Main workout only")
            }

            Section {
                if entry.isRange {
                    PaceRow(title: "Faster pace", text: $entry.faster, unit: entry.unit)
                    PaceRow(title: "Slower pace", text: $entry.slower, unit: entry.unit)
                } else {
                    PaceRow(title: "Target pace", text: $entry.single, unit: entry.unit)
                }
            } footer: {
                if let pace = entry.pace {
                    Text("Target: \(WorkoutDistance.paceText(pace, unit: entry.unit))")
                }
            }

            Section {
                Button(role: .destructive) {
                    Trace.tap("Target pace", "Remove target pace")
                    apply(nil)
                    dismiss()
                } label: {
                    Text("Remove target pace")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Target Pace")
        .navigationBarTitleDisplayMode(.inline)
        .traceScreen("Target pace")
        // Added as it opens, so Back keeps a pace just added.
        .onAppear { if let pace = entry.pace { apply(pace) } }
        // While a box is empty or doesn't read as a pace, the workout keeps its last one.
        .onChange(of: entry.pace) { _, pace in
            if let pace { apply(pace) }
        }
    }
}

/// "Target pace", a filled box to type m:ss in, and "min/km" or "min/mi".
private struct PaceRow: View {
    let title: String
    @Binding var text: String
    let unit: DistanceUnit

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0:00", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(width: 64)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.fill.tertiary, in: .rect(cornerRadius: 10))
                .accessibilityLabel("\(title) per \(unit.singularName)")
            Text("min/\(unit.symbol)")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}
