//
//  NumberInputLogicTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

@MainActor
struct DurationWheelsTests {
    @Test func splitsATimeIntoWheels() {
        let parts = DurationWheels.wheelValues(for: 3_725.4)
        #expect(parts.hours == 1)
        #expect(parts.minutes == 2)
        #expect(parts.seconds == 5)

        let rounded = DurationWheels.wheelValues(for: 59.6)
        #expect(rounded.hours == 0)
        #expect(rounded.minutes == 1)
        #expect(rounded.seconds == 0)
    }

    @Test func noTimeIsAllZeros() {
        let parts = DurationWheels.wheelValues(for: nil)
        #expect(parts.hours == 0)
        #expect(parts.minutes == 0)
        #expect(parts.seconds == 0)
    }

    @Test func wheelsAtZeroAreNoTime() {
        #expect(DurationWheels.total(hours: 0, minutes: 0, seconds: 0) == nil)
        #expect(DurationWheels.total(hours: 0, minutes: 5, seconds: 0) == 300)
        #expect(DurationWheels.total(hours: 1, minutes: 2, seconds: 5) == 3_725)
    }
}
