//
//  CalloutSpeaker.swift
//  Wind Run
//

import AVFAudio
import Foundation
import OSLog

/// Reads call-outs aloud on the device, dipping any music or podcast underneath and bringing it back after.
///
/// Speech is made on the device. Nothing is sent anywhere to be spoken.
final class CalloutSpeaker: NSObject {
    private let synthesizer = AVSpeechSynthesizer()

    /// The phrases are English, so a non-English system voice would garble them.
    private static let voice: AVSpeechSynthesisVoice? = {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        return AVSpeechSynthesisVoice(language: language.hasPrefix("en") ? language : "en-US")
    }()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        // The newest split is what matters, so it cuts off anything still being read.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        activateAudioSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice
        synthesizer.speak(utterance)
        Logger.callouts.debug("Speaking: \(text)")
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try session.setActive(true)
        } catch {
            Logger.callouts.error("Couldn't start the audio session: \(error.localizedDescription)")
        }
    }

    fileprivate func deactivateAudioSession() {
        guard !synthesizer.isSpeaking else { return }
        do {
            // Lets ducked music come back up to full volume.
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            Logger.callouts.debug("Couldn't end the audio session: \(error.localizedDescription)")
        }
    }
}

extension CalloutSpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.deactivateAudioSession() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.deactivateAudioSession() }
    }
}
