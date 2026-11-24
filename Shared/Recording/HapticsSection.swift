//
//  HapticsSection.swift
//  Wind Run
//

import SwiftUI

/// Haptics settings shared by the iPhone and watch. Both choices follow the runner between devices.
struct HapticsSection: View {
    @AppStorage(HapticDevices.storageKey) private var devices = HapticDevices.both
    @AppStorage(HapticPattern.storageKey) private var pattern = HapticPattern.standard

    var body: some View {
        Section {
            Picker("Buzz on", selection: $devices) {
                ForEach(HapticDevices.allCases) { devices in
                    Text(devices.name).tag(devices)
                }
            }

            if devices != .off {
                Picker("Pattern", selection: $pattern) {
                    ForEach(HapticPattern.allCases) { pattern in
                        Text(pattern.name).tag(pattern)
                    }
                }

                Button("Feel a sample", systemImage: "hand.tap") {
                    Trace.tap("Settings", "Feel a sample", ["pattern": pattern.rawValue])
                    StepHaptics.sample(pattern)
                }
            }
        } header: {
            Text("Haptics")
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        guard devices != .off else { return "No buzzes when a step changes, a goal is reached, or auto-pause stops or starts the clock." }
        let events = "A buzz when a step changes, a goal is reached, an open step has gone on a while, or auto-pause stops or starts the clock."
        #if os(watchOS)
        return "\(events) \(pattern.summary) Each device buzzes during the runs it records, so a run on the iPhone doesn't buzz the watch."
        #else
        return "\(events) \(pattern.summary) \(pattern.lockedSummary) Each device buzzes during the runs it records, so a run on the iPhone doesn't buzz the watch."
        #endif
    }
}
