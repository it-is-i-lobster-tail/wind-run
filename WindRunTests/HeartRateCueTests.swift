//
//  HeartRateCueTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The in-run heart-rate cue (PZ-12): the easy-run ceiling, the 60-second hold, the device margin, the quiet start on
/// a watch, and re-arming.
@MainActor
struct HeartRateCueTests {
    /// Feeds the tracker one reading a second and returns the seconds at which the cue played.
    private func cues(_ tracker: inout HeartRateCueTracker, from start: Int = 0, to end: Int, beatsPerMinute: (Int) -> Double?) -> [Int] {
        var played: [Int] = []
        for second in start...end where tracker.update(elapsed: TimeInterval(second), meters: Double(second) * 2.5, beatsPerMinute: beatsPerMinute(second)) {
            played.append(second)
        }
        return played
    }

    // MARK: The ceiling

    @Test func theEasyCeilingComesFromTheEstimateOrALowerLabMaximum() {
        // Age 18: an estimated max of 195 and an easy ceiling of 146. A lab maximum of 180 lowers it to 135.
        #expect(HeartRateZones.estimated(age: BuildRunStart.estimateAge).easyCeiling == 146)
        #expect(HeartRateZones.estimated(age: BuildRunStart.estimateAge, labMax: 180).easyCeiling == 135)
        #expect(HeartRateZones.estimated(age: BuildRunStart.estimateAge, labMax: 200).easyCeiling == 146)
    }

    // MARK: Trigger

    @Test func theCuePlaysAfterAMinuteOver() {
        var tracker = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: 135)], device: .chestStrap)
        // Over from second 10: the cue plays at second 70, not before.
        let played = cues(&tracker, to: 100) { $0 >= 10 ? 145 : 120 }
        #expect(played == [70])
    }

    @Test func aDipUnderTheMarginRestartsTheHold() {
        var tracker = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: 135)], device: .chestStrap)
        // A strap's margin is 5: 139 is over the ceiling but not over the margin.
        let played = cues(&tracker, to: 150) { second in
            if second < 40 { return 145 }
            if second < 50 { return 139 }
            return 145
        }
        #expect(played == [110])
    }

    @Test func theMarginDependsOnTheDevice() {
        // 142 is 7 over: past a strap's 5 but inside a watch's 10.
        var strap = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: 135)], device: .chestStrap)
        var watch = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: 135)], device: .appleWatch)
        #expect(!cues(&strap, from: 400, to: 500) { _ in 142 }.isEmpty)
        #expect(cues(&watch, from: 400, to: 500) { _ in 142 }.isEmpty)
    }

    @Test func aWatchStaysQuietForTheFirstFiveMinutes() {
        var tracker = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: 135)], device: .appleWatch)
        let played = cues(&tracker, to: 400) { _ in 160 }
        #expect(played == [360])
    }

    @Test func noReadingNeverCues() {
        var tracker = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: 135)], device: .chestStrap)
        #expect(cues(&tracker, to: 200) { _ in nil }.isEmpty)
    }

    @Test func itReArmsUnderTheCeilingAndWaitsThreeMinutes() {
        var tracker = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: 135)], device: .chestStrap)
        let played = cues(&tracker, to: 600) { second in
            switch second {
            case ..<100: 145
            // Back under the ceiling, which re-arms it.
            case 100..<110: 130
            // Over again: a minute passes at 170, but only 3 minutes after the first cue may it play.
            case 110..<500: 145
            default: 130
            }
        }
        #expect(played == [60, 240])
    }

    @Test func stayingOverDoesntRepeatWithoutComingBackUnder() {
        var tracker = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: 135)], device: .chestStrap)
        #expect(cues(&tracker, to: 900) { _ in 145 } == [60])
    }

    @Test func onlyPartsWithACeilingCue() {
        // A 2-minute warm-up with no ceiling, then a part with one, counted from its second minute.
        let parts = [
            HeartRateCue.Part(span: .seconds(120), ceiling: nil),
            HeartRateCue.Part(span: .seconds(600), ceiling: 160, delay: 60),
        ]
        var tracker = HeartRateCueTracker(parts: parts, device: .chestStrap)
        let played = cues(&tracker, to: 800) { _ in 175 }
        // The work part starts at 120, cues from 180, and the hold ends at 240. After the part ends, nothing.
        #expect(played == [240])
    }

    @Test func distancePartsEndByDistance() {
        let parts = [
            HeartRateCue.Part(span: .meters(500), ceiling: nil),
            HeartRateCue.Part(span: .toEnd, ceiling: 135),
        ]
        var tracker = HeartRateCueTracker(parts: parts, device: .chestStrap)
        // At 2.5 m a second, 500 m ends at second 200; the cue plays a minute later.
        #expect(cues(&tracker, to: 400) { _ in 150 } == [260])
    }
}
