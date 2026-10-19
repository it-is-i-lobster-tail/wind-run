//
//  SettingsView.swift
//  Wind Run
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage(PaceCalloutSettings.modeKey) private var calloutMode = PaceCalloutMode.off
    @AppStorage(PaceCalloutSettings.distanceKey) private var calloutDistance = PaceCalloutSettings.defaultDistance
    @AppStorage(PaceCalloutSettings.secondsKey) private var calloutSeconds = PaceCalloutSettings.defaultSeconds

    @State private var speaker = CalloutSpeaker()

    private var sample: PaceCallout? {
        PaceCallout.sample(for: PaceCalloutSettings(
            mode: calloutMode,
            unit: unit,
            distance: calloutDistance,
            seconds: calloutSeconds
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Distance", selection: $unit) {
                        ForEach(DistanceUnit.allCases) { unit in
                            Text(unit.name).tag(unit)
                        }
                    }
                }

                callouts

                Section {
                    Label("Runs and routes stay on this device.", systemImage: "lock")
                    Label("No account, no tracking, no analytics.", systemImage: "eye.slash")
                } header: {
                    Text("Privacy")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onDisappear { speaker.stop() }
        }
    }

    private var callouts: some View {
        Section {
            Picker("Call out", selection: $calloutMode) {
                ForEach(PaceCalloutMode.allCases) { mode in
                    Text(mode.name).tag(mode)
                }
            }

            switch calloutMode {
            case .off:
                EmptyView()
            case .distance:
                Picker("Every", selection: $calloutDistance) {
                    ForEach(PaceCalloutSettings.distanceOptions, id: \.self) { distance in
                        Text(PaceCalloutSettings.distanceName(distance, unit: unit)).tag(distance)
                    }
                }
            case .time:
                Picker("Every", selection: $calloutSeconds) {
                    ForEach(PaceCalloutSettings.secondsOptions, id: \.self) { seconds in
                        Text(PaceCalloutSettings.secondsName(seconds)).tag(seconds)
                    }
                }
            }

            if let sample {
                Button("Hear a sample", systemImage: "speaker.wave.2") {
                    speaker.speak(sample.spokenText)
                }
            }
        } header: {
            Text("Pace call-outs")
        } footer: {
            if let sample {
                Text("“\(sample.spokenText)” Each call-out is the pace of the split you just ran.")
            } else {
                Text("Hear your split pace read out as you run.")
            }
        }
    }
}

#Preview("Settings") {
    SettingsView()
}
