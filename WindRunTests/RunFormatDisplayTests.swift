//
//  RunFormatDisplayTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The run-row and summary readouts that had no tests of their own.
@MainActor
struct RunFormatDisplayTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
    /// Midday, so the test calendar and the device's time zone agree on the day.
    private let now = Date(timeIntervalSince1970: 1_795_003_200) // 2026-11-18 12:00 GMT

    private func daysAgo(_ days: Int) -> Date {
        now.addingTimeInterval(TimeInterval(-days * 86_400))
    }

    @Test func dayNamesTheRecentDays() {
        #expect(RunFormat.day(now, now: now, calendar: calendar) == "Today")
        #expect(RunFormat.day(daysAgo(1), now: now, calendar: calendar) == "Yesterday")
        #expect(RunFormat.day(daysAgo(3), now: now, calendar: calendar) == daysAgo(3).formatted(.dateTime.weekday(.wide)))
        #expect(RunFormat.day(daysAgo(6), now: now, calendar: calendar) == daysAgo(6).formatted(.dateTime.weekday(.wide)))
    }

    @Test func dayGivesTheDateFromAWeekAgoOrInTheFuture() {
        let weekAgo = daysAgo(7)
        let ahead = daysAgo(-2)
        #expect(RunFormat.day(weekAgo, now: now, calendar: calendar) == weekAgo.formatted(.dateTime.month(.abbreviated).day()))
        #expect(RunFormat.day(ahead, now: now, calendar: calendar) == ahead.formatted(.dateTime.month(.abbreviated).day()))
    }

    @Test func calories() {
        #expect(RunFormat.calories(611.6) == "612 kcal")
        #expect(RunFormat.calories(0) == "0 kcal")
        #expect(RunFormat.calories(nil) == "– kcal")
        #expect(RunFormat.calories(-1) == "– kcal")
        #expect(RunFormat.calories(.nan) == "– kcal")
    }

    @Test func hillCalories() {
        #expect(RunFormat.hillCalories(0.4) == nil)
        #expect(RunFormat.hillCalories(-0.4) == nil)
        #expect(RunFormat.hillCalories(48.2) == "Hills added 48 kcal")
        #expect(RunFormat.hillCalories(-12) == "Downhills saved 12 kcal")
    }

    @Test func steps() {
        #expect(RunFormat.steps(8_411.6) == 8_412.formatted())
        #expect(RunFormat.steps(0) == "0")
    }

    @Test func pacePlaceholders() {
        #expect(RunFormat.pace(nil, unit: .miles, withUnit: false) == "–:––")
        #expect(RunFormat.pace(nil, unit: .miles) == "–:–– /mi")
        #expect(RunFormat.pace(.infinity, unit: .kilometers) == "–:–– /km")
        #expect(RunFormat.pace(-5, unit: .kilometers) == "–:–– /km")
        #expect(RunFormat.pace(300, unit: .kilometers, withUnit: false) == "5:00")
    }

    @Test func distanceWithoutTheUnit() {
        #expect(RunFormat.distance(1_609.344, unit: .miles, withUnit: false) == 1.0.formatted(.number.precision(.fractionLength(2))))
    }
}
