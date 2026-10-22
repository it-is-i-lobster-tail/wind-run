//
//  PromptQueue.swift
//  Wind Run
//

import Foundation
import Observation

/// Works through the prompts still to ask on this device, one at a time.
///
/// Answers are remembered on this device only, since permissions like Health's are per device.
@Observable
final class PromptQueue {
    static let answeredKey = "answeredPrompts"

    /// The prompt to show, or nil when there's nothing left to ask.
    private(set) var current: Prompt?
    /// True while a yes is being acted on, such as while Health's permission sheet is up.
    private(set) var isAccepting = false

    @ObservationIgnored private let prompts: [Prompt]
    @ObservationIgnored private let defaults: UserDefaults

    init(prompts: [Prompt] = Prompt.all, defaults: UserDefaults = .standard) {
        self.prompts = prompts
        self.defaults = defaults
    }

    private var answered: Set<String> {
        Set(defaults.stringArray(forKey: Self.answeredKey) ?? [])
    }

    /// Moves on to the first prompt that hasn't been answered and is still needed.
    func showNext() {
        let answered = self.answered
        current = prompts.first { !answered.contains($0.id) && $0.isNeeded() }
    }

    /// Does what the current prompt's yes does, then moves on.
    func accept() async {
        guard let prompt = current, !isAccepting else { return }
        isAccepting = true
        await prompt.accept()
        isAccepting = false
        finish(prompt)
    }

    /// The runner said no, or closed the prompt without answering. Either way it isn't asked again.
    func decline() {
        guard let prompt = current, !isAccepting else { return }
        prompt.decline()
        finish(prompt)
    }

    private func finish(_ prompt: Prompt) {
        defaults.set(answered.union([prompt.id]).sorted(), forKey: Self.answeredKey)
        showNext()
    }
}
