//
//  AutoPauseSignsTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The signs auto-pause traces, which are the same signs that decide it.
@MainActor
struct AutoPauseSignsTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test func theSignsSayWhatEachSensorSaid() {
        var autoPause = AutoPause(usesMotion: true, start: start)
        autoPause.footsteps(at: at(10), cadence: 170)
        autoPause.fix(speed: 0.2, at: at(15))
        #expect(autoPause.signs(at: at(12)) == AutoPause.Signs(usesMotion: true, stepsQuiet: false, sensorStill: false, gpsSpeed: 0.2, secondsSinceStep: 2))
        #expect(autoPause.signs(at: at(15)) == AutoPause.Signs(usesMotion: true, stepsQuiet: true, sensorStill: false, gpsSpeed: 0.2, secondsSinceStep: 5))
        // The fix is 5 s old at 20 s, still fresh, and stale a second later.
        #expect(autoPause.signs(at: at(20)).gpsSpeed == 0.2)
        #expect(autoPause.signs(at: at(21)).gpsSpeed == nil)
        autoPause.activity(.stationary, at: at(11))
        #expect(autoPause.signs(at: at(12)).sensorStill)
    }

    @Test func quietStepsAndSlowGPSPauseAfterTheHold() {
        var autoPause = AutoPause(usesMotion: true, start: start)
        autoPause.footsteps(at: at(10), cadence: 170)
        autoPause.fix(speed: 0.2, at: at(14))
        // At 14 s the steps have been quiet for 4 s and GPS is slow, so the 2 s hold starts.
        #expect(autoPause.signs(at: at(14)).stepsQuiet)
        #expect(autoPause.check(at: at(14), isPaused: false) == nil)
        autoPause.fix(speed: 0.2, at: at(16))
        #expect(autoPause.check(at: at(16), isPaused: false) == .pause)
    }

    @Test func withoutMotionOnlyGPSCounts() {
        var autoPause = AutoPause(usesMotion: false, start: start)
        autoPause.fix(speed: 0.2, at: at(10))
        // The steps have been quiet since the start, but without motion only GPS speed decides.
        #expect(autoPause.signs(at: at(10)).stepsQuiet)
        #expect(autoPause.check(at: at(10), isPaused: false) == nil)
        #expect(autoPause.check(at: at(12), isPaused: false) == .pause)
    }
}
