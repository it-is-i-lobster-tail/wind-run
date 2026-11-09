//
//  HapticsSection.swift
//  Wind Run
//

import SwiftUI

/// Haptics settings, shared by the iPhone and watch settings. Both choices follow the runner between devices,
/// so the iPhone and the watch buzz in the same pattern.
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
        guard devices != .off else { return "No buzzes when an interval step changes or auto-pause stops the clock." }
        #if os(watchOS)
        return pattern.summary
        #else
        return "A buzz when an interval step changes or auto-pause stops the clock. \(pattern.summary) Each device buzzes during the runs it records."
        #endif
    }
}
