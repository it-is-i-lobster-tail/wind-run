//
//  PromptQueueTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftUI
import Testing
@testable import WindRun

@MainActor
final class PromptQueueTests {
    private let suiteName = "PromptQueueTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func prompt(
        _ id: String,
        isNeeded: Bool = true,
        onAccept: @escaping @MainActor () -> Void = {}
    ) -> Prompt {
        Prompt(
            id: id,
            systemImage: "star",
            title: "Title",
            message: "Message",
            acceptTitle: "Yes",
            isNeeded: { isNeeded },
            accept: { onAccept() }
        )
    }

    @Test func nothingShowsUntilAsked() {
        let queue = PromptQueue(prompts: [prompt("first")], defaults: defaults)

        #expect(queue.current == nil)
        queue.showNext()
        #expect(queue.current?.id == "first")
    }

    @Test func promptsComeOneAtATimeInOrder() async {
        let queue = PromptQueue(prompts: [prompt("first"), prompt("second")], defaults: defaults)
        queue.showNext()

        queue.decline()
        #expect(queue.current?.id == "second")
        await queue.accept()
        #expect(queue.current == nil)
    }

    @Test func anAnsweredPromptIsntAskedAgain() async {
        let prompts = [prompt("declined"), prompt("accepted")]
        let queue = PromptQueue(prompts: prompts, defaults: defaults)
        queue.showNext()
        queue.decline()
        await queue.accept()

        // As if the app opened again.
        let reopened = PromptQueue(prompts: prompts, defaults: defaults)
        reopened.showNext()
        #expect(reopened.current == nil)
    }

    @Test func aPromptThatIsntNeededIsSkippedButStillAskedLater() {
        let queue = PromptQueue(prompts: [prompt("later", isNeeded: false), prompt("now")], defaults: defaults)
        queue.showNext()
        #expect(queue.current?.id == "now")
        queue.decline()

        let reopened = PromptQueue(prompts: [prompt("later")], defaults: defaults)
        reopened.showNext()
        #expect(reopened.current?.id == "later")
    }

    @Test func onlyAcceptingRunsThePromptsAction() async {
        var accepted: [String] = []
        let queue = PromptQueue(
            prompts: [
                prompt("declined") { accepted.append("declined") },
                prompt("accepted") { accepted.append("accepted") },
            ],
            defaults: defaults
        )
        queue.showNext()
        queue.decline()
        await queue.accept()

        #expect(accepted == ["accepted"])
        #expect(!queue.isAccepting)
    }

    @Test func unitsThenWeightThenHeartRateThenMotionThenSavingRuns() {
        #expect(Prompt.all.map(\.id) == ["units", "bodyWeight", "heartRate", "motion", "saveRunsToHealth"])
    }

    @Test func weightCantBeSavedUntilItsAWeightAndIsSavedInKilograms() async {
        defaults.set(DistanceUnit.miles.rawValue, forKey: DistanceUnit.storageKey)
        let prompt = Prompt.enteringBodyWeight(defaults: defaults)
        let queue = PromptQueue(prompts: [prompt], defaults: defaults)
        queue.showNext()
        #expect(queue.current?.id == "bodyWeight")
        #expect(!prompt.canAccept())

        // Nothing typed yet, so Save does nothing.
        await queue.accept()
        #expect(queue.current?.id == "bodyWeight")
        #expect(BodyWeight.kilograms(in: defaults) == nil)
    }

    @Test func aSavedWeightIsntAskedFor() {
        let prompt = Prompt.enteringBodyWeight(defaults: defaults)
        #expect(prompt.isNeeded())
        BodyWeight.save(70, in: defaults)
        #expect(!prompt.isNeeded())
    }

    @Test func theWeightTypedIsSavedInKilograms() {
        defaults.set(DistanceUnit.miles.rawValue, forKey: DistanceUnit.storageKey)
        let entry = BodyWeightEntry(defaults: defaults)
        entry.text = "150"
        entry.save()
        #expect(abs((BodyWeight.kilograms(in: defaults) ?? 0) - 68.04) < 0.01)
    }

    @Test func savingRunsIsOnlyAskedWhileItsOff() {
        let prompt = Prompt.savingRunsToHealth(defaults: defaults)
        #expect(prompt.isNeeded() == HealthSync.shared.isAvailable)

        defaults.set(true, forKey: HealthSync.enabledKey)
        #expect(!prompt.isNeeded())
    }
}
