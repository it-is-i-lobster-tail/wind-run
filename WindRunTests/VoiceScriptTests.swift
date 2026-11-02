//
//  VoiceScriptTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

@MainActor
struct VoiceScriptTests {
    private let script = VoiceScript.bundled

    private func clips(_ text: String) -> [String]? {
        script.pieces(for: text)?.map(\.clip)
    }

    @Test func everyListedClipShipsWithTheApp() throws {
        let url = try #require(Bundle.main.url(forResource: "VoiceClips", withExtension: "json"))
        let listed = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        #expect(listed.count > 700)
        let missing = listed.keys.filter { VoiceScript.url(of: $0) == nil }
        #expect(missing.isEmpty)
    }

    @Test func wholeLinesPlayAsOneClip() {
        #expect(script.pieces(for: "Paused.") == [VoiceScript.Piece(clip: "line_paused", pauseAfter: 0)])
        #expect(clips("Resumed.") == ["line_resumed"])
    }

    @Test func splitIsJoinedFromPieces() {
        let pieces = script.pieces(for: "1 kilometer, pace 6 minutes per kilometer.")
        #expect(pieces == [
            VoiceScript.Piece(clip: "km_1000m_mid", pauseAfter: VoiceScript.pauseAtPunctuation),
            VoiceScript.Piece(clip: "pace_6min", pauseAfter: VoiceScript.pauseWithin),
            VoiceScript.Piece(clip: "per_km", pauseAfter: 0),
        ])
    }

    @Test func timeSplitsAndSeconds() {
        #expect(clips("1 hour 5 minutes, pace 5 minutes 3 seconds per kilometer.") == [
            "hour_1_mid", "min_5_mid", "pace_5min", "sec_3_mid", "per_km",
        ])
        #expect(clips("Quarter mile, pace 2 minutes 13 seconds per mile.") == [
            "mi_q1_mid", "pace_2min", "sec_13_mid", "per_mi",
        ])
        #expect(clips("1 minute.") == ["min_1_end"])
    }

    @Test func morePacesUseTheirOwnLeadIns() {
        #expect(clips("1 kilometer, pace 6 minutes per kilometer, average pace 5 minutes 30 seconds per kilometer.") == [
            "km_1000m_mid", "pace_6min", "per_km_mid", "avg_pace_5min", "sec_30_mid", "per_km",
        ])
        #expect(clips("5 minutes, current pace 4 minutes 10 seconds per kilometer.") == [
            "min_5_mid", "cur_pace_4min", "sec_10_mid", "per_km",
        ])
        #expect(clips("2 miles, last mile pace 8 minutes per mile.") == [
            "mi_q8_mid", "lastmi_pace_8min", "per_mi",
        ])
    }

    @Test func slowPacesSayPaceOnItsOwn() {
        #expect(clips("1 kilometer, pace 25 minutes per kilometer.") == [
            "km_1000m_mid", "pace", "min_25_mid", "per_km",
        ])
    }

    @Test func anythingWithoutAClipGoesToTheSystemVoice() {
        #expect(script.pieces(for: "Work, 1.35 kilometers.") == nil)
        #expect(script.pieces(for: "") == nil)
    }

    @Test func picksTheFormForWhereThePieceFalls() {
        let script = VoiceScript(clips: [
            "mile_mid": "1 mile,",
            "mile_end": "1 mile.",
            "pace": "pace 8 minutes,",
            "per": "per mile.",
        ])
        #expect(script.pieces(for: "1 mile.")?.map(\.clip) == ["mile_end"])
        #expect(script.pieces(for: "1 mile, pace 8 minutes per mile.")?.map(\.clip) == ["mile_mid", "pace", "per"])
        // Only one form recorded: it's used either way.
        #expect(script.pieces(for: "Pace 8 minutes.")?.map(\.clip) == ["pace"])
    }

    @Test func everySplitAMarathonRunnerHearsIsRecorded() {
        for unit in DistanceUnit.allCases {
            for quarter in 1...(unit == .miles ? 104 : 168) {
                let mark = PaceCallout.Mark.distance(meters: Double(quarter) * unit.meters / 4)
                for pace in stride(from: 180.0, through: 900, by: 37) {
                    let readings = PaceKind.allCases.map { PaceReading(kind: $0, secondsPerKilometer: pace) }
                    let text = PaceCallout(mark: mark, readings: readings, unit: unit).spokenText
                    #expect(script.pieces(for: text) != nil, "\(text)")
                }
            }
        }
        for minutes in 1...300 {
            let text = PaceCallout(mark: .time(seconds: Double(minutes) * 60), secondsPerKilometer: 303, unit: .kilometers).spokenText
            #expect(script.pieces(for: text) != nil, "\(text)")
        }
    }
}
