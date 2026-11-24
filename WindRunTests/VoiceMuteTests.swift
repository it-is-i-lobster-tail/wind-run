//
//  VoiceMuteTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// The run screen's mute button: the voice goes quiet for the run, and only that run.
@MainActor
struct VoiceMuteTests {
    private let container = WindRunSchema.makeContainer(inMemory: true)

    @Test func aNewRunStartsWithTheVoiceOn() {
        let recorder = RunRecorder(modelContext: container.mainContext)
        #expect(recorder.isVoiceMuted == false)
    }

    @Test func mutingAndUnmutingFlipsTheRunsVoice() {
        let recorder = RunRecorder(modelContext: container.mainContext)
        recorder.setVoiceMuted(true)
        #expect(recorder.isVoiceMuted)
        // Asking twice changes nothing.
        recorder.setVoiceMuted(true)
        #expect(recorder.isVoiceMuted)
        recorder.setVoiceMuted(false)
        #expect(recorder.isVoiceMuted == false)
    }

    @Test func aRunWithNothingToSayOffersNoMuteButton() {
        let recorder = RunRecorder(modelContext: container.mainContext)
        // Nothing has started, so there are no call-outs, steps or cues to mute.
        #expect(recorder.speaksAloud == false)
    }

    @Test func aCoachCueCountsAsSomethingToSay() {
        let recorder = RunRecorder(modelContext: container.mainContext)
        recorder.spokenCue = { _, _, _ in nil }
        #expect(recorder.speaksAloud)
    }
}
