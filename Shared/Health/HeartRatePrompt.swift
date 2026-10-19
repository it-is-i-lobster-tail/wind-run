//
//  HeartRatePrompt.swift
//  Wind Run
//

import SwiftUI

extension Prompt {
    /// Asks on first open whether to show heart rate during runs. Heart rate stays off unless
    /// the runner says yes, which turns the Heart rate setting on and asks Health for permission.
    static let heartRate = Prompt(
        id: "heartRate",
        systemImage: "heart.fill",
        title: "Show your heart rate?",
        message: heartRateMessage,
        acceptTitle: "Turn On",
        isNeeded: {
            HealthSync.shared.isAvailable && !UserDefaults.standard.bool(forKey: HeartRateMonitor.storageKey)
        },
        accept: {
            await HeartRateMonitor.turnOn()
        }
    )

    #if os(watchOS)
    private static let heartRateMessage: LocalizedStringKey = "See your heart rate while you run and keep it with each run. You can change this in Settings."
    #else
    private static let heartRateMessage: LocalizedStringKey = "See your heart rate while you run, from AirPods Pro 3, Powerbeats Pro 2, or a Bluetooth strap, and keep it with each run. You can change this anytime in Settings."
    #endif
}
