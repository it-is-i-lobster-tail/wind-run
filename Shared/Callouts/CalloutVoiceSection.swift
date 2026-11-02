//
//  CalloutVoiceSection.swift
//  Wind Run
//

import AVFAudio
import SwiftUI

/// Which voice reads call-outs and workout steps, shared by the iPhone and watch settings.
///
/// Each device lists its own voices, since what's downloaded differs between them.
struct CalloutVoiceSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CalloutVoice.storageKey) private var identifier = ""
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var speaker = CalloutSpeaker()

    /// What Automatic speaks with right now.
    private var automaticName: String? {
        CalloutVoice.best(among: voices).map { $0.name }
    }

    var body: some View {
        Section {
            Picker("Voice", selection: $identifier) {
                Text(automaticName.map { "Automatic (\($0))" } ?? "Automatic").tag("")
                ForEach(voices, id: \.identifier) { voice in
                    Text(CalloutVoice.label(for: voice)).tag(voice.identifier)
                }
                // A voice picked on another device, or since removed, stays selectable until changed.
                if !identifier.isEmpty, !voices.contains(where: { $0.identifier == identifier }) {
                    Text("Not on this device").tag(identifier)
                }
            }

            Button("Hear the voice", systemImage: "speaker.wave.2") {
                speaker.speak(sampleText)
            }
        } header: {
            Text("Voice")
        } footer: {
            Text(footer)
        }
        .task { voices = CalloutVoice.available() }
        .onChange(of: scenePhase) { _, phase in
            // Voices downloaded in Settings while the app was in the background show up on return.
            if phase == .active { voices = CalloutVoice.available() }
        }
        .onDisappear { speaker.stop() }
    }

    /// A split call-out when those are on, otherwise a workout step.
    private var sampleText: String {
        PaceCallout.sample(for: .current())?.spokenText ?? "Warm up, 10 minutes."
    }

    private var footer: String {
        #if os(watchOS)
        return "Reads your call-outs and workout steps. Automatic picks the most natural voice on this watch."
        #else
        let hasNatural = voices.contains { $0.quality != .default }
        let tip = hasNatural
            ? "More voices are in Settings › Accessibility › Spoken Content › Voices."
            : "For a smoother, more natural voice, download an Enhanced or Premium English voice in Settings › Accessibility › Spoken Content › Voices."
        return "Reads your call-outs and workout steps, on your iPhone. Automatic picks the most natural voice you have. \(tip)"
        #endif
    }
}
