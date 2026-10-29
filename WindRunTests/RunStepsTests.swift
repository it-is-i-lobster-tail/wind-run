//
//  RunStepsTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// Steps recorded as they're run: timed, open and distance steps, ended early or skipped.
@MainActor
struct RunStepsTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func runWalkTimeline(repeats: Int = 3, walk: IntervalGoal = .time(60)) -> [PlannedIntervalStep] {
        (1...repeats).flatMap { repetition in
            [
                PlannedIntervalStep(kind: .work, goal: .time(120), repetition: repetition, repeatCount: repeats),
                PlannedIntervalStep(kind: .recovery, goal: walk, repetition: repetition, repeatCount: repeats, isWalk: true),
            ]
        }
    }

    // MARK: Step tracker

    @Test func timedStepsEndOnTheirOwnWithTheirRealTimes() {
        let timeline = runWalkTimeline(repeats: 1)
        var tracker = StepTracker(timeline: timeline)
        #expect(tracker.update(elapsed: 119, meters: 300) == nil)
        #expect(tracker.update(elapsed: 121, meters: 310) == .started(timeline[1]))
        #expect(tracker.update(elapsed: 182, meters: 400) == .finished)
        #expect(tracker.recorded.map(\.index) == [0, 1])
        #expect(tracker.recorded[0].seconds == 121)
        #expect(tracker.recorded[1].seconds == 61)
        #expect(tracker.recorded.allSatisfy { !$0.cut })
    }

    @Test func anOpenWalkBreakEndsOnTheTapWithAReminderOnce() {
        var tracker = StepTracker(timeline: runWalkTimeline(repeats: 1, walk: .open))
        _ = tracker.update(elapsed: 120, meters: 300)
        #expect(tracker.update(elapsed: 200, meters: 350) == nil)
        #expect(tracker.update(elapsed: 211, meters: 355) == .openReminder)
        #expect(tracker.update(elapsed: 240, meters: 360) == nil)
        _ = tracker.endCurrentStep(elapsed: 250, meters: 362)
        // The break as actually taken: 130 s, not cut, since it ends on the tap by design.
        #expect(tracker.recorded.last?.seconds == 130)
        #expect(tracker.recorded.last?.cut == false)
    }

    /// Brendon's workout: open warm up, 4 × (4 min work, 1:30 recover), open cool down. The last recover
    /// hands over to the cool down on its own, and the cool down, with nothing after it, never asks for a tap.
    @Test func anOpenCoolDownStartsOnItsOwnAndRunsToTheFinish() {
        let repeats = (1...4).flatMap { repetition in
            [
                PlannedIntervalStep(kind: .work, goal: .time(240), repetition: repetition, repeatCount: 4),
                PlannedIntervalStep(kind: .recovery, goal: .time(90), repetition: repetition, repeatCount: 4),
            ]
        }
        let warmUp = PlannedIntervalStep(kind: .warmup, goal: .open, repetition: 1, repeatCount: 1)
        let coolDown = PlannedIntervalStep(kind: .cooldown, goal: .open, repetition: 1, repeatCount: 1)
        var tracker = StepTracker(timeline: [warmUp] + repeats + [coolDown])

        #expect(tracker.waitsForTap)
        #expect(tracker.endCurrentStep(elapsed: 600, meters: 1_500) == repeats[0])
        // Each timed step ends on its own, a second at a time.
        let setEnd: TimeInterval = 600 + 4 * (240 + 90)
        var started: [PlannedIntervalStep] = []
        for second in stride(from: 601, through: setEnd, by: 1) {
            if case .started(let step) = tracker.update(elapsed: TimeInterval(second), meters: 1_500 + Double(second)) {
                started.append(step)
            }
        }
        #expect(started == Array(repeats.dropFirst()) + [coolDown])
        #expect(tracker.current == coolDown)
        #expect(tracker.runsUntilFinish)
        #expect(!tracker.waitsForTap)
        // No "tap when you're ready" reminder in the cool down, however long it goes on.
        #expect(tracker.update(elapsed: setEnd + 300, meters: 6_000) == nil)
        tracker.finish(elapsed: setEnd + 600, meters: 7_000)
        #expect(tracker.recorded.count == 10)
        #expect(tracker.recorded.last?.seconds == 600)
        #expect(tracker.recorded.last?.cut == false)
    }

    /// A walk break that ends the workout still ends on the tap, so the coach gets the break as taken.
    @Test func anOpenLastWalkBreakStillWaitsForTheTap() {
        var tracker = StepTracker(timeline: runWalkTimeline(repeats: 1, walk: .open))
        _ = tracker.update(elapsed: 120, meters: 300)
        #expect(tracker.isOnLastStep)
        #expect(tracker.waitsForTap)
        #expect(!tracker.runsUntilFinish)
    }

    @Test func endingAStepEarlyCutsIt() {
        let timeline = runWalkTimeline(repeats: 1)
        var tracker = StepTracker(timeline: timeline)
        let next = tracker.endCurrentStep(elapsed: 90, meters: 220)
        #expect(next == timeline[1])
        #expect(tracker.recorded.first?.cut == true)
        #expect(tracker.recorded.first?.seconds == 90)
    }

    @Test func finishingSkipsTheStepsLeft() {
        var tracker = StepTracker(timeline: runWalkTimeline(repeats: 2))
        _ = tracker.update(elapsed: 130, meters: 320)
        tracker.finish(elapsed: 150, meters: 330)
        #expect(tracker.recorded.count == 4)
        #expect(tracker.recorded[1].cut)
        #expect(tracker.recorded[2].cut && tracker.recorded[2].seconds == 0)
        #expect(tracker.isFinished)
    }

    @Test func distanceStepsEndByDistance() {
        let timeline = [PlannedIntervalStep(kind: .work, goal: .distance(meters: 400), repetition: 1, repeatCount: 1)]
        var tracker = StepTracker(timeline: timeline)
        #expect(tracker.remaining(elapsed: 30, meters: 150) == .distance(meters: 250))
        #expect(tracker.update(elapsed: 95, meters: 401) == .finished)
    }
}
