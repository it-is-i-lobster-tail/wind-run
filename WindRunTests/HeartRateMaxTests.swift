//
//  HeartRateMaxTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The maximum heart rate behind the run screen's zones: a lab-tested maximum, the recent runs' peaks, and
/// a maximum saved before peaks were kept.
@MainActor
struct HeartRateMaxTests {
    private func defaults() -> UserDefaults {
        let name = "HeartRateMaxTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func saveLabMax(_ labMax: Double, in defaults: UserDefaults) throws {
        let settings = HeartRateSettings(labMax: labMax)
        defaults.set(try JSONEncoder().encode(settings), forKey: HeartRateMax.coachSettingsKey)
    }

    @Test func theCoachKeepsItsSettingsUnderTheKeyThisReads() {
        // Both name the same saved settings; if either changed, a lab-tested maximum would stop counting.
        #expect(HeartRateMax.coachSettingsKey == "coachHeartRateSettings")
        #expect(CoachHeartRateStore.storageKey == "coachHeartRateSettings")
    }

    @Test func aLabTestedMaximumWins() throws {
        let defaults = defaults()
        HeartRateMax.record(Array(repeating: 172, count: 100), in: defaults)
        #expect(HeartRateMax.value(in: defaults) == 172)

        try saveLabMax(190, in: defaults)
        #expect(HeartRateMax.value(in: defaults) == 190)
    }

    @Test func aLabMaximumThatCantBeRealIsIgnored() throws {
        let defaults = defaults()
        HeartRateMax.record(Array(repeating: 172, count: 100), in: defaults)
        try saveLabMax(300, in: defaults)
        #expect(HeartRateMax.value(in: defaults) == 172)
    }

    @Test func nothingBeforeAnyRunWithHeartRate() {
        #expect(HeartRateMax.value(in: defaults()) == nil)
    }

    @Test func aMaximumFromBeforePeaksCountsAsOneRun() {
        let defaults = defaults()
        defaults.set(180.0, forKey: HeartRateMax.storageKey)

        HeartRateMax.record(Array(repeating: 160, count: 100), in: defaults)
        #expect(defaults.array(forKey: HeartRateMax.peaksKey) as? [Double] == [180, 160])
        #expect(HeartRateMax.value(in: defaults) == 180)

        for _ in 0..<HeartRateMax.recentRuns {
            HeartRateMax.record(Array(repeating: 160, count: 100), in: defaults)
        }
        #expect(HeartRateMax.value(in: defaults) == 160)
    }

    @Test func aPeakNeedsTwoReadingsAndAPlausibleHeight() {
        #expect(HeartRateMax.peak(of: []) == nil)
        #expect(HeartRateMax.peak(of: [150]) == nil)
        #expect(HeartRateMax.peak(of: [150, 160]) == 150)
        #expect(HeartRateMax.peak(of: [240, 240]) == nil)
    }

    @Test func tenReadingsTakeThePercentileAndNineTheSecondHighest() {
        // 141 to 150: index Int(9 × 0.98) = 8.
        #expect(HeartRateMax.peak(of: (141...150).map { Double($0) }) == 149)
        // 141 to 149: the second-highest.
        #expect(HeartRateMax.peak(of: (141...149).map { Double($0) }) == 148)
    }

    @Test func zonesStartExactlyAtEachTenPercent() {
        #expect(HeartRateMax.zone(119, max: 200) == 1)
        #expect(HeartRateMax.zone(120, max: 200) == 2)
        #expect(HeartRateMax.zone(140, max: 200) == 3)
        #expect(HeartRateMax.zone(160, max: 200) == 4)
        #expect(HeartRateMax.zone(180, max: 200) == 5)
        #expect(HeartRateMax.zone(230, max: 200) == 5)
    }

    @Test func savedRunsAreReadOnce() {
        let defaults = defaults()
        let container = WindRunSchema.makeContainer(inMemory: true)
        let context = container.mainContext
        let start = Date(timeIntervalSinceReferenceDate: 0)
        let run = Run(startDate: start)
        context.insert(run)
        for second in 1...20 {
            _ = run.record(HeartRateSample(timestamp: start.addingTimeInterval(TimeInterval(second)), beatsPerMinute: 165, source: .appleWatch))
        }
        run.finish(at: start.addingTimeInterval(30))

        HeartRateMax.backfill(in: context, defaults: defaults)
        HeartRateMax.backfill(in: context, defaults: defaults)

        #expect(defaults.array(forKey: HeartRateMax.peaksKey) as? [Double] == [165])
        #expect(HeartRateMax.value(in: defaults) == 165)
        #expect(defaults.bool(forKey: HeartRateMax.backfilledKey))
    }
}
