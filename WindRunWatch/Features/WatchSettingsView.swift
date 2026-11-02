//
//  WatchSettingsView.swift
//  Wind Run Watch
//

import SwiftUI

/// The watch's settings. Units, call-outs and haptics stay in step with the iPhone's. Saving to Health
/// is set on each device, since each one records its own runs.
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
            HapticsSection()

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
