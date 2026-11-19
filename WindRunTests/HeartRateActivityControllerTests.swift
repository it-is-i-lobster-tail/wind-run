//
//  HeartRateActivityControllerTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The Live Activity's rules that don't need ActivityKit: which heart rate shows, when the Lock Screen goes
/// out of date, which changes skip the throttle, and the throttle itself.
@MainActor
struct HeartRateActivityControllerTests {
    private let now = Date(timeIntervalSinceReferenceDate: 10_000)

    private func reading(secondsAgo: TimeInterval, _ beatsPerMinute: Double) -> HeartRateReading {
        HeartRateReading(date: now.addingTimeInterval(-secondsAgo), beatsPerMinute: beatsPerMinute)
    }

    private func step(number: Int = 2, startDate: Date? = nil, detail: String? = nil, isFinished: Bool = false) -> RunStepState {
        RunStepState(name: "Work", number: number, count: 8, startDate: startDate, detail: detail, isFinished: isFinished)
    }

    // MARK: Heart rate

    @Test func theLockScreenUsesTheMonitorsFreshnessLimit() {
        #expect(HeartRateActivityController.heartRateFreshness == HeartRateMonitor.readingFreshness)
        #expect(HeartRateMonitor.readingFreshness == 15)
    }

    @Test func aReadingFifteenSecondsOldStillShows() {
        let latest = HeartRateActivityController.latestBeatsPerMinute([reading(secondsAgo: 15, 150)], at: now)

        #expect(latest == 150)
    }

    @Test func aReadingOverFifteenSecondsOldShowsADash() {
        let latest = HeartRateActivityController.latestBeatsPerMinute([reading(secondsAgo: 15.1, 150)], at: now)

        #expect(latest == nil)
    }

    @Test func theReadingIsRoundedToWholeBeats() {
        #expect(HeartRateActivityController.latestBeatsPerMinute([reading(secondsAgo: 1, 141.5)], at: now) == 142)
        #expect(HeartRateActivityController.latestBeatsPerMinute([reading(secondsAgo: 1, 141.4)], at: now) == 141)
    }

    @Test func onlyTheLastReadingCounts() {
        // A fresh reading earlier in the list doesn't stand in for an old last one.
        let latest = HeartRateActivityController.latestBeatsPerMinute([
            reading(secondsAgo: 2, 160),
            reading(secondsAgo: 20, 130),
        ], at: now)

        #expect(latest == nil)
    }

    @Test func noReadingsShowADash() {
        #expect(HeartRateActivityController.latestBeatsPerMinute([], at: now) == nil)
    }

    // MARK: Out of date

    @Test func aPausedRunNeverGoesOutOfDate() {
        #expect(HeartRateActivityController.staleDate(at: now, isPaused: true) == nil)
    }

    @Test func aRunningRunGoesOutOfDateAfterAMinute() {
        #expect(HeartRateActivityController.staleDate(at: now, isPaused: false) == now.addingTimeInterval(60))
    }

    // MARK: Steps

    @Test func aStepStartingAgainAfterAPauseShowsAtOnce() {
        let paused = step(startDate: nil, detail: "1:20")
        let running = step(startDate: now)

        #expect(HeartRateActivityController.showsStepAtOnce(from: paused, to: running))
        #expect(HeartRateActivityController.showsStepAtOnce(from: running, to: paused))
    }

    @Test func theSameStepWithNewDetailWaitsForTheThrottle() {
        let before = step(startDate: now, detail: "400 m left")
        let after = step(startDate: now, detail: "390 m left")

        #expect(!HeartRateActivityController.showsStepAtOnce(from: before, to: after))
    }

    @Test func aNewStepShowsAtOnce() {
        #expect(HeartRateActivityController.showsStepAtOnce(from: step(number: 2, startDate: now), to: step(number: 3, startDate: now)))
        #expect(HeartRateActivityController.showsStepAtOnce(from: nil, to: step(number: 1, startDate: now)))
        #expect(HeartRateActivityController.showsStepAtOnce(from: step(number: 1, startDate: now), to: nil))
    }

    @Test func theWorkoutFinishingShowsAtOnce() {
        let last = step(number: 8, startDate: now)
        let finished = step(number: 8, startDate: now, isFinished: true)

        #expect(HeartRateActivityController.showsStepAtOnce(from: last, to: finished))
    }

    // MARK: Throttle

    @Test func theFirstUpdateIsNeverThrottled() {
        #expect(!HeartRateActivityController.isThrottled(lastUpdate: nil, at: now))
    }

    @Test func updatesUnderFiveSecondsApartAreThrottled() {
        #expect(HeartRateActivityController.isThrottled(lastUpdate: now, at: now.addingTimeInterval(4.9)))
        #expect(HeartRateActivityController.isThrottled(lastUpdate: now, at: now))
    }

    @Test func anUpdateFiveSecondsLaterIsSent() {
        #expect(!HeartRateActivityController.isThrottled(lastUpdate: now, at: now.addingTimeInterval(5)))
        #expect(!HeartRateActivityController.isThrottled(lastUpdate: now, at: now.addingTimeInterval(30)))
    }
}
