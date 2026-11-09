//
//  SaveRunsPrompt.swift
//  Wind Run
//

import SwiftUI

extension Prompt {
    /// Asks on first open, right after heart rate, whether to save runs to Apple Health. Saving
    /// stays off unless the runner says yes, which turns "Save runs to Health" on and asks Health
    /// for permission. Skipped when it's already on, or came on from iCloud.
    static let saveRunsToHealth = savingRunsToHealth()

    static func savingRunsToHealth(defaults: UserDefaults = .standard) -> Prompt {
        Prompt(
            id: "saveRunsToHealth",
            systemImage: "heart.circle.fill",
            title: "Save your runs to Apple Health?",
            message: saveRunsMessage,
            acceptTitle: "Turn On",
            isNeeded: {
                HealthSync.shared.isAvailable && !defaults.bool(forKey: HealthSync.enabledKey)
            },
            accept: {
                await HealthSync.shared.turnOn(defaults: defaults)
            }
        )
    }

    #if os(watchOS)
    private static let saveRunsMessage: LocalizedStringKey = "Add each run you finish to the Health app. You can change this in Settings."
    #else
    private static let saveRunsMessage: LocalizedStringKey = "Add each run you finish to the Health app, with its route, next to the rest of your activity. You can change this anytime in Settings."
    #endif
}
