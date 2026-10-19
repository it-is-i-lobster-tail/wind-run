//
//  PaceCalloutSection.swift
//  Wind Run
//

import SwiftUI

/// Pace call-out settings, shared by the iPhone and watch settings.
///
/// Distance options follow the runner's unit, so "¼ mi" becomes "250 m" in kilometers.
struct PaceCalloutSection: View {
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage(PaceCalloutSettings.modeKey) private var mode = PaceCalloutMode.off
    @AppStorage(PaceCalloutSettings.distanceKey) private var distance = PaceCalloutSettings.defaultDistance
    @AppStorage(PaceCalloutSettings.secondsKey) private var seconds = PaceCalloutSettings.defaultSeconds

    @State private var speaker = CalloutSpeaker()

    private var sample: PaceCallout? {
        PaceCallout.sample(for: PaceCalloutSettings(mode: mode, unit: unit, distance: distance, seconds: seconds))
    }

    var body: some View {
        Section {
            Picker("Call out", selection: $mode) {
                ForEach(PaceCalloutMode.allCases) { mode in
                    Text(mode.name).tag(mode)
                }
            }

            switch mode {
            case .off:
                EmptyView()
            case .distance:
                Picker("Every", selection: $distance) {
                    ForEach(PaceCalloutSettings.distanceOptions, id: \.self) { distance in
                        Text(PaceCalloutSettings.distanceName(distance, unit: unit)).tag(distance)
                    }
                }
            case .time:
                Picker("Every", selection: $seconds) {
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
            Text(footer)
        }
        .onDisappear { speaker.stop() }
    }

    private var footer: String {
        guard let sample else { return "Hear your split pace read out as you run." }
        #if os(watchOS)
        return "“\(sample.spokenText)”"
        #else
        return "“\(sample.spokenText)” Each call-out is the pace of the split you just ran."
        #endif
    }
}
