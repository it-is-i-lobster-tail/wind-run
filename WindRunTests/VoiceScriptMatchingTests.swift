//
//  VoiceScriptMatchingTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// How words are matched to clips, with small scripts made for each rule.
@MainActor
struct VoiceScriptMatchingTests {
    @Test func typographicApostrophesMatchStraightOnes() {
        let script = VoiceScript(clips: ["a": "Don't stop."])
        #expect(script.pieces(for: "Don\u{2019}t stop.")?.map(\.clip) == ["a"])
    }

    @Test func caseDoesntMatter() {
        let script = VoiceScript(clips: ["p": "Paused."])
        #expect(script.pieces(for: "PAUSED.")?.map(\.clip) == ["p"])
    }

    @Test func aLinePrefixMakesAWholeLine() {
        let script = VoiceScript(clips: ["line_x": "Go"])
        #expect(script.pieces(for: "go") == [VoiceScript.Piece(clip: "line_x", pauseAfter: 0)])
    }

    @Test func punctuationInsideAClipMakesAWholeLine() {
        let script = VoiceScript(clips: ["w": "Work, go."])
        #expect(script.pieces(for: "Work, go.")?.map(\.clip) == ["w"])
        // A line is only ever played whole, so part of it has no clip.
        #expect(script.pieces(for: "Work,") == nil)
    }

    @Test func aPeriodInsideANumberStays() {
        let script = VoiceScript(clips: ["k": "1.5 kilometers."])
        #expect(script.pieces(for: "1.5 kilometers.")?.map(\.clip) == ["k"])
        #expect(script.pieces(for: "1 kilometers.") == nil)
    }

    @Test func piecesThatRunOnPauseBriefly() {
        let script = VoiceScript(clips: ["a": "pace 5 minutes", "b": "20 seconds."])
        #expect(script.pieces(for: "pace 5 minutes 20 seconds.") == [
            VoiceScript.Piece(clip: "a", pauseAfter: VoiceScript.pauseWithin),
            VoiceScript.Piece(clip: "b", pauseAfter: 0),
        ])
    }

    @Test func piecesEndingInACommaPauseLonger() {
        let script = VoiceScript(clips: ["a": "1 mile,", "b": "pace 8 minutes."])
        #expect(script.pieces(for: "1 mile, pace 8 minutes.") == [
            VoiceScript.Piece(clip: "a", pauseAfter: VoiceScript.pauseAtPunctuation),
            VoiceScript.Piece(clip: "b", pauseAfter: 0),
        ])
    }
}
