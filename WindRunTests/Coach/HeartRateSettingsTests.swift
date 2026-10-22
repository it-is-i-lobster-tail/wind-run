//
//  HeartRateSettingsTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// IN-17: one yes or no for heart rate, with the source found from the runs.
@MainActor
struct HeartRateSettingsTests {
    func run(day: Int, source: HeartRateDevice?) -> LoggedRun {
        LoggedRun(
            start: CoachFixtures.day(day),
            movingSeconds: 45 * 60,
            meters: 8_000,
            heartRate: source.map { RunHeartRate(source: $0, coverage: 0.95, mean: 140) }
        )
    }

    @Test func settingsSavedWithAPickedSourceStayOn() throws {
        let picked = Data(#"{"device":"appleWatch","useForCoaching":false,"labMax":181}"#.utf8)
        let settings = try JSONDecoder().decode(HeartRateSettings.self, from: picked)
        #expect(settings.enabled)
        #expect(settings.device == .appleWatch)
        #expect(!settings.useForCoaching)
        #expect(settings.labMax == 181)

        let off = try JSONDecoder().decode(HeartRateSettings.self, from: Data(#"{"device":"off","useForCoaching":true}"#.utf8))
        #expect(!off.enabled)
    }

    @Test func theAnswerSurvivesASave() throws {
        let settings = HeartRateSettings(useForCoaching: true, enabled: true)
        let decoded = try JSONDecoder().decode(HeartRateSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
        #expect(decoded.enabled)
        #expect(decoded.device == .off)
    }

    @Test func theSourceComesFromTheNewestRunWithHeartRate() {
        let on = HeartRateSettings(enabled: true)
        let runs = [run(day: 1, source: .chestStrap), run(day: 3, source: .appleWatch), run(day: 5, source: nil)]
        #expect(on.detectingSource(from: runs).device == .appleWatch)
        #expect(on.detectingSource(from: runs).canCoach)
        // Before any run has heart rate, nothing is found yet and nothing can coach.
        #expect(on.detectingSource(from: [run(day: 1, source: nil)]).device == .off)
        #expect(!on.detectingSource(from: []).canCoach)
        // Earbuds are found, but never coach.
        #expect(!on.detectingSource(from: [run(day: 1, source: .earbuds)]).canCoach)
    }

    @Test func noMeansNoSourceWhateverTheRunsHad() {
        let no = HeartRateSettings(device: .appleWatch, enabled: false)
        let detected = no.detectingSource(from: [run(day: 1, source: .chestStrap)])
        #expect(detected.device == .off)
        #expect(!detected.coachingAllowed)
    }

    @Test func showOnlyNeverCoaches() {
        let showOnly = HeartRateSettings(useForCoaching: false, enabled: true)
        #expect(!showOnly.coachingAllowed)
        #expect(!showOnly.detectingSource(from: [run(day: 1, source: .chestStrap)]).canCoach)
    }

    @Test func theRestingCheckNeedsNoRunSource() {
        let calendar = CoachFixtures.calendar
        let readings = (-24 ... 3).map { RestingHeartRate(date: CoachFixtures.day($0, hour: 8), bpm: 50, device: "watch") }
            + [RestingHeartRate(date: CoachFixtures.day(4, hour: 8), bpm: 54, device: "watch"),
               RestingHeartRate(date: CoachFixtures.day(5, hour: 8), bpm: 54, device: "watch")]
        let on = HeartRateSettings(enabled: true)
        #expect(HeartRateRules.restingRaised(readings, settings: on, on: CoachFixtures.day(6), calendar: calendar))
        #expect(!HeartRateRules.restingRaised(readings, settings: .off, on: CoachFixtures.day(6), calendar: calendar))
        #expect(!HeartRateRules.restingRaised(readings, settings: HeartRateSettings(useForCoaching: false, enabled: true), on: CoachFixtures.day(6), calendar: calendar))
    }
}
