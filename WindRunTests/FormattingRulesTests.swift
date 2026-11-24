//
//  FormattingRulesTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The rules the screen and the voice share, so the two never disagree about a number.
@MainActor
struct SharedFormattingRuleTests {
    @Test func secondsAreCutDownToTheWholeSecond() {
        // The tiny nudge keeps a hair under 250 s at 250.
        #expect(RunFormat.wholeSeconds(249.9996) == 250)
        #expect(RunFormat.wholeSeconds(299.6) == 299)
        #expect(RunFormat.wholeSeconds(0) == 0)
        #expect(RunFormat.wholeSeconds(-5) == 0)
    }

    @Test func paceInTheRunnersUnit() {
        #expect(RunFormat.secondsPerUnit(300, unit: .kilometers) == 300)
        #expect(RunFormat.secondsPerUnit(3_599, unit: .kilometers) == 3_599)
        #expect(RunFormat.secondsPerUnit(nil, unit: .kilometers) == nil)
        #expect(RunFormat.secondsPerUnit(0, unit: .kilometers) == nil)
        #expect(RunFormat.secondsPerUnit(-5, unit: .miles) == nil)
        #expect(RunFormat.secondsPerUnit(.infinity, unit: .kilometers) == nil)
        #expect(RunFormat.secondsPerUnit(.nan, unit: .kilometers) == nil)
    }

    @Test func screenAndVoiceIncludePacesOfAnHourOrMore() {
        #expect(RunFormat.pace(3_600, unit: .kilometers) == "1:00:00 /km")
        #expect(SpokenFormat.pace(3_600, unit: .kilometers) == "1 hour per kilometer")
        #expect(RunFormat.pace(2_400, unit: .miles) == "1:04:22 /mi")
        #expect(SpokenFormat.pace(2_400, unit: .miles) == "1 hour 4 minutes 22 seconds per mile")
    }

    @Test func timeOptionsReadAsMinutesOrAClock() {
        #expect(RunFormat.wholeMinutes(180) == "3 min")
        #expect(RunFormat.wholeMinutes(0) == "0 min")
        #expect(RunFormat.wholeMinutes(90) == nil)
        #expect(RunFormat.goal(.time(180), unit: .kilometers) == "3 min")
        #expect(RunFormat.goal(.time(90), unit: .kilometers) == "1:30")
        #expect(PaceCalloutSettings.secondsName(1_800) == "30 min")
        #expect(PaceCalloutSettings.secondsName(90) == "1:30")
        #expect(PaceCalloutSettings.secondsName(30) == "30 sec")
    }
}

@MainActor
struct UnitWordTests {
    @Test func singularNames() {
        #expect(DistanceUnit.kilometers.singularName == "kilometer")
        #expect(DistanceUnit.miles.singularName == "mile")
    }

    @Test func pluralNames() {
        #expect(DistanceUnit.kilometers.pluralName == "kilometers")
        #expect(DistanceUnit.miles.pluralName == "miles")
    }

    @Test func lastUnitLabelsInBothUnits() {
        #expect(PaceKind.lastUnit.name(unit: .miles) == "Last mile")
        #expect(PaceKind.lastUnit.name(unit: .kilometers) == "Last kilometer")
        #expect(PaceKind.lastUnit.detail(unit: .miles) == "Your pace over the last mile, however long your splits are.")
        #expect(PaceKind.lastUnit.detail(unit: .kilometers) == "Your pace over the last kilometer, however long your splits are.")
        #expect(PaceKind.lastUnit.spokenLabel(unit: .miles) == "last mile pace")
        #expect(PaceKind.lastUnit.spokenLabel(unit: .kilometers) == "last kilometer pace")
    }

    @Test func spokenPaceEndsInTheUnitWord() {
        #expect(SpokenFormat.pace(300, unit: .kilometers) == "5 minutes per kilometer")
        #expect(SpokenFormat.pace(1_000 / DistanceUnit.miles.meters * 600, unit: .miles)?.hasSuffix(" per mile") == true)
    }
}

@MainActor
struct HeightUnitTests {
    @Test func heightsFollowTheDistanceUnit() {
        #expect(DistanceUnit.miles.height(fromMeters: DistanceUnit.metersPerFoot) == 1)
        #expect(DistanceUnit.miles.height(fromMeters: 0) == 0)
        #expect(DistanceUnit.kilometers.height(fromMeters: 37) == 37)
        #expect(DistanceUnit.miles.heightSymbol == "ft")
        #expect(DistanceUnit.kilometers.heightSymbol == "m")
        #expect(RunFormat.elevation(DistanceUnit.metersPerFoot * 100, unit: .miles) == "100 ft")
    }
}

@MainActor
struct WholeReadingTests {
    @Test func cadenceCountsStandingStill() {
        #expect(RunFormat.cadence(171.6) == "172 spm")
        #expect(RunFormat.cadence(171.6, withUnit: false) == "172")
        #expect(RunFormat.cadence(0) == "0 spm")
        #expect(RunFormat.cadence(nil) == "–– spm")
        #expect(RunFormat.cadence(-1) == "–– spm")
        #expect(RunFormat.cadence(.nan, withUnit: false) == "––")
    }

    @Test func heartRateHasNoZero() {
        #expect(RunFormat.heartRate(0) == "–– bpm")
        #expect(RunFormat.heartRate(0, withUnit: false) == "––")
        #expect(RunFormat.heartRate(.infinity) == "–– bpm")
        #expect(RunFormat.heartRate(60) == "60 bpm")
    }
}

@MainActor
struct SpokenMileFractionTests {
    private let mile = DistanceUnit.miles.meters

    @Test func quartersAreWords() {
        #expect(SpokenFormat.distance(mile * 0.25, unit: .miles) == "quarter mile")
        #expect(SpokenFormat.distance(mile * 2.75, unit: .miles) == "2 and three quarters miles")
        #expect(SpokenFormat.distance(mile * 0.75, unit: .miles) == "three quarters of a mile")
    }

    @Test func otherFractionsAreNumbers() {
        #expect(SpokenFormat.distance(mile * 1.3, unit: .miles) == "1.3 miles")
        #expect(SpokenFormat.distance(mile * 0.1, unit: .miles) == "0.1 miles")
    }

    @Test func noTimeIsZeroSeconds() {
        #expect(SpokenFormat.duration(0) == "0 seconds")
        #expect(SpokenFormat.duration(-3) == "0 seconds")
    }
}

@MainActor
struct PaceRangeTests {
    @Test func aRangeReadsFastestFirst() {
        #expect(RunFormat.paceRange(390 ... 420, unit: .kilometers) == "6:30–7:00 /km")
        #expect(RunFormat.paceRange(390 ... 420, unit: .kilometers, withUnit: false) == "6:30–7:00")
    }

    @Test func oneEndedRangeReadsAsOnePace() {
        #expect(RunFormat.paceRange(300 ... 300, unit: .kilometers) == "5:00 /km")
        // 300 s/km is 482.8 s/mi, cut down to 8:02.
        #expect(RunFormat.paceRange(300 ... 300, unit: .miles) == "8:02 /mi")
    }
}

@MainActor
struct CapitalizedFirstTests {
    @Test func onlyTheFirstLetterChanges() {
        #expect("your shin".capitalizedFirst == "Your shin")
        #expect("warm-up".capitalizedFirst == "Warm-up")
        #expect("Already".capitalizedFirst == "Already")
        #expect("".capitalizedFirst == "")
    }
}

@MainActor
struct StoredDistanceUnitTests {
    @Test func storedReadsOnlyARealUnit() throws {
        let suite = "StoredDistanceUnitTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        #expect(DistanceUnit.stored(in: defaults) == nil)
        #expect(DistanceUnit.current(in: defaults) == .kilometers)
        #expect(!DistanceUnit.isChosen(in: defaults))

        defaults.set("furlongs", forKey: DistanceUnit.storageKey)
        #expect(DistanceUnit.stored(in: defaults) == nil)
        #expect(DistanceUnit.current(in: defaults) == .kilometers)
        #expect(!DistanceUnit.isChosen(in: defaults))

        defaults.set("miles", forKey: DistanceUnit.storageKey)
        #expect(DistanceUnit.stored(in: defaults) == .miles)
        #expect(DistanceUnit.current(in: defaults) == .miles)
        #expect(DistanceUnit.isChosen(in: defaults))
        #expect(PaceCalloutSettings.current(in: defaults).unit == .miles)
    }
}

@MainActor
struct PacePerUnitTests {
    @Test func kilometersAreUnchanged() {
        #expect(DistanceUnit.kilometers.perUnit(300) == 300)
        #expect(DistanceUnit.kilometers.perKilometer(300) == 300)
    }

    @Test func milesScaleByAMilesMeters() {
        // 300 × 1,609.344 / 1,000.
        #expect(DistanceUnit.miles.perUnit(300) == 482.8032)
        #expect(DistanceUnit.miles.perKilometer(482.8032) == 300)
        #expect(DistanceUnit.miles.perKilometer(1_609.344) == 1_000)
    }

    @Test func hikingPaceConvertsInBothUnits() {
        #expect(RunFormat.secondsPerUnit(300, unit: .miles) == 482.8032)
        // 2,300 s/km is 3,701.5 s/mi, over the hour.
        #expect(RunFormat.secondsPerUnit(2_300, unit: .miles) == DistanceUnit.miles.perUnit(2_300))
        #expect(RunFormat.secondsPerUnit(2_300, unit: .kilometers) == 2_300)
    }
}

@MainActor
struct WholeDaysTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()
    private let noon = Date(timeIntervalSince1970: 1_795_003_200) // 2026-11-18 12:00 GMT

    @Test func countsCalendarDaysNotHours() {
        let lateThatNight = noon.addingTimeInterval(11 * 3_600) // 23:00 the same day
        let earlyNextMorning = noon.addingTimeInterval(13 * 3_600) // 01:00 the next day
        #expect(calendar.wholeDays(from: noon, to: lateThatNight) == 0)
        #expect(calendar.wholeDays(from: noon, to: earlyNextMorning) == 1)
        #expect(calendar.wholeDays(from: noon, to: noon.addingTimeInterval(3 * 86_400)) == 3)
    }

    @Test func anEarlierDayIsNegative() {
        #expect(calendar.wholeDays(from: noon, to: noon.addingTimeInterval(-2 * 86_400)) == -2)
    }
}

@MainActor
struct MileLiteralTests {
    @Test func aQuarterMileIsExactly402_336Meters() {
        #expect(DistanceUnit.miles.meters / 4 == 402.336)
    }

    @Test func aDistanceRunStartsAt3MilesOr5Kilometers() {
        #expect(WorkoutMainPage.defaultDistanceMeters(.miles) == 4_828.032)
        #expect(WorkoutMainPage.defaultDistanceMeters(.kilometers) == 5_000)
    }
}

@MainActor
struct WorkoutLengthTests {
    @Test func distancesStayInTheWorkoutsUnit() {
        let timeline = [
            PlannedIntervalStep(kind: .work, goal: .time(600), repetition: 1, repeatCount: 1),
            PlannedIntervalStep(kind: .work, goal: .distance(meters: 400), repetition: 1, repeatCount: 1),
        ]
        #expect(WorkoutDistance.length(timeline, in: .kilometers) == "10 min + 0.4 km")
        // The default writer, which a run's own steps use, says meters under a kilometer.
        #expect(RunFormat.intervalLength(timeline, unit: .kilometers) == "10 min + 400 m")
    }
}

@MainActor
struct DurationAgreementTests {
    /// Just under a whole second, which the shared nudge in `wholeSeconds` carries up for both.
    @Test func screenAndVoiceAgreeJustUnderASecond() {
        let cases: [(TimeInterval, spoken: String, shown: String)] = [
            (59.9996, "1 minute", "1:00"),
            (249.9999, "4 minutes 10 seconds", "4:10"),
            (3_599.9996, "1 hour", "1:00:00"),
            (3_600, "1 hour", "1:00:00"),
        ]
        for (seconds, spoken, shown) in cases {
            #expect(SpokenFormat.duration(seconds) == spoken)
            #expect(RunFormat.duration(seconds) == shown)
        }
    }
}
