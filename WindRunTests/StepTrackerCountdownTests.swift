//
//  StepTrackerCountdownTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The step tracker's countdown for timed and distance steps, which steps count as cut, and picking up a
/// saved step log.
@MainActor
struct StepTrackerCountdownTests {
    private func step(_ kind: IntervalStepKind, _ goal: IntervalGoal, isWalk: Bool = false) -> PlannedIntervalStep {
        PlannedIntervalStep(kind: kind, goal: goal, repetition: 1, repeatCount: 1, isWalk: isWalk)
    }

    // MARK: Countdown

    @Test func aDistanceStepTapsAtThirtyTwentyAndTenMetersLeft() {
        let tracker = StepTracker(timeline: [step(.work, .distance(meters: 400))])
        // 31 m left rounds up to 4 tens: not yet.
        #expect(tracker.countdown(elapsed: 0, meters: 369) == nil)
        #expect(tracker.countdown(elapsed: 0, meters: 370) == 3)
        #expect(tracker.countdown(elapsed: 0, meters: 371) == 3)
        #expect(tracker.countdown(elapsed: 0, meters: 381) == 2)
        #expect(tracker.countdown(elapsed: 0, meters: 395) == 1)
        #expect(tracker.countdown(elapsed: 0, meters: 400) == nil)
        #expect(tracker.countdown(elapsed: 0, meters: 450) == nil)
    }

    @Test func theTwoArgumentCountdownMatchesTheTimedOne() {
        let tracker = StepTracker(timeline: [step(.work, .time(120)), step(.recovery, .open)])
        for elapsed in [100, 116.5, 117.2, 118.4, 119.9, 120, 130] as [TimeInterval] {
            #expect(tracker.countdown(elapsed: elapsed, meters: 0) == tracker.countdown(elapsed: elapsed))
        }
        #expect(tracker.countdown(elapsed: 117.2, meters: 0) == 3)
        #expect(tracker.countdown(elapsed: 119.9, meters: 0) == 1)
    }

    @Test func anOpenStepHasNoCountdown() {
        let tracker = StepTracker(timeline: [step(.recovery, .open)])
        #expect(tracker.countdown(elapsed: 0, meters: 0) == nil)
        #expect(tracker.countdown(elapsed: 1_000, meters: 1_000) == nil)
    }

    @Test func aFinishedWorkoutHasNoCountdown() {
        var tracker = StepTracker(timeline: [step(.work, .distance(meters: 400))])
        _ = tracker.update(elapsed: 90, meters: 400)
        #expect(tracker.isFinished)
        #expect(tracker.countdown(elapsed: 90, meters: 400) == nil)
    }

    // MARK: Cut steps

    @Test func endingATimedStepBeforeItsGoalCutsIt() {
        var tracker = StepTracker(timeline: [step(.work, .time(120)), step(.recovery, .time(60))])
        _ = tracker.endCurrentStep(elapsed: 100, meters: 300)
        #expect(tracker.recorded.last?.cut == true)
    }

    @Test func endingAStepThatReachedItsGoalIsNotACut() {
        var tracker = StepTracker(timeline: [step(.work, .distance(meters: 400)), step(.recovery, .time(60))])
        // Not updated in between, so the step is still under way past its goal.
        _ = tracker.endCurrentStep(elapsed: 100, meters: 401)
        #expect(tracker.recorded.last?.cut == false)
    }

    @Test func endingAnOpenStepIsNeverACut() {
        var tracker = StepTracker(timeline: [step(.recovery, .open, isWalk: true), step(.work, .time(60))])
        _ = tracker.endCurrentStep(elapsed: 5, meters: 10)
        #expect(tracker.recorded.last?.cut == false)
    }

    @Test func finishingCutsTheStepUnderWayAndSkipsTheRest() {
        var tracker = StepTracker(timeline: [step(.work, .time(120)), step(.recovery, .time(60)), step(.work, .time(120))])
        tracker.finish(elapsed: 100, meters: 300)
        #expect(tracker.recorded.map(\.cut) == [true, true, true])
        #expect(tracker.isFinished)
    }

    @Test func finishingOnAnOpenStepKeepsItWhole() {
        var tracker = StepTracker(timeline: [step(.work, .time(60)), step(.cooldown, .open)])
        _ = tracker.update(elapsed: 60, meters: 200)
        tracker.finish(elapsed: 400, meters: 900)
        #expect(tracker.recorded.map(\.cut) == [false, false])
    }

    // MARK: Picking up a saved log

    @Test func resumingPicksUpAfterTheLastLoggedStep() {
        let timeline = [step(.work, .time(120)), step(.recovery, .time(60)), step(.work, .time(120))]
        let log = [RecordedStep(index: 0, startElapsed: 0, endElapsed: 125, startMeters: 0, endMeters: 400, cut: false)]
        let tracker = StepTracker(timeline: timeline, resumingFrom: log)
        #expect(tracker.index == 1)
        #expect(tracker.current == timeline[1])
        #expect(tracker.recorded == log)
        #expect(tracker.elapsedInStep(130) == 5)
        #expect(tracker.remaining(elapsed: 130, meters: 420) == .time(55))
        // 60 - (182.5 - 125) leaves 2.5 s, which rounds up to 3.
        #expect(tracker.countdown(elapsed: 182.5, meters: 0) == 3)
    }

    @Test func resumingADistanceStepMeasuresFromWhereTheLastEnded() {
        let timeline = [step(.work, .distance(meters: 400)), step(.recovery, .distance(meters: 200))]
        let log = [RecordedStep(index: 0, startElapsed: 0, endElapsed: 100, startMeters: 0, endMeters: 410, cut: false)]
        let tracker = StepTracker(timeline: timeline, resumingFrom: log)
        #expect(tracker.remaining(elapsed: 150, meters: 500) == .distance(meters: 110))
    }

    @Test func aFullLogResumesFinished() {
        let timeline = [step(.work, .time(120)), step(.recovery, .time(60))]
        let log = [
            RecordedStep(index: 0, startElapsed: 0, endElapsed: 120, startMeters: 0, endMeters: 400, cut: false),
            RecordedStep(index: 1, startElapsed: 120, endElapsed: 180, startMeters: 400, endMeters: 500, cut: false),
        ]
        let tracker = StepTracker(timeline: timeline, resumingFrom: log)
        #expect(tracker.index == timeline.count)
        #expect(tracker.isFinished)
        #expect(tracker.current == nil)
    }

    @Test func aLogPastTheTimelineIsClampedToItsEnd() {
        let timeline = [step(.work, .time(120))]
        let log = [RecordedStep(index: 4, startElapsed: 0, endElapsed: 120, startMeters: 0, endMeters: 400, cut: false)]
        let tracker = StepTracker(timeline: timeline, resumingFrom: log)
        #expect(tracker.index == 1)
        #expect(tracker.isFinished)
    }

    @Test func anEmptyLogStartsAtTheFirstStep() {
        let timeline = [step(.work, .time(120))]
        let tracker = StepTracker(timeline: timeline, resumingFrom: [])
        #expect(tracker.index == 0)
        #expect(tracker.elapsedInStep(30) == 30)
    }
}
