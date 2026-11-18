//
//  FirstOpenWeightTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The weight on the first-open page: the range its note gives is exactly what can be saved, and the
/// answered prompts it checks are read the way the queue keeps them.
@MainActor
final class FirstOpenWeightTests {
    private let suiteName = "FirstOpenWeightTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func setup() -> FirstOpenSetup {
        FirstOpenSetup(defaults: defaults, offersHealth: false, countsSteps: false)
    }

    @Test func theWeightRangeIsWholePoundsOrKilograms() {
        #expect(FirstOpenSetup.typedWeightRange(unit: .miles) == 56...661)
        #expect(FirstOpenSetup.typedWeightRange(unit: .kilometers) == 25...300)
    }

    @Test func theEndsOfThePoundRangeAreWeightsThatCanBeSaved() {
        #expect(BodyWeight.kilograms(fromTyped: "56", unit: .miles) != nil)
        #expect(BodyWeight.kilograms(fromTyped: "661", unit: .miles) != nil)
        #expect(BodyWeight.kilograms(fromTyped: "55", unit: .miles) == nil)
        #expect(BodyWeight.kilograms(fromTyped: "662", unit: .miles) == nil)
        #expect(BodyWeight.kilograms(fromTyped: "25", unit: .kilometers) == 25)
        #expect(BodyWeight.kilograms(fromTyped: "300", unit: .kilometers) == 300)
        #expect(BodyWeight.kilograms(fromTyped: "24.9", unit: .kilometers) == nil)
    }

    @Test func theKilogramNoteGivesTheKilogramRange() {
        let setup = setup()
        setup.unit = .kilometers
        setup.weightText = "10"
        #expect(!setup.canContinue)
        #expect(setup.weightProblem == "Enter a weight between 25 and 300 kg.")
        setup.weightText = "  "
        #expect(setup.canContinue)
        #expect(setup.weightProblem == nil)
    }

    @Test func answeredPromptsAreReadAsTheQueueKeepsThem() {
        #expect(PromptQueue.answeredIDs(in: defaults).isEmpty)
        #expect(setup().isNeeded)
        defaults.set(["units", "other"], forKey: PromptQueue.answeredKey)
        #expect(PromptQueue.answeredIDs(in: defaults) == ["units", "other"])
        // "units" was one of the questions the setup page replaced.
        #expect(!setup().isNeeded)
    }
}
