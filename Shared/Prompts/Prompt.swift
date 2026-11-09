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
    /// What the second button does. Most prompts do nothing, which leaves the feature off.
    var decline: @MainActor () -> Void = {}
    /// A question with no "Not Now", such as a choice between two options. The sheet can't be
    /// closed without picking one.
    var requiresAnswer = false
    /// Something to fill in under the message, such as a number field.
    var content: (@MainActor () -> AnyView)? = nil
    /// Work done before deciding whether to ask, such as looking for the answer in Health. Runs once, the
    /// first time the prompt comes up; `isNeeded` is checked after it.
    var prepare: (@MainActor () async -> Void)? = nil
    /// Whether the yes button can be tapped yet, such as once a number is filled in. Read while the
    /// prompt shows, so it follows what's typed.
    var canAccept: @MainActor () -> Bool = { true }
}

extension Prompt {
    /// Everything Wind Run asks when it opens, in order.
    #if os(watchOS)
    // The watch takes its units from the iPhone.
    static let all: [Prompt] = [.heartRate, .motion, .saveRunsToHealth]
    #else
    // Units come first so the weight can be asked in them. Weight comes after Health, so it can come from there.
    static let all: [Prompt] = [.units, .heartRate, .motion, .saveRunsToHealth, .bodyWeight]
    #endif
}
