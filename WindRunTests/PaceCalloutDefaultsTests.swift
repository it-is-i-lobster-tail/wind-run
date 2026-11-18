//
//  PaceCalloutDefaultsTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

@MainActor
struct PaceCalloutDefaultsTests {
    @Test func storedDefaultIsTheSplit() {
        // The value @AppStorage writes and reads, which must not change.
        #expect(PaceCalloutSettings.defaultPaces == "split")
        #expect(PaceKind.decode(PaceCalloutSettings.defaultPaces) == PaceCalloutSettings.defaultPaceKinds)
    }

    @Test func settingsAndTrackerStartWithTheSamePaces() {
        let settings = PaceCalloutSettings(mode: .distance, unit: .kilometers)
        let tracker = PaceCalloutTracker(trigger: .distance(meters: 1_000), unit: .kilometers)
        #expect(settings.paces == [.split])
        #expect(tracker.paces == settings.paces)
    }
}

@MainActor
struct PaceCalloutSummaryTests {
    @Test func rowSummarySaysHowOften() {
        #expect(PaceCalloutSettings.summary(mode: .off, distance: 1, seconds: 300, unit: .miles) == "Off")
        #expect(PaceCalloutSettings.summary(mode: .distance, distance: 0.25, seconds: 300, unit: .miles) == "Every ¼ mi")
        #expect(PaceCalloutSettings.summary(mode: .distance, distance: 0.25, seconds: 300, unit: .kilometers) == "Every 250 m")
        #expect(PaceCalloutSettings.summary(mode: .time, distance: 1, seconds: 300, unit: .kilometers) == "Every 5 min")
        #expect(PaceCalloutSettings.summary(mode: .time, distance: 1, seconds: 30, unit: .miles) == "Every 30 sec")
    }
}
