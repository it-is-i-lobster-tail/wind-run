//
//  WatchSettingsView.swift
//  Wind Run Watch
//

import SwiftUI

/// The watch's settings. Units and call-outs stay in step with the iPhone's. Saving to Health
/// is set on each device, since each one records its own runs, and so is the voice, since each
/// device has its own voices.
struct WatchSettingsView: View {
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    var body: some View {
        List {
            Picker("Units", selection: $unit) {
                ForEach(DistanceUnit.allCases) { unit in
                    Text(unit.systemName).tag(unit)
                }
            }

            PaceCalloutSection()
            CalloutVoiceSection()

            HealthSyncSection()
            HeartRateSection()
            MotionSection()
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        WatchSettingsView()
    }
}
