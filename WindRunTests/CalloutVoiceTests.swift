//
//  CalloutVoiceTests.swift
//  Wind Run Tests
//

import AVFAudio
import Foundation
import Testing
@testable import WindRun

@MainActor
struct CalloutVoiceTests {
    @Test func listsOnlyEnglishVoicesBestFirst() {
        let voices = CalloutVoice.available()
        #expect(voices.allSatisfy { $0.language.hasPrefix("en") })
        #expect(voices.allSatisfy { !$0.voiceTraits.contains(.isNoveltyVoice) })
        let qualities = voices.map(\.quality.rawValue)
        #expect(qualities == qualities.sorted(by: >))
    }

    @Test func automaticIsAnEnglishVoiceOfTheBestQualityOnTheDevice() throws {
        let voices = CalloutVoice.available()
        // A test machine may have no voices installed; there's nothing to pick from then.
        guard !voices.isEmpty else { return }
        let best = try #require(CalloutVoice.best(among: voices, language: "fr-FR"))
        #expect(best.language.hasPrefix("en"))
        if let top = voices.first?.quality, top != .default {
            #expect(best.quality == top)
        }
    }

    @Test func aVoiceNoLongerOnTheDeviceFallsBackToAutomatic() throws {
        let suite = "CalloutVoiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        defaults.set("com.example.voice.gone", forKey: CalloutVoice.storageKey)
        #expect(CalloutVoice.current(in: defaults)?.identifier == CalloutVoice.best()?.identifier)

        defaults.set("", forKey: CalloutVoice.storageKey)
        #expect(CalloutVoice.current(in: defaults)?.identifier == CalloutVoice.best()?.identifier)
    }

    @Test func aPickedVoiceIsUsed() throws {
        let suite = "CalloutVoiceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        guard let voice = CalloutVoice.available().last else { return }

        defaults.set(voice.identifier, forKey: CalloutVoice.storageKey)
        #expect(CalloutVoice.current(in: defaults)?.identifier == voice.identifier)
    }

    @Test func theVoiceSyncsWithTheOtherSettings() {
        #expect(CloudSettings.keys.contains(CalloutVoice.storageKey))
    }

    @Test func qualityNames() {
        #expect(CalloutVoice.qualityName(.premium) == "Premium")
        #expect(CalloutVoice.qualityName(.enhanced) == "Enhanced")
        #expect(CalloutVoice.qualityName(.default) == nil)
    }
}
