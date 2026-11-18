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

    @Test func aPlannedDistanceReadsToTheTenth() {
        // 7,424 m is 4.613 mi and 7.424 km.
        #expect(RunFormat.plannedDistance(7_424, unit: .miles) == "4.6 mi")
        #expect(RunFormat.plannedDistance(7_424, unit: .kilometers) == "7.4 km")
        #expect(RunFormat.plannedDistance(8_000, unit: .kilometers, withUnit: false) == "8.0")
        #expect(RunFormat.plannedDistance(10 * 1_609.344, unit: .miles) == "10.0 mi")
    }

    @Test func aPlannedRunAimsForTheDistanceItShows() {
        let miles = DistanceUnit.miles.plannedMeters(7_424)
        #expect(abs(miles - 4.6 * 1_609.344) < 0.001)
        // The run's own distance reads 4.60 the moment it gets there.
        #expect(RunFormat.distance(miles, unit: .miles, withUnit: false) == "4.60")
        #expect(DistanceUnit.kilometers.plannedMeters(7_424) == 7_400)
        // Too short to round, so it's kept.
        #expect(DistanceUnit.kilometers.plannedMeters(40) == 40)
    }

    @Test func aPlannedTimeIsTheWholeMinuteTheCoachShows() {
        #expect(CoachFormat.plannedSeconds(45 * 60 + 20) == 45 * 60)
        #expect(CoachFormat.minutes(45 * 60 + 20) == "45 min")
        #expect(CoachFormat.plannedSeconds(20) == 20)
    }

    @Test func thePreviewGoalIsRoundInEitherUnit() {
        let miles = DisplayScreen.standard.readings(.sample(unit: .miles))
        let kilometers = DisplayScreen.standard.readings(.sample(unit: .kilometers))
        #expect(miles.secondary.label == "OF 10.0 MI")
        #expect(kilometers.secondary.label == "OF 15.0 KM")
        #expect(miles.tiles[0].label == "TARGET 8:10–8:43")
    }
}
