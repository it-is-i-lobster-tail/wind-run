//
//  MotionPrompt.swift
//  Wind Run
//

import SwiftUI

extension Prompt {
    /// Asks on first open whether to count steps and pause when the runner stops. Both stay off unless
    /// the runner says yes, which turns them on and asks for Motion & Fitness.
    static let motion = Prompt(
        id: "motion",
        systemImage: "figure.run",
        title: "Count steps and auto-pause?",
        message: motionMessage,
        acceptTitle: "Turn On",
        isNeeded: {
            MotionMonitor.isAvailable
                && !(UserDefaults.standard.bool(forKey: MotionMonitor.stepsKey) && UserDefaults.standard.bool(forKey: AutoPause.storageKey))
        },
        accept: {
            await MotionMonitor.turnOn()
        }
    )

    #if os(watchOS)
    private static let motionMessage: LocalizedStringKey = "Count your steps, and pause the clock when you stand still. Uses Motion & Fitness. You can change this in Settings."
    #else
    private static let motionMessage: LocalizedStringKey = "Wind Run can count your steps, show your cadence, and pause the clock when you stop at a crossing, using your iPhone's motion sensor with GPS. Steps are kept with your runs, like your routes. You can change this anytime in Settings."
    #endif
}
