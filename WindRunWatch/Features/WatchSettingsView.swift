//
//  WatchSettingsView.swift
//  Wind Run Watch
//

import SwiftUI

/// Units and pace call-outs, kept in step with the same settings on the iPhone.
struct WatchSettingsView: View {
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
        Form {
            Picker("Units", selection: $unit) {
                ForEach(DistanceUnit.allCases) { unit in
                    Text(unit.name).tag(unit)
                }
            }

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
                    Text("“\(sample.spokenText)”")
                }
            }
        }
        .navigationTitle("Settings")
        .onDisappear { speaker.stop() }
    }
}

#Preview {
    NavigationStack {
        WatchSettingsView()
    }
}
