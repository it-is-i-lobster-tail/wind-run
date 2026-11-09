//
//  CalloutSpeaker.swift
//  Wind Run
//

import AVFAudio
import Foundation
import OSLog

/// Reads call-outs aloud on the device, dipping any music or podcast underneath and bringing it back after.
///
/// Call-outs play from voice clips recorded into the app, joined into a line (`VoiceScript`). A line with
/// no clips for some part of it, such as an unusual step distance, is read by the system voice instead.
/// Either way it plays on the device. Nothing is sent anywhere to be spoken.
final class CalloutSpeaker: NSObject {
    /// Starting and ending the audio session can block while other apps' audio adjusts,
    /// so it happens here, in order, instead of on the main thread.
    private nonisolated static let audioQueue = DispatchQueue(label: "WindRun.CalloutSpeaker.audio")

    private let script: VoiceScript
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// The format the player is wired to the mixer with, once it has played.
    private var playerFormat: AVAudioFormat?
    private let synthesizer = AVSpeechSynthesizer()
    /// Call-outs asked for and not yet finished or cut off. The audio session ends when this reaches zero.
    private var unfinished = 0

    /// The phrases are English, so a non-English system voice would garble them.
    private static let voice: AVSpeechSynthesisVoice? = {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        return AVSpeechSynthesisVoice(language: language.hasPrefix("en") ? language : "en-US")
    }()

    init(script: VoiceScript = .bundled) {
        self.script = script
        super.init()
        synthesizer.delegate = self
        engine.attach(player)
    }

    func speak(_ text: String) {
        // The newest split is what matters, so it cuts off anything still being read.
        stop()
        unfinished += 1
        let recorded = script.pieces(for: text).flatMap { Self.audio(for: $0) }
        Task {
            if let error = await Self.onAudioQueue(Self.activateAudioSession) {
                Logger.callouts.error("Couldn't start the audio session: \(error)")
            }
            if let recorded, play(recorded) {
                Logger.callouts.debug("Playing: \(text)")
                return
            }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = Self.voice
            synthesizer.speak(utterance)
            Logger.callouts.debug("Speaking with the system voice: \(text)")
        }
    }

    /// Plays joined clips, or returns false when the audio engine can't start.
    private func play(_ buffer: AVAudioPCMBuffer) -> Bool {
        if playerFormat != buffer.format {
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            playerFormat = buffer.format
        }
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                Logger.callouts.error("Couldn't start the audio engine: \(error.localizedDescription)")
                return false
            }
        }
        // Called once the line has played, or when it's cut off.
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { @Sendable [weak self] _ in
            Task { @MainActor in self?.utteranceEnded() }
        }
        player.play()
        return true
    }

    /// The clips read from the app and joined with their pauses, or nil if one can't be read.
    private static func audio(for pieces: [VoiceScript.Piece]) -> AVAudioPCMBuffer? {
        var parts: [(audio: AVAudioPCMBuffer, pause: AVAudioFrameCount)] = []
        var format: AVAudioFormat?
        for piece in pieces {
            guard let url = VoiceScript.url(of: piece.clip),
                  let file = try? AVAudioFile(forReading: url),
                  let audio = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: audio)) != nil
            else {
                Logger.callouts.error("Missing voice clip \(piece.clip)")
                return nil
            }
            if let format, format != file.processingFormat { return nil }
            format = file.processingFormat
            parts.append((audio, AVAudioFrameCount(piece.pauseAfter * file.processingFormat.sampleRate)))
        }
        guard let format, !parts.isEmpty else { return nil }
        let total = parts.reduce(AVAudioFrameCount(0)) { $0 + $1.audio.frameLength + $1.pause }
        guard let joined = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: total),
              let output = joined.floatChannelData
        else { return nil }
        for channel in 0..<Int(format.channelCount) {
            var offset = 0
            for part in parts {
                guard let input = part.audio.floatChannelData else { return nil }
                let frames = Int(part.audio.frameLength)
                (output[channel] + offset).update(from: input[channel], count: frames)
                offset += frames
                (output[channel] + offset).update(repeating: 0, count: Int(part.pause))
                offset += Int(part.pause)
            }
        }
        joined.frameLength = total
        return joined
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        // Stopping calls the playing line's completion, which counts it as ended.
        if playerFormat != nil {
            player.stop()
        }
    }

    fileprivate func utteranceEnded() {
        unfinished = max(0, unfinished - 1)
        guard unfinished == 0 else { return }
        // The session can't end while the engine is still running, and the music would stay ducked.
        if engine.isRunning {
            engine.stop()
        }
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
