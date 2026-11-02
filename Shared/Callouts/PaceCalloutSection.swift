//
//  PaceCalloutSection.swift
//  Wind Run
//

import SwiftUI

/// The split pace call-outs row in Settings, shared by the iPhone and watch. It opens its own page.
struct PaceCalloutSection: View {
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage(PaceCalloutSettings.modeKey) private var mode = PaceCalloutMode.off
    @AppStorage(PaceCalloutSettings.distanceKey) private var distance = PaceCalloutSettings.defaultDistance
    @AppStorage(PaceCalloutSettings.secondsKey) private var seconds = PaceCalloutSettings.defaultSeconds

    var body: some View {
        Section {
            NavigationLink {
                PaceCalloutSettingsView()
            } label: {
                LabeledContent("Split pace", value: summary)
            }
        } header: {
            Text("Call-outs")
        } footer: {
            #if !os(watchOS)
            Text("Hear your time or distance and pace read out as you run.")
            #endif
        }
    }

    /// "Off", "Every ¼ mi" or "Every 5 min".
    private var summary: String {
        switch mode {
        case .off: "Off"
        case .distance: "Every \(PaceCalloutSettings.distanceName(distance, unit: unit))"
        case .time: "Every \(PaceCalloutSettings.secondsName(seconds))"
        }
    }
}

/// When splits are read out, and which paces each one says.
///
/// Distance options follow the runner's unit, so "¼ mi" becomes "250 m" in kilometers.
struct PaceCalloutSettingsView: View {
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage(PaceCalloutSettings.modeKey) private var mode = PaceCalloutMode.off
    @AppStorage(PaceCalloutSettings.distanceKey) private var distance = PaceCalloutSettings.defaultDistance
    @AppStorage(PaceCalloutSettings.secondsKey) private var seconds = PaceCalloutSettings.defaultSeconds
    @AppStorage(PaceCalloutSettings.pacesKey) private var storedPaces = PaceCalloutSettings.defaultPaces

    @State private var speaker = CalloutSpeaker()

    private var paces: [PaceKind] {
        PaceKind.decode(storedPaces)
    }

    private var sample: PaceCallout? {
        PaceCallout.sample(for: PaceCalloutSettings(mode: mode, unit: unit, distance: distance, seconds: seconds, paces: paces))
    }

    var body: some View {
        Form {
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
            } footer: {
                if mode == .off {
                    Text("Hear your time or distance and pace read out as you run.")
                }
            }

            if mode != .off {
                Section {
                    ForEach(PaceKind.allCases) { kind in
                        Toggle(isOn: picked(kind)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.name(unit: unit))
                                Text(kind.detail(unit: unit))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Paces to say")
                } footer: {
                    Text(paces.isEmpty ? "With none picked, you hear just the distance or time." : "Said in this order.")
                }

                if let sample {
                    Section {
                        Button("Hear a sample", systemImage: "speaker.wave.2") {
                            speaker.speak(sample.spokenText)
                        }
                    } footer: {
                        Text("“\(sample.spokenText)”")
                    }
                }
            }
        }
        .navigationTitle("Split Pace")
        .onDisappear { speaker.stop() }
    }

    private func picked(_ kind: PaceKind) -> Binding<Bool> {
        Binding {
            paces.contains(kind)
        } set: { isOn in
            var kinds = Set(paces)
            if isOn { kinds.insert(kind) } else { kinds.remove(kind) }
            storedPaces = PaceKind.encode(kinds)
        }
    }
}

#Preview {
    NavigationStack {
        PaceCalloutSettingsView()
    }
}
