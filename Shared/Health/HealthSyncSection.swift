//
//  HealthSyncSection.swift
//  Wind Run
//

import SwiftUI

/// The "Save runs to Health" switch, shared by the iPhone and watch settings.
///
/// Turning it on asks Health for permission. If Health says no, the switch goes back off,
/// since nothing would be saved.
struct HealthSyncSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(HealthSync.enabledKey) private var savesToHealth = false
    @State private var access = HealthSync.shared.access

    private let health = HealthSync.shared

    var body: some View {
        Section {
            Toggle("Save runs to Health", isOn: $savesToHealth)
                .disabled(!health.isAvailable)
        } header: {
            Text("Apple Health")
        } footer: {
            Text(footer)
        }
        .onChange(of: savesToHealth) { _, isOn in
            guard isOn else { return }
            Task {
                access = await health.requestAccess()
                if access == .denied {
                    savesToHealth = false
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
            return "Wind Run isn't allowed to save to Health. Allow it in Health settings, then turn this on."
            #else
            return "Wind Run isn't allowed to save to Health. Allow it in Settings > Privacy & Security > Health > Wind Run, then turn this on."
            #endif
        }
        #if os(watchOS)
        return "Adds each run you finish to Health. Turning this off only stops new runs."
        #else
        return "Adds each run you finish to the Health app, with its route. Turning this off only stops new runs. Runs already in Health stay there."
        #endif
    }
}
