//
//  PromptQueueGuardTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftUI
import Testing
@testable import WindRun

/// The queue's guards against answering a prompt the runner hasn't seen: a tap meant for one that's gone,
/// a yes before it can be given, and a second answer while a yes is still under way.
@MainActor
final class PromptQueueGuardTests {
    private let suiteName = "PromptQueueGuardTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    /// Holds a yes open until the test lets it finish.
    @MainActor
    private final class Gate {
        var continuation: CheckedContinuation<Void, Never>?
        var accepts = 0
    }

    private func prompt(
        _ id: String,
        accept: @escaping @MainActor () async -> Void = {},
        decline: @escaping @MainActor () -> Void = {},
        canAccept: @escaping @MainActor () -> Bool = { true }
    ) -> Prompt {
        Prompt(
            id: id,
            systemImage: "star",
            title: "Title",
            message: "Message",
            acceptTitle: "Yes",
            isNeeded: { true },
            accept: accept,
            decline: decline,
            canAccept: canAccept
        )
    }

    private var answered: [String]? {
        defaults.stringArray(forKey: PromptQueue.answeredKey)
    }

    @Test func aStaleTapDoesntAnswerTheNextPrompt() async {
        let queue = PromptQueue(prompts: [prompt("first"), prompt("second")], defaults: defaults)
        queue.showNext()

        await queue.accept("second")
        queue.decline("second")
        #expect(queue.current?.id == "first")
        #expect(answered == nil)

        queue.decline("first")
        #expect(queue.current?.id == "second")
        #expect(answered == ["first"])
    }

    @Test func aYesWaitsUntilItCanBeGiven() async {
        var accepted = false
        let queue = PromptQueue(prompts: [prompt("first", accept: { accepted = true }, canAccept: { false })], defaults: defaults)
        queue.showNext()

        await queue.accept()
        #expect(!accepted)
        #expect(queue.current?.id == "first")
        #expect(answered == nil)
    }

    @Test func closingCountsAsAnAnswer() {
        var declined = 0
        let prompts = [prompt("first", decline: { declined += 1 })]
        let queue = PromptQueue(prompts: prompts, defaults: defaults)
        queue.showNext()

        queue.decline("first", how: .closed)
        #expect(declined == 1)
        #expect(queue.current == nil)
        #expect(answered == ["first"])

        let reopened = PromptQueue(prompts: prompts, defaults: defaults)
        reopened.showNext()
        #expect(reopened.current == nil)
    }

    @Test func nothingElseAnswersWhileAYesIsUnderWay() async {
        let gate = Gate()
        let queue = PromptQueue(prompts: [
            prompt("first", accept: {
                gate.accepts += 1
                await withCheckedContinuation { gate.continuation = $0 }
            }),
            prompt("second"),
        ], defaults: defaults)
        queue.showNext()

        let accepting = Task { await queue.accept("first") }
        while gate.continuation == nil {
            await Task.yield()
        }
        #expect(queue.isAccepting)

        queue.decline()
        await queue.accept()
        #expect(queue.current?.id == "first")
        #expect(gate.accepts == 1)

        gate.continuation?.resume()
        await accepting.value
        #expect(!queue.isAccepting)
        #expect(queue.current?.id == "second")
        #expect(answered == ["first"])
    }
}
