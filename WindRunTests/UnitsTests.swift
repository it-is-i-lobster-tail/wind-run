//
//  UnitsTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// Picking metric or imperial on first open, and height in feet and inches.
@MainActor
final class UnitsTests {
    private let suiteName = "UnitsTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test("The first open asks for units, and the answer can't be skipped")
    func asksOnFirstOpen() {
        let prompt = Prompt.choosingUnits(suggesting: .kilometers, defaults: defaults)
        #expect(prompt.isNeeded())
        #expect(prompt.requiresAnswer)
    }

    @Test("The first button picks the suggested system, the second the other one")
    func eachButtonPicksAUnit() async {
        let queue = PromptQueue(prompts: [Prompt.choosingUnits(suggesting: .miles, defaults: defaults)], defaults: defaults)
        queue.showNext()
        await queue.accept()
        #expect(defaults.string(forKey: DistanceUnit.storageKey) == "miles")

        defaults.removeObject(forKey: DistanceUnit.storageKey)
        defaults.removeObject(forKey: PromptQueue.answeredKey)
        let again = PromptQueue(prompts: [Prompt.choosingUnits(suggesting: .miles, defaults: defaults)], defaults: defaults)
        again.showNext()
        again.decline()
        #expect(defaults.string(forKey: DistanceUnit.storageKey) == "kilometers")
    }

    @Test("A runner who already picked a unit isn't asked")
    func notAskedOncePicked() {
        defaults.set(DistanceUnit.miles.rawValue, forKey: DistanceUnit.storageKey)
        #expect(!Prompt.choosingUnits(suggesting: .kilometers, defaults: defaults).isNeeded())
    }

    @Test("Height in feet and inches is kept as centimeters")
    func feetAndInches() {
        #expect(FeetAndInchesField.centimeters(feet: "5", inches: "11") == 71 * 2.54)
        #expect(FeetAndInchesField.centimeters(feet: "6", inches: "") == 72 * 2.54)
        #expect(FeetAndInchesField.centimeters(feet: "", inches: "11") == nil)
        #expect(FeetAndInchesField.centimeters(feet: "0", inches: "0") == nil)

        let fiveEleven = FeetAndInchesField.feetAndInches(180.34)
        #expect(fiveEleven.feet == 5 && fiveEleven.inches == 11)
        // 5 ft 11.8 in rounds up to 6 ft, not 5 ft 12 in.
        let almostSix = FeetAndInchesField.feetAndInches(182.4)
        #expect(almostSix.feet == 6 && almostSix.inches == 0)
    }
}
