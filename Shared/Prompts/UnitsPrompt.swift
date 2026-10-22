//
//  UnitsPrompt.swift
//  Wind Run
//

import SwiftUI

extension Prompt {
    /// Asks on first open whether to use metric or imperial units. The region's system is the
    /// first button. Skipped when a unit was already picked, or came from iCloud.
    static let units = choosingUnits(suggesting: .regionDefault)

    static func choosingUnits(suggesting suggested: DistanceUnit, defaults: UserDefaults = .standard) -> Prompt {
        let other: DistanceUnit = suggested == .kilometers ? .miles : .kilometers
        return Prompt(
            id: "units",
            systemImage: "ruler",
            title: "Metric or imperial?",
            message: "Wind Run shows distance, pace, height and weight in the units you pick. You can change this anytime in Settings.",
            acceptTitle: choiceTitle(suggested),
            declineTitle: choiceTitle(other),
            isNeeded: { !DistanceUnit.isChosen(in: defaults) },
            accept: { defaults.set(suggested.rawValue, forKey: DistanceUnit.storageKey) },
            decline: { defaults.set(other.rawValue, forKey: DistanceUnit.storageKey) },
            requiresAnswer: true
        )
    }

    private static func choiceTitle(_ unit: DistanceUnit) -> LocalizedStringKey {
        "\(unit.systemName) (\(unit.systemExamples))"
    }
}
