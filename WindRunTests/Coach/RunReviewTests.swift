//
//  RunReviewTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// PZ-11 and PZ-12: the heart-rate numbers the app reads from the logged runs, on the device.
@MainActor
struct HeartRateZoneTests {
    let calendar = CoachFixtures.calendar
    let state = CoachFixtures.start(CoachFixtures.regularIntake())
    let watch = HeartRateSettings(device: .appleWatch)
    let strap = HeartRateSettings(device: .chestStrap)

    var estimate: Double { (208 - 0.7 * Double(state.assessment.age)).rounded() }

    /// A run with decision-grade heart rate unless a check says otherwise.
    func run(
        day: Int,
        minutes: Double = 45,
        rpe: Int = 3,
        talkTest: Bool? = true,
        allOut: Bool = false,
        heat: HeatAnswer? = nil,
        source: HeartRateDevice = .appleWatch,
        mean: Double? = 140,
        peak: Double? = nil,
        fromMinute10: Double? = nil,
        coverage: Double = 0.95
    ) -> LoggedRun {
        var checkIn = RunCheckIn(answeredAt: CoachFixtures.day(day, hour: 9), rpe: rpe, talkTest: talkTest, feel: .ok)
        checkIn.raceOrAllOut = allOut
        checkIn.heat = heat
        let heartRate = RunHeartRate(source: source, coverage: coverage, mean: mean, peak30s: peak, fromMinute10: fromMinute10)
        return LoggedRun(start: CoachFixtures.day(day), movingSeconds: minutes * 60, meters: minutes * 60 / 330 * 1_000, checkIn: checkIn, heartRate: heartRate)
    }

    func zones(_ runs: [LoggedRun], settings: HeartRateSettings? = nil, state: CoachState? = nil) -> HeartRateZones {
        let state = state ?? self.state
        return RunHeartRate.zones(age: state.assessment.age, settings: settings ?? watch, runs: runs, state: state, calendar: calendar)
    }

    @Test func twoRacesRaiseMaxToTheLowerPeak() {
        let runs = [run(day: 1, allOut: true, peak: estimate + 9), run(day: 5, allOut: true, peak: estimate + 5)]
        let zones = zones(runs)
        #expect(zones.max == estimate + 5)
        #expect(zones.maxObserved)
        #expect(zones.easyCeiling == ((estimate + 5) * 0.80).rounded())
    }

    @Test func oneRaceIsEnoughOnlyWithAStrap() {
        #expect(zones([run(day: 1, allOut: true, source: .chestStrap, peak: estimate + 6)], settings: strap).max == estimate + 6)
        let watchOnly = zones([run(day: 1, allOut: true, peak: estimate + 6)])
        #expect(watchOnly.max == estimate)
        #expect(!watchOnly.maxObserved)
    }

    @Test func observedMaxNeverPassesTheEstimatePlus22() {
        let runs = [run(day: 1, allOut: true, peak: estimate + 40), run(day: 5, allOut: true, peak: estimate + 30)]
        #expect(zones(runs).max == estimate + 22)
    }

    @Test func peaksBelowTheEstimateNeverLowerIt() {
        let runs = [run(day: 1, allOut: true, peak: estimate - 10), run(day: 5, allOut: true, peak: estimate - 12)]
        #expect(zones(runs).max == estimate)
    }

    @Test func onlyRunsMarkedAllOutCount() {
        let runs = [run(day: 1, peak: estimate + 9), run(day: 5, peak: estimate + 8)]
        #expect(zones(runs).max == estimate)
    }

    @Test func patchyHeartRateNeverRaisesMax() {
        let runs = [run(day: 1, allOut: true, peak: estimate + 9, coverage: 0.5), run(day: 5, allOut: true, peak: estimate + 8, coverage: 0.5)]
        #expect(zones(runs).max == estimate)
    }

    @Test func startersAndNovicesKeepTheEstimate() {
        var novice = state
        novice.assessment.tier = .novice
        let runs = [run(day: 1, allOut: true, peak: estimate + 9), run(day: 5, allOut: true, peak: estimate + 8)]
        #expect(zones(runs, state: novice).max == estimate)
    }

    @Test func aLowerLabMaxReplacesTheEstimate() {
        let settings = HeartRateSettings(device: .appleWatch, labMax: estimate - 8)
        #expect(zones([], settings: settings).max == estimate - 8)
    }

    @Test func showOnlyUsesTheEstimateAlone() {
        let runs = [run(day: 1, allOut: true, source: .chestStrap, peak: estimate + 6)]
        let zones = zones(runs, settings: HeartRateSettings(device: .chestStrap, useForCoaching: false))
        #expect(zones.max == estimate)
        #expect(zones.threshold == nil)
        #expect(zones.personalEasyCeiling == nil)
    }

    @Test func thresholdComesFromTheNewestAllOutRunOf40To70Minutes() {
        let runs = [
            run(day: 1, minutes: 50, rpe: 9, allOut: true, fromMinute10: 158),
            run(day: 4, minutes: 52, rpe: 9, allOut: true, fromMinute10: 162),
            // Too long, and not marked: neither sets threshold HR.
            run(day: 6, minutes: 80, rpe: 9, allOut: true, fromMinute10: 150),
            run(day: 7, minutes: 45, rpe: 8, fromMinute10: 170),
        ]
        let zones = zones(runs)
        #expect(zones.threshold == 162)
        #expect(zones.thresholdBand == (162 * 0.95).rounded() ... 162)
    }

    @Test func aHotRunNeverSetsThreshold() {
        let runs = [
            run(day: 1, minutes: 50, rpe: 9, allOut: true, fromMinute10: 158),
            run(day: 4, minutes: 50, rpe: 9, allOut: true, heat: .warm, fromMinute10: 168),
        ]
        #expect(zones(runs).threshold == 158)
    }

    @Test func personalCeilingNeedsThreeEasyRunsThatFeltEasy() {
        let two = [run(day: 1, mean: 128), run(day: 3, mean: 130)]
        #expect(zones(two).personalEasyCeiling == nil)
        let runs = two + [
            run(day: 5, mean: 132),
            // Rated 4, and a failed talk test: neither counts.
            run(day: 6, rpe: 4, mean: 150),
            run(day: 7, talkTest: false, mean: 150),
        ]
        let zones = zones(runs)
        #expect(zones.personalEasyCeiling == 130)
        #expect(zones.easyCeiling == 130)
    }

    @Test func personalCeilingUsesTheLatestFiveAndOnlyWhenLower() {
        let means: [Double] = [120, 150, 150, 150, 150, 150]
        let runs = means.enumerated().map { run(day: $0.offset, mean: $0.element) }
        let zones = zones(runs)
        #expect(zones.personalEasyCeiling == 150)
        #expect(zones.easyCeiling == (estimate * 0.75).rounded())
    }

    @Test func personalCeilingKeepsToOneDevice() {
        let runs = [run(day: 1, source: .chestStrap, mean: 128), run(day: 3, mean: 130), run(day: 5, mean: 132), run(day: 6, mean: 134)]
        #expect(zones(runs).personalEasyCeiling == 132)
        #expect(zones(runs, settings: strap).personalEasyCeiling == nil)
    }

    @Test func personalCeilingStartsAgainAfterABreak() {
        let before = [run(day: 1, mean: 120), run(day: 2, mean: 120), run(day: 3, mean: 120)]
        let after = [run(day: 20, mean: 135), run(day: 21, mean: 137)]
        #expect(zones(before + after).personalEasyCeiling == nil)
    }
}

/// BD-5c's benchmark comparison and AD-6c's fatigue check.
@MainActor
struct BenchmarkTests {
    let calendar = CoachFixtures.calendar
    let state = CoachFixtures.start(CoachFixtures.regularIntake())

    func benchmark(day: Int, pace: Double, rpe: Int = 3, meters: Double = 5_000, temperature: Double? = 12, treadmill: Bool = false) -> LoggedRun {
        LoggedRun(
            start: CoachFixtures.day(day),
            movingSeconds: meters / 1_000 * pace,
            meters: meters,
            source: treadmill ? .treadmill : .gps,
            checkIn: RunCheckIn(answeredAt: CoachFixtures.day(day, hour: 9), rpe: rpe, talkTest: true, feel: .ok),
            track: treadmill ? nil : TrackSummary(climbFirstHalf: 10, climbSecondHalf: 12),
            temperature: temperature
        )
    }

    func compare(_ run: LoggedRun, _ earlier: [LoggedRun], state: CoachState? = nil) -> (notes: [CoachNote], fatigueCheck: Bool) {
        RunReviewer.compareBenchmark(run, earlier: earlier, state: state ?? self.state, now: run.end.addingTimeInterval(3_600), calendar: calendar)
    }

    @Test func aFasterBenchmarkAtTheSameEffortIsAGain() {
        let result = compare(benchmark(day: 42, pace: 376), [benchmark(day: 0, pace: 400)])
        #expect(result.notes == [CoachNote(.insight, "Same easy effort, 6% faster than 6 weeks ago.")])
        #expect(!result.fatigueCheck)
    }

    @Test func theSamePaceRatedLowerIsAGain() {
        let result = compare(benchmark(day: 28, pace: 396, rpe: 2), [benchmark(day: 0, pace: 400, rpe: 3)])
        #expect(result.notes == [CoachNote(.insight, "Same pace as 4 weeks ago, at an easier effort.")])
    }

    @Test func underFivePercentIsNoClearChange() {
        let result = compare(benchmark(day: 35, pace: 388), [benchmark(day: 0, pace: 400)])
        #expect(result.notes == [CoachNote(.insight, "Same easy effort, about the same pace as 5 weeks ago.")])
    }

    @Test func muchSlowerWithWorseFatigueStartsTheFatigueCheck() {
        var tired = state
        tired.morningChecks.append(MorningCheck(date: CoachFixtures.day(35, hour: 6), fatigue: 6, soreness: 4))
        let run = benchmark(day: 35, pace: 445)
        let result = compare(run, [benchmark(day: 0, pace: 400)], state: tired)
        #expect(result.fatigueCheck)
        #expect(result.notes == [CoachNote(.plan, "Your check run was well off your usual at the same effort. Let's rest or run easy for a week.")])
        // Without the worse fatigue it is only a slower run.
        #expect(!compare(run, [benchmark(day: 0, pace: 400)]).fatigueCheck)
    }

    @Test func onlyLikeForLikeRunsAreCompared() {
        let earlier = benchmark(day: 0, pace: 400, temperature: 5)
        #expect(compare(benchmark(day: 35, pace: 370, temperature: 14), [earlier]).notes.isEmpty)
        #expect(compare(benchmark(day: 35, pace: 370, temperature: 5, treadmill: true), [earlier]).notes.isEmpty)
        #expect(compare(benchmark(day: 35, pace: 370, meters: 7_000, temperature: 5), [earlier]).notes.isEmpty)
        // The newest like-for-like run is the one compared.
        let result = compare(benchmark(day: 35, pace: 370, temperature: 5), [earlier, benchmark(day: 21, pace: 392, temperature: 6)])
        #expect(result.notes == [CoachNote(.insight, "Same easy effort, 6% faster than 2 weeks ago.")])
    }

    @Test func noRPENoComparison() {
        var run = benchmark(day: 35, pace: 370)
        run.checkIn = nil
        #expect(compare(run, [benchmark(day: 0, pace: 400)]).notes.isEmpty)
    }
}
