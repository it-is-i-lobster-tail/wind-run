//
//  HeartRateWindowTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

struct HeartRateWindowTests {
    private let end = Date(timeIntervalSinceReferenceDate: 10_000)

    private func reading(secondsAgo: TimeInterval, _ beatsPerMinute: Double) -> HeartRateReading {
        HeartRateReading(date: end.addingTimeInterval(-secondsAgo), beatsPerMinute: beatsPerMinute)
    }

    @Test func anEmptyWindowHasSixtyEmptySteps() {
        let window = HeartRateWindow(end: end)

        #expect(window.steps.count == 60)
        #expect(window.steps.allSatisfy { $0 == 0 })
        #expect(window.points.isEmpty)
        #expect(window.start == end.addingTimeInterval(-300))
    }

    @Test func readingsAreAveragedIntoFiveSecondSteps() {
        let window = HeartRateWindow(readings: [
            reading(secondsAgo: 4, 140),
            reading(secondsAgo: 1, 145),
            reading(secondsAgo: 0, 150),
            reading(secondsAgo: 7, 130),
        ], end: end)

        // The newest step takes in the last five seconds, up to and including the end.
        #expect(window.steps[59] == 145)
        #expect(window.steps[58] == 130)
        #expect(window.steps.dropLast(2).allSatisfy { $0 == 0 })
    }

    @Test func readingsOutsideTheFiveMinutesAreLeftOut() {
        let window = HeartRateWindow(readings: [
            reading(secondsAgo: 300, 120),
            reading(secondsAgo: 299, 125),
            reading(secondsAgo: -1, 160),
        ], end: end)

        #expect(window.steps[0] == 125)
        #expect(window.points.map(\.beatsPerMinute) == [125])
    }

    @Test func pointsSitAtTheEndOfTheirStep() {
        let window = HeartRateWindow(readings: [
            reading(secondsAgo: 2, 150),
            reading(secondsAgo: 62, 140),
        ], end: end)

        #expect(window.points == [
            HeartRateWindow.Point(date: end.addingTimeInterval(-60), beatsPerMinute: 140),
            HeartRateWindow.Point(date: end, beatsPerMinute: 150),
        ])
    }

    @Test func valuesFitInOneByte() {
        let window = HeartRateWindow(readings: [
            reading(secondsAgo: 1, 300),
            reading(secondsAgo: 6, 0.4),
            reading(secondsAgo: 11, 0),
        ], end: end)

        #expect(window.steps[59] == 255)
        // A real but tiny reading still counts, while zero means no reading.
        #expect(window.steps[58] == 1)
        #expect(window.steps[57] == 0)
    }

    @Test func aFullWindowStaysWellUnderTheLiveActivityLimit() throws {
        let readings = (0..<300).map { reading(secondsAgo: Double($0), 180 + Double($0 % 20)) }
        let state = HeartRateActivityAttributes.ContentState(
            beatsPerMinute: 199,
            window: HeartRateWindow(readings: readings, end: end)
        )
        let data = try JSONEncoder().encode(state)

        // ActivityKit allows 4 KB for the whole update.
        #expect(data.count < 1_024)
        #expect(try JSONDecoder().decode(HeartRateActivityAttributes.ContentState.self, from: data) == state)
    }
}
