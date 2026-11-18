//
//  FirstOpenSetup.swift
//  Wind Run
//

import Foundation
import Observation
import SwiftUI

extension Prompt {
    /// First open's one page: units, heart rate, Save runs to Health, steps and auto-pause, and weight on the
    /// iPhone; the Health and motion switches on the watch. Continue asks Apple's Health sheet once for both
    /// Health switches, and nothing else: Motion & Fitness is asked on the first run, with location. Not Now keeps the units and any weight typed and leaves the rest
    /// off. It replaced five separate questions (the owner, 2026-11-17).
    static let firstOpenSetup = settingUp()

    static func settingUp(_ setup: FirstOpenSetup = FirstOpenSetup()) -> Prompt {
        Prompt(
            id: FirstOpenSetup.id,
            systemImage: "figure.run",
            title: "Welcome to Wind Run",
            message: "A few choices before your first run.",
            acceptTitle: "Continue",
            isNeeded: { setup.isNeeded },
            accept: { await setup.apply() },
            decline: { setup.applyNotNow() },
            // Swiping a long form by mistake shouldn't skip it. Not Now is on the page.
            requiresAnswer: true,
            canAccept: { setup.canContinue },
            page: { queue in AnyView(FirstOpenSetupView(setup: setup, queue: queue)) }
        )
    }
}

/// The choices on the first-open setup page, and what Continue and Not Now do with them.
@Observable
final class FirstOpenSetup {
    static let id = "setup"
    /// The separate first-open questions this page replaced. A device that answered any of them has been set
    /// up already, so it isn't asked again.
    static let replacedIDs: Set<String> = ["units", "heartRate", "motion", "saveRunsToHealth", "bodyWeight"]

    /// Metric or imperial, shown first. Weight typed in the old units is changed to the new ones.
    var unit: DistanceUnit {
        didSet {
            guard unit != oldValue, let kilograms = BodyWeight.kilograms(fromTyped: weightText, unit: oldValue) else { return }
            weightText = BodyWeight.typed(kilograms, unit: unit)
        }
    }
    // Each switch starts on, so Continue turns everything on and the runner turns off what they don't want.
    var heartRate = true
    var saveRuns = true
    var motion = true
    /// Optional. Left empty, the weight comes from Health when it has one.
    var weightText = ""

    /// Whether this device has Apple Health, so the Health switches show.
    let offersHealth: Bool
    /// Whether this device can count steps. Without it the switch is auto-pause alone, from GPS.
    let countsSteps: Bool

    @ObservationIgnored private let defaults: UserDefaults

    init(
        defaults: UserDefaults = .standard,
        offersHealth: Bool = HealthSync.shared.isAvailable,
        countsSteps: Bool = MotionMonitor.isAvailable
    ) {
        self.defaults = defaults
        self.offersHealth = offersHealth
        self.countsSteps = countsSteps
        unit = defaults.string(forKey: DistanceUnit.storageKey).flatMap(DistanceUnit.init(rawValue:)) ?? .regionDefault
        // A weight that came from iCloud shows, so it isn't typed twice.
        if let kilograms = BodyWeight.kilograms(in: defaults) {
            weightText = BodyWeight.typed(kilograms, unit: unit)
        }
    }

    /// Asked once per device, unless the device went through the separate questions before this page.
    var isNeeded: Bool {
        PromptQueue.answeredIDs(in: defaults).isDisjoint(with: Self.replacedIDs)
    }

    /// Whether either Health switch is on, so the weight can come from Health.
    var usesHealth: Bool {
        offersHealth && (heartRate || saveRuns)
    }

    /// The weight typed, in kilograms, or nil when nothing's typed or it isn't a weight.
    var kilograms: Double? {
        BodyWeight.kilograms(fromTyped: weightText, unit: unit)
    }

    /// The weight box without the spaces around what's typed.
    private var trimmedWeightText: String {
        weightText.trimmingCharacters(in: .whitespaces)
    }

    private var hasTypedWeight: Bool {
        !trimmedWeightText.isEmpty
    }

    /// Continue waits for a weight it can save, or none at all.
    var canContinue: Bool {
        !hasTypedWeight || kilograms != nil
    }

    /// Why Continue can't be tapped: "Enter a weight between 56 and 661 lb."
    var weightProblem: String? {
        guard hasTypedWeight, kilograms == nil else { return nil }
        let range = Self.typedWeightRange(unit: unit)
        return switch unit {
        case .miles:
            "Enter a weight between \(range.lowerBound) and \(range.upperBound) lb."
        case .kilometers:
            "Enter a weight between \(range.lowerBound) and \(range.upperBound) kg."
        }
    }

    /// The whole numbers a weight can be typed as, in pounds or kilograms: 56 to 661 lb, 25 to 300 kg. Pounds
    /// round inwards, so every one shown is a weight `BodyWeight` keeps.
    static func typedWeightRange(unit: DistanceUnit) -> ClosedRange<Int> {
        let range = BodyWeight.range
        return switch unit {
        case .miles:
            Int((range.lowerBound / BodyWeight.kilogramsPerPound).rounded(.up))...Int((range.upperBound / BodyWeight.kilogramsPerPound).rounded(.down))
        case .kilometers:
            Int(range.lowerBound)...Int(range.upperBound)
        }
    }

    /// Continue: saves the units and weight, turns on what's switched on, and asks Apple once, for Health. With no weight typed, Health's newest weight is taken when it has one.
    func apply() async {
        saveUnitsAndWeight()
        if usesHealth {
            await HealthSync.shared.turnOn(heartRate: heartRate, saveRuns: saveRuns, defaults: defaults)
        }
        if motion {
            // Motion & Fitness is asked when the first run starts, beside location, so Apple asks only about
            // Health here. Auto-pause works from GPS alone until then, or without a step counter.
            if countsSteps { defaults.set(true, forKey: MotionMonitor.stepsKey) }
            defaults.set(true, forKey: AutoPause.storageKey)
        }
        #if os(iOS)
        // Health's sheet already covered weight, so this only reads it.
        await HealthWeight.fillBeforeAsking(defaults: defaults)
        #endif
        Trace.log(.prompt, "Setup chosen", [
            "heartRate": heartRate, "saveRuns": saveRuns, "motion": motion, "typedWeight": kilograms != nil,
        ])
    }

    /// Not Now: the units still need saving, and a weight typed is kept. Everything else stays off.
    func applyNotNow() {
        saveUnitsAndWeight()
    }

    private func saveUnitsAndWeight() {
        #if os(iOS)
        // The watch takes its units from the iPhone.
        defaults.set(unit.rawValue, forKey: DistanceUnit.storageKey)
        // A weight from iCloud shown unchanged isn't saved again, which would round it and date it today.
        let saved = BodyWeight.kilograms(in: defaults).map { BodyWeight.typed($0, unit: unit) }
        if let kilograms, trimmedWeightText != saved {
            BodyWeight.save(kilograms, in: defaults)
        }
        #endif
    }
}
