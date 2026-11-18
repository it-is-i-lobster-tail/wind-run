//
//  RunRecorderLogicTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The recorder's pure pieces: the climb threshold, the spoken steps, a coach session's target and the GPS
/// signal, each worked out without GPS, Health or a run under way.
@MainActor
struct RunRecorderLogicTests {
    // MARK: Climb

    @Test func theBarometerCountsFinerClimbThanGPS() {
        #expect(ClimbCounter.threshold(hasBarometer: true) == 2)
        #expect(ClimbCounter.threshold(hasBarometer: false) == 6)
        #expect(ClimbCounter.barometerThreshold == 2)
        #expect(ClimbCounter.gpsThreshold == 6)
    }

    @Test func gpsHeightNeedsSixMetersToCountAsClimb() {
        var climb = ClimbCounter(threshold: ClimbCounter.threshold(hasBarometer: false))
        for height in [0, 5, 5.9, 6, 1, 0.5, -0.5] as [Double] {
            climb.record(height)
        }
        // 0 to 6 counts as 6 up; 6 to 0.5 is only 5.5 down, then -0.5 makes 6.5 down.
        #expect(climb.ascent == 6)
        #expect(climb.descent == 6.5)
    }
}
