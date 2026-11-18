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
