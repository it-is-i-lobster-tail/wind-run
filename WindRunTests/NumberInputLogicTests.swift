//
//  NumberInputLogicTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

@MainActor
struct MirroredWidthsTests {
    @Test func mirroredPairsShareTheWiderWidth() {
        #expect(MirroredWidths.mirrored([10, 30, 20]) == [20, 30, 20])
        #expect(MirroredWidths.mirrored([10, 40]) == [40, 40])
        #expect(MirroredWidths.mirrored([]) == [])
    }

    @Test func widthsThatFitAreLeftAlone() {
        #expect(MirroredWidths.fitted([50, 50], spacing: 4, available: 200) == [50, 50])
        #expect(MirroredWidths.fitted([50, 50], spacing: 4, available: 104) == [50, 50])
        #expect(MirroredWidths.fitted([50, 50], spacing: 4, available: nil) == [50, 50])
        #expect(MirroredWidths.fitted([50, 50], spacing: 4, available: .infinity) == [50, 50])
        #expect(MirroredWidths.fitted([], spacing: 4, available: 10) == [])
    }

    @Test func widthsThatDontFitNarrowByTheSameShare() {
        // 54 points less the 4 point gap leaves half of the 100 points asked for.
        #expect(MirroredWidths.fitted([50, 50], spacing: 4, available: 54) == [25, 25])
        #expect(MirroredWidths.fitted([20, 60, 20], spacing: 5, available: 60) == [10, 30, 10])
        // Narrower than the gaps alone leaves nothing for the pills.
        #expect(MirroredWidths.fitted([50, 50], spacing: 4, available: 2) == [0, 0])
    }
}

@MainActor
struct DurationWheelsTests {
    @Test func splitsATimeIntoWheels() {
        let parts = DurationWheels.parts(of: 3_725.4)
        #expect(parts.hours == 1)
        #expect(parts.minutes == 2)
        #expect(parts.seconds == 5)

        let rounded = DurationWheels.parts(of: 59.6)
        #expect(rounded.hours == 0)
        #expect(rounded.minutes == 1)
        #expect(rounded.seconds == 0)
    }

    @Test func noTimeIsAllZeros() {
        let parts = DurationWheels.parts(of: nil)
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
