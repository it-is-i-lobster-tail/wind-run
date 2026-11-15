//
//  WatchRunDisplayTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// What the Watch run screen shows: the header, the big numbers' labels, and the pace or Next step part.
struct WatchRunDisplayTests {
    private func input(
        status: RunStatus = .active,
        elapsed: TimeInterval = 32 * 60 + 48,
        meters: Double = 6_400,
        steps: StepTracker? = nil,
        coach: CoachWorkoutTarget? = nil,
        pace: TimeInterval? = 312,
        height: Double? = -43
    ) -> WatchRunDisplay.Input {
        WatchRunDisplay.Input(
            status: status,
            elapsed: elapsed,
            meters: meters,
            unit: .kilometers,
            steps: steps,
            coach: coach,
            currentPace: pace,
            heightFromStart: height
        )
    }

    /// Warm up 10:00, then Work 3:00 and an open Recover twice, then an open cool down.
    private var intervals: StepTracker {
        StepTracker(timeline: [
            PlannedIntervalStep(kind: .warmup, goal: .time(600), repetition: 1, repeatCount: 1),
            PlannedIntervalStep(kind: .work, goal: .time(180), repetition: 1, repeatCount: 2),
            PlannedIntervalStep(kind: .recovery, goal: .open, repetition: 1, repeatCount: 2),
            PlannedIntervalStep(kind: .work, goal: .distance(meters: 400), repetition: 2, repeatCount: 2),
            PlannedIntervalStep(kind: .recovery, goal: .open, repetition: 2, repeatCount: 2),
            PlannedIntervalStep(kind: .cooldown, goal: .open, repetition: 1, repeatCount: 1),
        ])
    }

    @Test func aFreeRunShowsTimeDistancePaceAndHeight() {
        let display = WatchRunDisplay(input())

        #expect(display.title == "FREE RUN")
        #expect(display.elapsed == "32:48")
        #expect(display.elapsedLabel == "ELAPSED")
        #expect(display.distance == "6.40")
        #expect(display.distanceUnit == "km")
        #expect(display.distanceLabel == "DISTANCE")
        #expect(display.lower == .pace(
            value: "5:12",
            unit: "min/km",
            footer: .init(symbol: "arrow.down", value: "43 m", detail: "below start")
        ))
    }

    @Test func heightReadsAboveOrLevelWithTheStart() {
        let above = WatchRunDisplay(input(height: 12.4))
        let level = WatchRunDisplay(input(height: 0.3))
        let none = WatchRunDisplay(input(height: nil))

        #expect(above.lower == .pace(value: "5:12", unit: "min/km", footer: .init(symbol: "arrow.up", value: "12 m", detail: "above start")))
        #expect(level.lower == .pace(value: "5:12", unit: "min/km", footer: .init(symbol: "arrow.left.and.right", value: "Level", detail: "with start")))
        #expect(none.lower == .pace(value: "5:12", unit: "min/km", footer: nil))
    }

    @Test func pausedSaysSoAndDropsThePace() {
        let display = WatchRunDisplay(input(status: .paused))
        var auto = input(status: .paused)
        auto.isAutoPaused = true

        #expect(display.title == "PAUSED")
        #expect(display.isPaused)
        #expect(display.lower == .pace(value: "–:––", unit: "min/km", footer: .init(symbol: "arrow.down", value: "43 m", detail: "below start")))
        #expect(WatchRunDisplay(auto).title == "AUTO-PAUSED")
    }

    @Test func anOpenStepShowsWhatsNextInPlaceOfThePace() {
        var steps = intervals
        _ = steps.update(elapsed: 600, meters: 1_900)
        _ = steps.update(elapsed: 780, meters: 2_600)
        let display = WatchRunDisplay(input(steps: steps))

        #expect(display.title == "RECOVER · 3/6")
        #expect(display.elapsedLabel == "ELAPSED")
        #expect(display.lower == .nextStep(.init(caption: "NEXT", value: "Work · 400 m")))
    }

    @Test func aTimedStepShowsThePaceAndTheTimeToTheNextStep() {
        var steps = intervals
        _ = steps.update(elapsed: 600, meters: 1_900)
        let display = WatchRunDisplay(input(elapsed: 623.4, meters: 1_990, steps: steps))

        #expect(display.title == "WORK · 2/6")
        #expect(display.lower == .pace(value: "5:12", unit: "min/km", footer: .init(caption: "NEXT", value: "Recover", detail: "in 2:37")))
    }

    @Test func aDistanceStepCountsDownTheMeters() {
        var steps = intervals
        _ = steps.update(elapsed: 600, meters: 1_900)
        _ = steps.update(elapsed: 780, meters: 2_600)
        _ = steps.endCurrentStep(elapsed: 900, meters: 2_800)
        let display = WatchRunDisplay(input(elapsed: 960, meters: 3_080.2, steps: steps))

        #expect(display.title == "WORK · 4/6")
        #expect(display.lower == .pace(value: "5:12", unit: "min/km", footer: .init(caption: "NEXT", value: "Recover", detail: "in 120 m")))
    }

    @Test func anOpenLastCoolDownRunsUntilTheFinishWithNoNextStep() {
        var steps = intervals
        _ = steps.update(elapsed: 600, meters: 1_900)
        _ = steps.update(elapsed: 780, meters: 2_600)
        _ = steps.endCurrentStep(elapsed: 900, meters: 2_800)
        _ = steps.update(elapsed: 1_000, meters: 3_200)
        _ = steps.endCurrentStep(elapsed: 1_100, meters: 3_400)
        let display = WatchRunDisplay(input(steps: steps))

        #expect(display.title == "COOL DOWN · 6/6")
        #expect(display.lower == .pace(value: "5:12", unit: "min/km", footer: .init(caption: "LAST STEP", value: "Cool down", detail: "until you finish")))
    }

    @Test func anOpenLastWalkStillWaitsForTheTap() {
        var steps = StepTracker(timeline: [
            PlannedIntervalStep(kind: .work, goal: .time(60), repetition: 1, repeatCount: 1),
            PlannedIntervalStep(kind: .recovery, goal: .open, repetition: 1, repeatCount: 1, isWalk: true),
        ])
        _ = steps.update(elapsed: 61, meters: 200)
        let display = WatchRunDisplay(input(steps: steps))

        #expect(display.title == "WALK · 2/2")
        #expect(display.lower == .nextStep(.init(caption: "NEXT", value: "Run as you like")))
    }

    @Test func doneStepsGoBackToTheFreeRunFooter() {
        var steps = StepTracker(timeline: [PlannedIntervalStep(kind: .work, goal: .time(60), repetition: 1, repeatCount: 1)])
        _ = steps.update(elapsed: 61, meters: 200)
        let display = WatchRunDisplay(input(steps: steps))

        #expect(display.title == "STEPS DONE")
        #expect(display.lower == .pace(value: "5:12", unit: "min/km", footer: .init(symbol: "arrow.down", value: "43 m", detail: "below start")))
    }

    @Test func aCoachSessionShowsItsGoalAndPaceRange() {
        let target = CoachWorkoutTarget(
            title: "Easy run", detail: "", notes: "", meters: 8_000, seconds: nil,
            pace: 290...305, effort: nil, runWalk: nil, isKeySession: false, isQuality: false
        )
        let display = WatchRunDisplay(input(coach: target))
        var timed = target
        timed.meters = nil
        timed.seconds = 40 * 60

        #expect(display.title == "EASY RUN")
        #expect(display.distanceLabel == "OF 8.00 KM")
        #expect(display.elapsedLabel == "ELAPSED")
        #expect(display.lower == .pace(value: "5:12", unit: "min/km", footer: .init(caption: "TARGET", value: "4:50–5:05", detail: "/km")))
        #expect(WatchRunDisplay(input(coach: timed)).elapsedLabel == "OF 40:00")
    }

    // MARK: Live readings

    @Test func currentPaceIsTheLast30SecondsOfRunning() throws {
        var pace = RecentPace()
        // 3 m/s for a minute, then 4 m/s (4:10 /km) for 40 seconds.
        for second in 0...100 {
            let meters = second <= 60 ? Double(second) * 3 : 180 + Double(second - 60) * 4
            pace.record(time: Double(second), meters: meters)
        }

        let now = try #require(pace.pace(at: 100))
        #expect(abs(now - 250) < 0.001)
        #expect(pace.pace(at: 111) == nil, "Stale after 10 s without a fix")
    }

    @Test func currentPaceWaitsForEnoughRunning() {
        var pace = RecentPace()
        pace.record(time: 0, meters: 0)
        pace.record(time: 3, meters: 10)
        #expect(pace.pace(at: 3) == nil)
        pace.record(time: 10, meters: 30)
        #expect(pace.pace(at: 10) == 10.0 / 30 * 1_000)
    }

    @Test func heartRateHistoryKeepsFifteenMinutes() {
        var history = HeartRateHistory()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        for second in stride(from: 0, through: 1_200, by: 10) {
            history.record(140, at: start.addingTimeInterval(Double(second)))
        }
        history.record(0, at: start.addingTimeInterval(1_205))

        let recent = history.recent(at: start.addingTimeInterval(1_200))
        #expect(recent.first?.date == start.addingTimeInterval(300))
        #expect(recent.last?.date == start.addingTimeInterval(1_200))
        #expect(history.points.count == recent.count)
    }

    @Test func gpsHeightCountsFromTheFirstUsableFix() {
        var height = GPSHeightFromStart()
        height.record(altitude: 50, verticalAccuracy: 40)
        #expect(height.change == nil)
        height.record(altitude: 100, verticalAccuracy: 8)
        height.record(altitude: 90, verticalAccuracy: -1)
        height.record(altitude: 57, verticalAccuracy: 10)
        #expect(height.change == -43)
    }
}
