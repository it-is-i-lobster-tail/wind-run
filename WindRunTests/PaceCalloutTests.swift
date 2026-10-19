//
//  PaceCalloutTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

@MainActor
struct PaceCalloutTrackerTests {
    private let mile = DistanceUnit.miles.meters

    /// Feeds a steady run, one update a second, and collects what would be said.
    private func run(
        _ tracker: inout PaceCalloutTracker,
        secondsPerMile: Double,
        for seconds: Int,
        from start: (elapsed: Double, meters: Double) = (0, 0)
    ) -> [PaceCallout] {
        var callouts: [PaceCallout] = []
        for second in 1...seconds {
            let elapsed = start.elapsed + Double(second)
            let meters = start.meters + Double(second) / secondsPerMile * mile
            if let callout = tracker.update(elapsed: elapsed, meters: meters) {
                callouts.append(callout)
            }
        }
        return callouts
    }

    @Test func quarterMileCallsOutThatSplitsPace() throws {
        var tracker = PaceCalloutTracker(trigger: .distance(meters: mile / 4), unit: .miles)
        let callouts = run(&tracker, secondsPerMile: 133, for: 40)

        let callout = try #require(callouts.first)
        #expect(callouts.count == 1)
        #expect(callout.mark == .distance(meters: mile / 4))
        #expect(callout.spokenText == "Quarter mile, pace 2 minutes 13 seconds per mile.")
    }

    @Test func fiveMinutesCallsOutThatSplitsPace() {
        var tracker = PaceCalloutTracker(trigger: .time(seconds: 300), unit: .miles)
        let callouts = run(&tracker, secondsPerMile: 513, for: 610)

        #expect(callouts.map(\.spokenText) == [
            "5 minutes, pace 8 minutes 33 seconds per mile.",
            "10 minutes, pace 8 minutes 33 seconds per mile.",
        ])
    }

    @Test func eachCalloutIsItsOwnSplitNotTheAverage() {
        var tracker = PaceCalloutTracker(trigger: .distance(meters: 1_000), unit: .kilometers)
        // A 6:00 kilometer, then a 4:00 one. The average would be 5:00.
        _ = tracker.update(elapsed: 0, meters: 0)
        let first = tracker.update(elapsed: 360, meters: 1_000)
        let second = tracker.update(elapsed: 600, meters: 2_000)

        #expect(first?.spokenText == "1 kilometer, pace 6 minutes per kilometer.")
        #expect(second?.spokenText == "2 kilometers, pace 4 minutes per kilometer.")
    }

    @Test func splitEndIsPlacedBetweenFixes() {
        var tracker = PaceCalloutTracker(trigger: .distance(meters: 1_000), unit: .kilometers)
        _ = tracker.update(elapsed: 290, meters: 950)
        // Clock ticks without a new fix don't move where the split is measured from.
        _ = tracker.update(elapsed: 299, meters: 950)
        let callout = tracker.update(elapsed: 310, meters: 1_050)

        // Halfway between the fixes at 290 s and 310 s.
        #expect(callout?.secondsPerKilometer == 300)
    }

    @Test func aGPSJumpOnlyCallsOutTheNewestSplit() {
        var tracker = PaceCalloutTracker(trigger: .distance(meters: 500), unit: .kilometers)
        _ = tracker.update(elapsed: 0, meters: 0)
        let callout = tracker.update(elapsed: 450, meters: 1_600)

        #expect(callout?.mark == .distance(meters: 1_500))
        #expect(tracker.update(elapsed: 460, meters: 1_700) == nil)
    }

    @Test func standingStillSaysJustTheTime() {
        var tracker = PaceCalloutTracker(trigger: .time(seconds: 60), unit: .kilometers)
        var callout: PaceCallout?
        for second in 1...60 {
            callout = tracker.update(elapsed: Double(second), meters: 0) ?? callout
        }

        #expect(callout?.spokenText == "1 minute.")
    }

    @Test func lateFixDoesntConfuseTheClock() {
        var tracker = PaceCalloutTracker(trigger: .time(seconds: 60), unit: .kilometers)
        _ = tracker.update(elapsed: 59.9, meters: 299)
        // A fix stamped just before the last tick is skipped; the next tick reads its distance.
        #expect(tracker.update(elapsed: 59.5, meters: 300) == nil)
        let callout = tracker.update(elapsed: 60.9, meters: 304)

        #expect(callout?.mark == .time(seconds: 60))
        #expect(callout?.spokenText == "1 minute, pace 3 minutes 20 seconds per kilometer.")
    }

    @Test func offMeansNoTracker() {
        #expect(PaceCalloutTracker(settings: PaceCalloutSettings(mode: .off, unit: .miles)) == nil)
    }
}

@MainActor
struct PaceCalloutSettingsTests {
    private func defaults() -> UserDefaults {
        let name = "PaceCalloutSettingsTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    @Test func defaultsToOff() {
        let settings = PaceCalloutSettings.current(in: defaults())
        #expect(settings.mode == .off)
        #expect(settings.trigger == nil)
    }

    @Test func distanceIsInTheRunnersUnit() {
        let defaults = defaults()
        defaults.set(PaceCalloutMode.distance.rawValue, forKey: PaceCalloutSettings.modeKey)
        defaults.set(DistanceUnit.miles.rawValue, forKey: DistanceUnit.storageKey)
        defaults.set(0.25, forKey: PaceCalloutSettings.distanceKey)

        #expect(PaceCalloutSettings.current(in: defaults).trigger == .distance(meters: 402.336))

        defaults.set(DistanceUnit.kilometers.rawValue, forKey: DistanceUnit.storageKey)
        #expect(PaceCalloutSettings.current(in: defaults).trigger == .distance(meters: 250))
    }

    @Test func timeUsesSeconds() {
        let defaults = defaults()
        defaults.set(PaceCalloutMode.time.rawValue, forKey: PaceCalloutSettings.modeKey)
        defaults.set(600.0, forKey: PaceCalloutSettings.secondsKey)

        #expect(PaceCalloutSettings.current(in: defaults).trigger == .time(seconds: 600))
    }

    @Test func optionNames() {
        #expect(PaceCalloutSettings.distanceName(0.25, unit: .miles) == "¼ mi")
        #expect(PaceCalloutSettings.distanceName(2, unit: .miles) == "2 mi")
        #expect(PaceCalloutSettings.distanceName(0.25, unit: .kilometers) == "250 m")
        #expect(PaceCalloutSettings.distanceName(1, unit: .kilometers) == "1 km")
        #expect(PaceCalloutSettings.secondsName(30) == "30 sec")
        #expect(PaceCalloutSettings.secondsName(300) == "5 min")
    }
}

@MainActor
struct SpokenFormatTests {
    private let mile = DistanceUnit.miles.meters

    @Test func miles() {
        #expect(SpokenFormat.distance(mile * 0.25, unit: .miles) == "quarter mile")
        #expect(SpokenFormat.distance(mile * 0.5, unit: .miles) == "half mile")
        #expect(SpokenFormat.distance(mile * 0.75, unit: .miles) == "three quarters of a mile")
        #expect(SpokenFormat.distance(mile / 4 * 4, unit: .miles) == "1 mile")
        #expect(SpokenFormat.distance(mile * 1.25, unit: .miles) == "1 and a quarter miles")
        #expect(SpokenFormat.distance(mile * 2.5, unit: .miles) == "2 and a half miles")
        #expect(SpokenFormat.distance(mile * 3, unit: .miles) == "3 miles")
    }

    @Test func kilometers() {
        #expect(SpokenFormat.distance(250, unit: .kilometers) == "250 meters")
        #expect(SpokenFormat.distance(1_000, unit: .kilometers) == "1 kilometer")
        #expect(SpokenFormat.distance(1_500, unit: .kilometers) == "1.5 kilometers")
        #expect(SpokenFormat.distance(2_250, unit: .kilometers) == "2.25 kilometers")
        #expect(SpokenFormat.distance(10_000, unit: .kilometers) == "10 kilometers")
    }

    @Test func durations() {
        #expect(SpokenFormat.duration(30) == "30 seconds")
        #expect(SpokenFormat.duration(60) == "1 minute")
        #expect(SpokenFormat.duration(90) == "1 minute 30 seconds")
        #expect(SpokenFormat.duration(3_900) == "1 hour 5 minutes")
    }

    @Test func paces() {
        #expect(SpokenFormat.pace(300, unit: .kilometers) == "5 minutes per kilometer")
        #expect(SpokenFormat.pace(300, unit: .miles) == "8 minutes 3 seconds per mile")
        #expect(SpokenFormat.pace(61, unit: .kilometers) == "1 minute 1 second per kilometer")
        #expect(SpokenFormat.pace(nil, unit: .kilometers) == nil)
        // Slower than an hour per unit isn't a pace.
        #expect(SpokenFormat.pace(4_000, unit: .kilometers) == nil)
    }
}
