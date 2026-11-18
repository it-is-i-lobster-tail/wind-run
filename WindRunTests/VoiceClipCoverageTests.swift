//
//  VoiceClipCoverageTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// Every call-out a runner can pick in Settings has recorded clips, so none falls back to the system voice.
@MainActor
struct VoiceClipCoverageTests {
    private let script = VoiceScript.bundled

    @Test func everyTimeSplitUpToFiveHoursIsRecorded() {
        var checked: Set<String> = []
        for unit in DistanceUnit.allCases {
            for interval in PaceCalloutSettings.secondsOptions {
                for split in 1...Int(5 * 3600 / interval) {
                    let mark = PaceCallout.Mark.time(seconds: Double(split) * interval)
                    for pace in stride(from: 180.0, through: 900, by: 111) {
                        let readings = PaceKind.allCases.map { PaceReading(kind: $0, secondsPerKilometer: pace) }
                        let text = PaceCallout(mark: mark, readings: readings, unit: unit).spokenText
                        guard checked.insert(text).inserted else { continue }
                        #expect(script.pieces(for: text) != nil, "\(text)")
                    }
                }
            }
        }
    }

    @Test func everySettingsSampleIsRecorded() throws {
        for unit in DistanceUnit.allCases {
            for distance in PaceCalloutSettings.distanceOptions {
                let settings = PaceCalloutSettings(mode: .distance, unit: unit, distance: distance, paces: PaceKind.allCases)
                let text = try #require(PaceCallout.sample(for: settings)).spokenText
                #expect(script.pieces(for: text) != nil, "\(text)")
            }
            for seconds in PaceCalloutSettings.secondsOptions {
                let settings = PaceCalloutSettings(mode: .time, unit: unit, seconds: seconds, paces: PaceKind.allCases)
                let text = try #require(PaceCallout.sample(for: settings)).spokenText
                #expect(script.pieces(for: text) != nil, "\(text)")
            }
        }
    }
}
