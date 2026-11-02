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
    /// Starting and ending the audio session can block while other apps' audio adjusts,
    /// so it happens here, in order, instead of on the main thread.
    private nonisolated static let audioQueue = DispatchQueue(label: "WindRun.CalloutSpeaker.audio")

    private let synthesizer = AVSpeechSynthesizer()
    /// Call-outs asked for and not yet finished or cut off. The audio session ends when this reaches zero.
    private var unfinished = 0

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
        unfinished += 1
        Task {
            if let error = await Self.onAudioQueue(Self.activateAudioSession) {
                Logger.callouts.error("Couldn't start the audio session: \(error)")
            }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = Self.voice
            synthesizer.speak(utterance)
            Logger.callouts.debug("Speaking: \(text)")
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    fileprivate func utteranceEnded() {
        unfinished = max(0, unfinished - 1)
        guard unfinished == 0 else { return }
        Task {
            if let error = await Self.onAudioQueue(Self.deactivateAudioSession) {
                Logger.callouts.debug("Couldn't end the audio session: \(error)")
            }
        }
    }

    /// Runs audio session work on `audioQueue` and returns its error message, if any.
    private nonisolated static func onAudioQueue(_ work: @escaping @Sendable () -> String?) async -> String? {
        await withCheckedContinuation { continuation in
            audioQueue.async { continuation.resume(returning: work()) }
        }
    }

    private nonisolated static func activateAudioSession() -> String? {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try session.setActive(true)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private nonisolated static func deactivateAudioSession() -> String? {
        do {
            // Lets ducked music come back up to full volume.
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

extension CalloutSpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceEnded() }
    }
}
