//
//  PaceCalloutSection.swift
//  Wind Run
//

import SwiftUI

/// The voice call-outs row in Settings, shared by the iPhone and watch. It opens its own page.
struct PaceCalloutSection: View {
    var body: some View {
        Section("Call-outs") {
            NavigationLink("Voice Call-outs") {
                List(WorkoutSport.allCases) { sport in
                    NavigationLink {
                        PaceCalloutSettingsView(sport: sport)
                    } label: {
                        Label(sport.name, systemImage: sport.systemImage)
                    }
                }
                .navigationTitle("Voice Call-outs")
            }
        }
    }
}

/// When splits are read out, and which paces each one says.
///
/// Distance options follow the runner's unit, so "¼ mi" becomes "250 m" in kilometers.
struct PaceCalloutSettingsView: View {
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage private var mode: PaceCalloutMode
    @AppStorage private var distance: Double
    @AppStorage private var seconds: Double
    @AppStorage private var storedPaces: String

    let sport: WorkoutSport

    init(sport: WorkoutSport) {
        self.sport = sport
        _mode = AppStorage(wrappedValue: .off, PaceCalloutSettings.key(PaceCalloutSettings.modeKey, for: sport))
        _distance = AppStorage(wrappedValue: PaceCalloutSettings.defaultDistance, PaceCalloutSettings.key(PaceCalloutSettings.distanceKey, for: sport))
        _seconds = AppStorage(wrappedValue: PaceCalloutSettings.defaultSeconds, PaceCalloutSettings.key(PaceCalloutSettings.secondsKey, for: sport))
        _storedPaces = AppStorage(wrappedValue: PaceKind.encode(PaceCalloutSettings.defaultPaceKinds(for: sport)), PaceCalloutSettings.key(PaceCalloutSettings.pacesKey, for: sport))
    }

    /// Made on the first sample, since an audio engine and a speech voice are too much to make on every redraw.
    @State private var speaker: CalloutSpeaker?

    private var paces: [PaceKind] {
        PaceKind.decode(storedPaces)
    }

    private var sample: PaceCallout? {
        PaceCallout.sample(for: PaceCalloutSettings(mode: mode, unit: unit, distance: distance, seconds: seconds, paces: paces, sport: sport))
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
                    Text(sport == .cycling ? "Hear your time or distance and speed as you ride." : "Hear your time or distance and pace as you \(sport.noun).")
                }
            }

            if mode != .off {
                Section {
                    ForEach(PaceKind.allCases) { kind in
                        Toggle(isOn: picked(kind)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.name(unit: unit))
                                Text(kind.detail(unit: unit, sport: sport))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Pace and speed")
                } footer: {
                    Text(paces.isEmpty ? "With none picked, you hear just the distance or time." : "Said in this order.")
                }

                if let sample {
                    Section {
                        Button("Hear a sample", systemImage: "speaker.wave.2") {
                            Trace.tap("Voice Call-outs", "Hear a sample")
                            let speaker = self.speaker ?? CalloutSpeaker()
                            self.speaker = speaker
                            speaker.speak(sample.spokenText)
                        }
                    } footer: {
                        Text("“\(sample.spokenText)”")
                    }
                }
            }
        }
        .navigationTitle(sport.name)
        .traceScreen("Voice Call-outs")
        .onDisappear { speaker?.stop() }
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
        PaceCalloutSettingsView(sport: .running)
    }
}
