//
//  Prompt.swift
//  Wind Run
//

import SwiftUI

/// A question Wind Run asks once, such as whether to turn a feature on.
///
/// Prompts show one at a time when the app opens, in the order of `Prompt.all`, and each device
/// asks each one only once. When something new needs the runner's go-ahead, add a prompt there.
struct Prompt: Identifiable {
    /// Remembered once the prompt is answered, so it has to stay the same from release to release.
    let id: String
    let systemImage: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let acceptTitle: LocalizedStringKey
    var declineTitle: LocalizedStringKey = "Not Now"
    /// Whether the question still needs asking on this device, for example because the feature
    /// works here and isn't on yet. Checked each time the app opens until the prompt is answered.
    let isNeeded: @MainActor () -> Bool
    /// What saying yes does, such as turning a setting on and asking for permission.
    /// The prompt stays up until it finishes.
    let accept: @MainActor () async -> Void
}

extension Prompt {
    /// Everything Wind Run asks when it opens, in order.
    static let all: [Prompt] = [.heartRate]
}
