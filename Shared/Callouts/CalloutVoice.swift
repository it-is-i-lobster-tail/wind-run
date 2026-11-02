//
//  CalloutVoice.swift
//  Wind Run
//

import AVFAudio
import Foundation

/// The voice that reads call-outs: the one the runner picked, or the most natural English voice on the device.
///
/// Enhanced and Premium voices sound far smoother than the small default voice, and say the same words the
/// same way every time. Like every voice, they speak on the device. Runners download them in Settings ›
/// Accessibility › Spoken Content › Voices.
enum CalloutVoice {
    /// The picked voice's identifier, or empty for the best voice on the device.
    static let storageKey = "calloutVoice"

    /// English voices on this device, the most natural first, then by name. Novelty voices and Personal Voice
    /// are left out.
    static func available() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { voice in
                voice.language.hasPrefix("en")
                    && !voice.voiceTraits.contains(.isNoveltyVoice)
                    && !voice.voiceTraits.contains(.isPersonalVoice)
            }
            .sorted { first, second in
                if first.quality != second.quality {
                    return first.quality.rawValue > second.quality.rawValue
                }
                if first.name != second.name {
                    return first.name.localizedStandardCompare(second.name) == .orderedAscending
                }
                return first.language < second.language
            }
    }

    /// The most natural English voice on the device, in the runner's own English when there's a choice.
    ///
    /// Picks by quality first, so a downloaded Premium voice wins over the default voice of the runner's region.
    static func best(
        among voices: [AVSpeechSynthesisVoice] = available(),
        language: String = AVSpeechSynthesisVoice.currentLanguageCode()
    ) -> AVSpeechSynthesisVoice? {
        let preferred = language.hasPrefix("en") ? language : "en-US"
        guard let top = voices.first?.quality else { return AVSpeechSynthesisVoice(language: preferred) }
        let finest = voices.filter { $0.quality == top }
        if top == .default, let regional = AVSpeechSynthesisVoice(language: preferred) {
            // Without a better voice downloaded, the system's own pick for the region is the familiar one.
            return regional
        }
        return finest.first { $0.language == preferred }
            ?? finest.first { $0.language == "en-US" }
            ?? finest.first
    }

    /// The voice to speak with now: the picked one while it's still on the device, otherwise the best one.
    static func current(in defaults: UserDefaults = .standard) -> AVSpeechSynthesisVoice? {
        if let identifier = defaults.string(forKey: storageKey), !identifier.isEmpty,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            return voice
        }
        return best()
    }

    /// "Ava (US, Premium)" or "Daniel (UK)".
    static func label(for voice: AVSpeechSynthesisVoice) -> String {
        let parts = [region(of: voice.language), qualityName(voice.quality)].compactMap(\.self)
        return parts.isEmpty ? voice.name : "\(voice.name) (\(parts.joined(separator: ", ")))"
    }

    /// "Premium", "Enhanced", or nil for the default quality.
    static func qualityName(_ quality: AVSpeechSynthesisVoiceQuality) -> String? {
        switch quality {
        case .premium: "Premium"
        case .enhanced: "Enhanced"
        default: nil
        }
    }

    /// "US" for "en-US", with Great Britain shown as "UK" as runners there say it.
    private static func region(of language: String) -> String? {
        guard let code = language.split(separator: "-").dropFirst().first else { return nil }
        return code == "GB" ? "UK" : String(code)
    }
}
