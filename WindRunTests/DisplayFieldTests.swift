//
//  DisplayFieldTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The data fields a runner can put on the display screen, the live numbers behind them, and editing a screen.
struct DisplayFieldTests {
    private func defaults() -> UserDefaults {
        let name = "DisplayFieldTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - Editing a screen

    @Test func everyMetricHasANameASummaryAndAGroup() {
        #expect(DisplayMetric.allCases.count == 30)
        for metric in DisplayMetric.allCases {
            #expect(!metric.name.isEmpty)
            #expect(!metric.summary.isEmpty)
            #expect(metric.category.metrics.contains(metric))
        }
        #expect(DisplayMetricCategory.allCases.flatMap(\.metrics).count == DisplayMetric.allCases.count)
    }

    @Test func placingAMetricAlreadyOnTheScreenSwapsTheTwo() {
        var screen = DisplayScreen.standard
        screen.place(.cadence, in: .primary)

        #expect(screen.primary == .cadence)
        #expect(screen.tiles == [.currentPace, .heartRate, .heightFromStart, .elapsed])

        screen.place(.totalAscent, in: .tile(1))
        #expect(screen.tiles == [.currentPace, .totalAscent, .heightFromStart, .elapsed])
        #expect(Set(screen.metrics).count == 6)
    }

    @Test func anEditedScreenIsSavedAndReadBack() {
        let defaults = defaults()
        #expect(DisplayScreen.current(in: defaults) == .standard)

        var screen = DisplayScreen.standard
        screen.place(.grade, in: .tile(3))
        screen.save(in: defaults)

        #expect(DisplayScreen.current(in: defaults) == screen)
        // Kept as text, so it syncs with the other settings.
        #expect(defaults.string(forKey: DisplayScreen.storageKey) != nil)
    }

    @Test func aMetricFromANewerVersionFallsBackToTheStandardOne() throws {
        let json = #"{"id":"6F1D2A7C-3B4E-4C5D-9E8F-0A1B2C3D4E5F","name":"Mine","primary":"somethingNew","secondary":"distance","tiles":["grade","later","altitude","cadence"]}"#
        let screen = try JSONDecoder().decode(DisplayScreen.self, from: Data(json.utf8))

        #expect(screen.primary == .elapsed)
        #expect(screen.tiles == [.grade, .heartRate, .altitude, .cadence])
    }

    @Test func everyMetricReadsTheSampleRunWithoutADash() {
        for unit in [DistanceUnit.kilometers, .miles] {
            let sample = RunSnapshot.sample(unit: unit)
            for metric in DisplayMetric.allCases {
                let reading = metric.reading(sample)
                #expect(reading.metric == metric)
                #expect(reading.value != "––", "\(metric) in \(unit)")
                #expect(!reading.label.isEmpty)
                #expect(!reading.spoken.isEmpty)
            }
        }
    }

    @Test func everyMetricShowsADashOrAZeroBeforeTheRunHasAnything() {
        let empty = RunSnapshot(elapsed: 0, meters: 0, unit: .kilometers)
        for metric in DisplayMetric.allCases {
            let reading = metric.reading(empty)
            #expect(!reading.value.isEmpty)
            #expect(!reading.spoken.isEmpty)
        }
    }

    // MARK: - Readings

    @Test func goalLeftAndProjectedFinishFollowTheGoal() {
        var snapshot = RunSnapshot(elapsed: 1_500, meters: 5_000, unit: .kilometers, averagePace: 300)
        snapshot.goalMeters = 10_000
        #expect(DisplayMetric.goalLeft.reading(snapshot).value == "5.00")
        #expect(DisplayMetric.projectedFinish.reading(snapshot).value == "50:00")

        snapshot.goalMeters = nil
        snapshot.goalSeconds = 3_000
        #expect(DisplayMetric.goalLeft.reading(snapshot).value == "25:00")
        // 1,500 s left at 5:00 a kilometer is 5 km more.
        #expect(DisplayMetric.projectedFinish.reading(snapshot).value == "10.00")

        snapshot.goalSeconds = nil
        #expect(DisplayMetric.goalLeft.reading(snapshot).label == "NO GOAL")
    }

    @Test func aheadOrBehindCountsAgainstTheMiddleOfTheTargetRange() {
        var snapshot = RunSnapshot(elapsed: 1_450, meters: 5_000, unit: .kilometers)
        snapshot.paceTarget = 290...310
        let ahead = DisplayMetric.aheadBehind.reading(snapshot)
        #expect(ahead.label == "AHEAD")
        #expect(ahead.value == "0:50")

        snapshot.elapsed = 1_530
        #expect(DisplayMetric.aheadBehind.reading(snapshot).label == "BEHIND")

        snapshot.paceTarget = nil
        #expect(DisplayMetric.aheadBehind.reading(snapshot).label == "NO TARGET")
    }

    @Test func heartRateZonesAreTenPercentBandsOfTheMaximum() {
        #expect(HeartRateMax.zone(100, max: 200) == 1)
        #expect(HeartRateMax.zone(125, max: 200) == 2)
        #expect(HeartRateMax.zone(150, max: 200) == 3)
        #expect(HeartRateMax.zone(170, max: 200) == 4)
        #expect(HeartRateMax.zone(185, max: 200) == 5)

        var snapshot = RunSnapshot(elapsed: 60, meters: 200, unit: .kilometers, beatsPerMinute: 150)
        #expect(DisplayMetric.heartRateZone.reading(snapshot).value == "––")
        snapshot.heartRateMax = 200
        let reading = DisplayMetric.heartRateZone.reading(snapshot)
        #expect(reading.value == "Z3")
        #expect(reading.tint == .zone3)
    }

    @Test func theMaximumHeartRateIgnoresASingleSpikeAndOnlyGoesUp() {
        let defaults = defaults()
        HeartRateMax.record([150, 172, 225], in: defaults)
        #expect(HeartRateMax.value(in: defaults) == 172)

        HeartRateMax.record([140, 160, 165], in: defaults)
        #expect(HeartRateMax.value(in: defaults) == 172)

        HeartRateMax.record([181], in: defaults)
        #expect(HeartRateMax.value(in: defaults) == 172)
    }

    @Test func aRunsPeakIsWhatItsHeartRateHeld() {
        // A long run near 150 with a couple of spikes to 205.
        let readings = Array(repeating: 150.0, count: 200) + [205, 205]
        #expect(HeartRateMax.peak(of: readings) == 150)
    }

    @Test func aBadRunsMaximumLeavesAfterTheRecentRuns() {
        let defaults = defaults()
        // A run where the sensor locked onto cadence.
        HeartRateMax.record(Array(repeating: 186.0, count: 100), in: defaults)
        #expect(HeartRateMax.value(in: defaults) == 186)

        for _ in 0..<HeartRateMax.recentRuns {
            HeartRateMax.record(Array(repeating: 170.0, count: 100), in: defaults)
        }
        #expect(HeartRateMax.value(in: defaults) == 170)
    }

    @Test func gradeAdjustedPaceIsFasterUphillAndTheSameOnTheFlat() {
        #expect(DisplayMetric.gradeAdjusted(300, grade: 0) == 300)
        #expect(DisplayMetric.gradeAdjusted(300, grade: 0.08) < 300)
        #expect(DisplayMetric.gradeAdjusted(300, grade: -0.05) > 250)
    }

    @Test func strideLengthComesFromPaceAndCadence() {
        // 5:00 a kilometer is 3.33 m/s; 180 steps a minute is 3 a second.
        let snapshot = RunSnapshot(elapsed: 600, meters: 2_000, unit: .kilometers, currentPace: 300, cadence: 180)
        #expect(DisplayMetric.strideLength.reading(snapshot).value == "1.11")
    }

    // MARK: - Live numbers

    @Test func splitsEndAtEachKilometerAndKeepTheLastOnesTime() {
        var splits = SplitClock(length: 1_000)
        splits.record(time: 0, meters: 0)
        splits.record(time: 290, meters: 960)
        #expect(splits.lastSplit == nil)
        splits.record(time: 310, meters: 1_040)
        // The kilometer was crossed halfway between the two fixes.
        #expect(splits.lastSplit == 300)
        splits.record(time: 450, meters: 1_500)
        #expect(splits.pace(time: 450, meters: 1_500) == 300)
    }

    @Test func rollingPaceReadsTheLastStretchOnly() {
        var rolling = RollingPace()
        rolling.record(time: 0, meters: 0)
        #expect(rolling.pace(over: 500) == nil)
        rolling.record(time: 400, meters: 1_000)
        #expect(rolling.pace(over: 500) == 400)
        rolling.record(time: 550, meters: 1_500)
        // The last 500 m took 150 s.
        #expect(rolling.pace(over: 500) == 300)
    }

    @Test func climbCountsOnlyChangesPastTheThreshold() {
        var climb = ClimbCounter(threshold: 2)
        for height in [0, 1, 0.5, 1.5, 3, 6, 10, 9, 7, 4] as [Double] {
            climb.record(height)
        }
        #expect(climb.ascent == 10)
        #expect(climb.descent == 6)
    }

    @Test func slopeReadsGradeAndClimbingSpeed() {
        var slope = SlopeTracker()
        for second in 0...60 {
            slope.record(time: TimeInterval(second), meters: Double(second) * 2, height: Double(second) * 0.2)
        }
        #expect(abs((slope.grade ?? 0) - 0.1) < 0.0001)
        #expect(abs((slope.metersPerHour ?? 0) - 720) < 0.01)
    }

    @Test func sunsetAndSunriseComeInOrder() throws {
        // Greenwich on the June solstice: sunrise about 3:43 and sunset about 20:21 UTC.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let noon = try #require(utc.date(from: DateComponents(year: 2026, month: 6, day: 21, hour: 12)))
        let sunset = try #require(SunTimes.next(after: noon, latitude: 51.48, longitude: 0))
        #expect(sunset.isSunset)
        let hour = utc.component(.hour, from: sunset.date)
        #expect(hour == 20)

        let sunrise = try #require(SunTimes.next(after: sunset.date.addingTimeInterval(60), latitude: 51.48, longitude: 0))
        #expect(!sunrise.isSunset)
        #expect(utc.component(.hour, from: sunrise.date) == 3)

        // No sunset near the North Pole in June.
        #expect(SunTimes.next(after: noon, latitude: 89, longitude: 0) == nil)
    }
}
