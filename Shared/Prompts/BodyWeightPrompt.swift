//
//  BodyWeightPrompt.swift
//  Wind Run
//

#if os(iOS)
import Observation
import SwiftUI

extension Prompt {
    /// Asks on first open, right after units, for the runner's weight, which calories need. Skipping
    /// leaves calories off until a weight is given in Settings.
    static let bodyWeight = enteringBodyWeight()

    static func enteringBodyWeight(defaults: UserDefaults = .standard) -> Prompt {
        let entry = BodyWeightEntry(defaults: defaults)
        return Prompt(
            id: "bodyWeight",
            systemImage: "scalemass",
            title: "What do you weigh?",
            message: "Wind Run uses your weight to work out the calories each run burns, uphill and down. It stays on your devices, and in your private iCloud if you turn on iCloud Sync. There's no account, and your health data is never sent to us. You can change it anytime in Settings.",
            acceptTitle: "Save",
            declineTitle: "Skip",
            isNeeded: { BodyWeight.kilograms(in: defaults) == nil },
            accept: { entry.save() },
            content: { AnyView(BodyWeightField(entry: entry)) },
            canAccept: { entry.kilograms != nil }
        )
    }
}

/// The weight typed into the prompt, in the units just picked.
@Observable
final class BodyWeightEntry {
    var text = ""

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The units prompt comes first, so this is the runner's pick.
    var unit: DistanceUnit {
        defaults.string(forKey: DistanceUnit.storageKey).flatMap(DistanceUnit.init(rawValue:)) ?? .regionDefault
    }

    /// What's typed, in kilograms, or nil until it's a weight.
    var kilograms: Double? {
        BodyWeight.kilograms(fromTyped: text, unit: unit)
    }

    func save() {
        BodyWeight.save(kilograms, in: defaults)
    }
}

/// A big number field with its unit, ready to type into.
private struct BodyWeightField: View {
    @Bindable var entry: BodyWeightEntry
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TextField("Weight", text: $entry.text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.title.weight(.semibold).monospacedDigit())
                .focused($isFocused)
                .frame(maxWidth: 120)
                .accessibilityLabel(entry.unit == .miles ? "Weight in pounds" : "Weight in kilograms")
            Text(entry.unit == .miles ? "lb" : "kg")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(.fill.tertiary, in: .rect(cornerRadius: 12))
        .onAppear { isFocused = true }
    }
}
#endif
