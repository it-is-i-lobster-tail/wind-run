//
//  HeartRateSection.swift
//  Wind Run
//

import SwiftUI

/// The "Heart rate" switch, shared by the iPhone and watch settings.
///
/// Turning it on asks Health for permission. Heart rate comes from a workout session, so Health
/// asks to allow workouts as well as heart rate. Without workouts the switch goes back off.
struct HeartRateSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(HeartRateMonitor.storageKey) private var measuresHeartRate = false
    @State private var access = HealthSync.shared.access

    private let health = HealthSync.shared

    var body: some View {
        Section {
            Toggle("Heart rate", isOn: $measuresHeartRate)
                .disabled(!health.isAvailable)
        } footer: {
            Text(footer)
        }
        .onChange(of: measuresHeartRate) { _, isOn in
            guard isOn else { return }
            Task {
                access = await HeartRateMonitor.requestAccess()
                if access == .denied {
                    measuresHeartRate = false
                }
            }
        }
        // Permission can change in the Settings app while Wind Run is in the background.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                access = health.access
            }
        }
    }

    private var footer: LocalizedStringKey {
        if !health.isAvailable {
            return "Health isn't available on this device."
        }
        if access == .denied {
            #if os(watchOS)
            return "Heart rate needs Workouts allowed for Wind Run in Health settings. Allow it, then turn this on."
            #else
            return "Heart rate needs Workouts allowed in Settings > Privacy & Security > Health > Wind Run. Allow it, then turn this on."
            #endif
        }
        #if os(watchOS)
        return "Shows your heart rate while you run and keeps it with the run on this watch."
        #else
        return "Shows your heart rate while you run, from AirPods Pro 3, Powerbeats Pro 2, or a Bluetooth strap paired in Settings. Readings stay with your runs on this device."
        #endif
    }
}
