//
//  PaceCalloutSplitTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// Where a split's end is placed between two updates, for distance and for time.
@MainActor
struct PaceCalloutSplitTests {
    @Test func distanceSplitEndsBetweenTwoFixes() {
        var tracker = PaceCalloutTracker(trigger: .distance(meters: 1_000), unit: .kilometers)
        #expect(tracker.update(elapsed: 100, meters: 900) == nil)
        // 1,000 m is halfway between the fixes, so it was reached at 120 s.
        let callout = tracker.update(elapsed: 140, meters: 1_100)

        #expect(callout?.mark == .distance(meters: 1_000))
        #expect(callout?.pace(.split) == 120)
    }

    @Test func timeSplitEndsBetweenTwoTicks() {
        var tracker = PaceCalloutTracker(trigger: .time(seconds: 60), unit: .kilometers)
        #expect(tracker.update(elapsed: 50, meters: 200) == nil)
        // 60 s is halfway between the ticks, so the runner had covered 250 m.
        let callout = tracker.update(elapsed: 70, meters: 300)

        #expect(callout?.mark == .time(seconds: 60))
        #expect(callout?.pace(.split) == 240)
    }

    @Test func theNextSplitStartsWhereTheLastEnded() {
        var tracker = PaceCalloutTracker(trigger: .time(seconds: 60), unit: .kilometers)
        _ = tracker.update(elapsed: 60, meters: 250)
        let second = tracker.update(elapsed: 120, meters: 450)

        // 200 m in the second minute.
        #expect(second?.mark == .time(seconds: 120))
        #expect(second?.pace(.split) == 300)
    }

    @Test func averageStaysMeasuredFromTheRunsStartAfterResuming() {
        var tracker = PaceCalloutTracker(trigger: .distance(meters: 1_000), unit: .kilometers, paces: [.split, .average])
        tracker.resume(elapsed: 400, meters: 2_000)
        let callout = tracker.update(elapsed: 900, meters: 3_000)

        #expect(callout?.mark == .distance(meters: 3_000))
        // The split is measured from where the run was picked up again, the average from the start.
        #expect(callout?.pace(.split) == 500)
        #expect(callout?.pace(.average) == 300)
    }
}
