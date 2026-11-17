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
    /// Prompts whose `prepare` has run.
    @ObservationIgnored private var prepared: Set<String> = []
    /// The `prepare` under way, if any. Nothing shows while it runs.
    @ObservationIgnored private(set) var preparing: Task<Void, Never>?
    /// Prompts already traced as not needed this time, so each says so once.
    @ObservationIgnored private var skipped: Set<String> = []

    /// How a prompt was answered no, for the trace.
    enum Decline: String {
        /// Its second button.
        case button
        /// Swiped away without answering.
        case closed
    }

    init(prompts: [Prompt] = Prompt.all, defaults: UserDefaults = .standard) {
        self.prompts = prompts
        self.defaults = defaults
    }

    private var answered: Set<String> {
        Set(defaults.stringArray(forKey: Self.answeredKey) ?? [])
    }

    /// Moves on to the first prompt that hasn't been answered and is still needed. A prompt with work to do
    /// first does it, then the queue looks again.
    func showNext() {
        let answered = self.answered
        for prompt in prompts where !answered.contains(prompt.id) {
            if let prepare = prompt.prepare, !prepared.contains(prompt.id) {
                prepared.insert(prompt.id)
                current = nil
                preparing = Task {
                    // Such as looking in Health, which can be slow: timed, so a late prompt can be told apart.
                    let started = Date.now
                    await prepare()
                    Trace.log(.prompt, "Prepared", ["prompt": prompt.id, "seconds": Date.now.timeIntervalSince(started)])
                    preparing = nil
                    showNext()
                }
                return
            }
            if prompt.isNeeded() {
                current = prompt
                return
            }
            // Such as the weight once Health gave one. It's asked again on a later open if it's needed then.
            if skipped.insert(prompt.id).inserted {
                Trace.log(.prompt, "Skipped, not needed", ["prompt": prompt.id])
            }
        }
        current = nil
    }

    /// Does what the prompt's yes does, then moves on. With `id`, only while that prompt is the one showing,
    /// so a second tap as its sheet goes can't answer the next prompt before the runner has seen it.
    func accept(_ id: String? = nil) async {
        guard let prompt = current, id == nil || prompt.id == id, !isAccepting, prompt.canAccept() else { return }
        Trace.log(.prompt, "Accepted", ["prompt": prompt.id])
        isAccepting = true
        await prompt.accept()
        isAccepting = false
        finish(prompt)
    }

    /// The runner said no, or closed the prompt without answering. Either way it isn't asked again. With
    /// `id`, only while that prompt is the one showing.
    func decline(_ id: String? = nil, how: Decline = .button) {
        guard let prompt = current, id == nil || prompt.id == id, !isAccepting else { return }
        Trace.log(.prompt, how == .button ? "Declined" : "Closed", ["prompt": prompt.id])
        prompt.decline()
        finish(prompt)
    }

    private func finish(_ prompt: Prompt) {
        defaults.set(answered.union([prompt.id]).sorted(), forKey: Self.answeredKey)
        showNext()
    }
}
