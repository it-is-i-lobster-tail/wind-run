//
//  FirstOpenSetupTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The one setup page first open shows. Health and Motion are left out, so no system sheet comes up.
@MainActor
final class FirstOpenSetupTests {
    private let suiteName = "FirstOpenSetupTests-\(UUID().uuidString)"
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

    @Test("A new device is asked, and the page can't be swiped away")
    func asksOnFirstOpen() {
        let prompt = Prompt.settingUp(setup())
        #expect(prompt.isNeeded())
        #expect(prompt.requiresAnswer)
    }

    @Test("A device that answered the old separate questions isn't asked again")
    func notAskedAfterTheOldQuestions() {
        defaults.set(["heartRate", "units"], forKey: PromptQueue.answeredKey)
        #expect(!setup().isNeeded)
    }

    @Test("Once answered it's never asked again, either way")
    func answeredOnce() async {
        let queue = PromptQueue(prompts: [.settingUp(setup())], defaults: defaults)
        queue.showNext()
        #expect(queue.current?.id == "setup")
        queue.decline()
        #expect(queue.current == nil)

        let reopened = PromptQueue(prompts: [.settingUp(setup())], defaults: defaults)
        reopened.showNext()
        #expect(reopened.current == nil)
    }

    @Test("Units start on what was picked before, such as from iCloud")
    func unitsStartOnTheSavedPick() {
        defaults.set(DistanceUnit.miles.rawValue, forKey: DistanceUnit.storageKey)
        #expect(setup().unit == .miles)
        defaults.set(DistanceUnit.kilometers.rawValue, forKey: DistanceUnit.storageKey)
        #expect(setup().unit == .kilometers)
    }

    @Test("Continue saves the units and the weight in kilograms")
    func continueSavesUnitsAndWeight() async {
        let setup = setup()
        setup.unit = .miles
        setup.weightText = "150"
        await setup.apply()
        #expect(defaults.string(forKey: DistanceUnit.storageKey) == "miles")
        #expect(abs((BodyWeight.kilograms(in: defaults) ?? 0) - 68.04) < 0.01)
    }

    @Test("Not Now still saves the units and a weight, and turns nothing on")
    func notNowKeepsUnitsAndWeight() {
        let setup = setup()
        setup.unit = .kilometers
        setup.weightText = "70"
        setup.applyNotNow()
        #expect(defaults.string(forKey: DistanceUnit.storageKey) == "kilometers")
        #expect(BodyWeight.kilograms(in: defaults) == 70)
        #expect(!defaults.bool(forKey: HeartRateMonitor.storageKey))
        #expect(!defaults.bool(forKey: HealthSync.enabledKey))
        #expect(!defaults.bool(forKey: AutoPause.storageKey))
    }

    @Test("Continue with no weight leaves weight unset, so calories wait for one")
    func noWeightTyped() async {
        await setup().apply()
        #expect(BodyWeight.kilograms(in: defaults) == nil)
    }

    @Test("Continue waits for a weight it can save")
    func continueNeedsARealWeight() {
        let setup = setup()
        setup.unit = .miles
        #expect(setup.canContinue)
        setup.weightText = "12"
        #expect(!setup.canContinue)
        #expect(setup.weightProblem == "Enter a weight between 56 and 661 lb.")
        setup.weightText = "150"
        #expect(setup.canContinue)
        #expect(setup.weightProblem == nil)
    }

    @Test("Switching units changes the weight typed to match")
    func switchingUnitsConvertsTheWeight() {
        let setup = setup()
        setup.unit = .kilometers
        setup.weightText = "68"
        setup.unit = .miles
        #expect(setup.weightText == "150")
    }

    @Test("Without step counting, the motion switch turns on auto-pause from GPS alone")
    func autoPauseWithoutSteps() async {
        let setup = setup()
        await setup.apply()
        #expect(defaults.bool(forKey: AutoPause.storageKey))
        #expect(!defaults.bool(forKey: MotionMonitor.stepsKey))
    }

    @Test("A weight from iCloud shows on the page and isn't saved again unchanged")
    func iCloudWeightShows() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        defaults.set(DistanceUnit.kilometers.rawValue, forKey: DistanceUnit.storageKey)
        BodyWeight.save(70.04, measuredAt: date, in: defaults)
        let setup = setup()
        #expect(setup.weightText == "70")
        setup.applyNotNow()
        #expect(BodyWeight.kilograms(in: defaults) == 70.04)
        #expect(BodyWeight.date(in: defaults) == date)
    }
}
