//
//  RunStepsAndHeartRateTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// Steps recorded as they're run, and what the coach reads from a run: steps, walk breaks and heart rate.
@MainActor
struct RunStepsAndHeartRateTests {
    private let container = WindRunSchema.makeContainer(inMemory: true)
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

    // MARK: What the coach reads

    /// A run-walk run of 3 × (2 min run, 1 min walk) with steps as recorded, heart rate every 5 s.
    private func runWalkRun(walkSeconds: [TimeInterval] = [70, 55, 65], beatsPerMinute: (Int) -> Double = { _ in 140 }) -> Run {
        let plan = IntervalPlan(name: "Run-walk")
        container.mainContext.insert(plan)
        let block = plan.addBlock(repeatCount: 3)
        block.addStep(.work, goal: .time(120))
        block.addStep(.recovery, goal: .open, isWalk: true)

        let run = Run(kind: .intervals, startDate: start)
        container.mainContext.insert(run)
        run.intervalPlanValue = plan
        var elapsed: TimeInterval = 0
        var meters = 0.0
        var recorded: [RecordedStep] = []
        for (repeatIndex, walk) in walkSeconds.enumerated() {
            recorded.append(RecordedStep(index: repeatIndex * 2, startElapsed: elapsed, endElapsed: elapsed + 120, startMeters: meters, endMeters: meters + 330, cut: false))
            elapsed += 120
            meters += 330
            recorded.append(RecordedStep(index: repeatIndex * 2 + 1, startElapsed: elapsed, endElapsed: elapsed + walk, startMeters: meters, endMeters: meters + 90, cut: false))
            elapsed += walk
            meters += 90
        }
        run.saveStepLog(recorded)
        for second in stride(from: 0, through: Int(elapsed), by: 5) {
            run.record(HeartRateSample(timestamp: start.addingTimeInterval(TimeInterval(second)), beatsPerMinute: beatsPerMinute(second)))
        }
        run.finish(at: start.addingTimeInterval(elapsed))
        return run
    }

    @Test func walkBreaksCountTheirRealTime() {
        let run = runWalkRun()
        let logged = LoggedRun(run, track: nil, heartRateSettings: .off)

        #expect(abs((logged.walkingSeconds ?? 0) - 190) < 0.01)
        #expect(logged.steps?.count == 6)
        #expect(logged.steps?.map(\.isWork) == [true, false, true, false, true, false])
        #expect(logged.steps?.first?.seconds == 120)
        #expect(abs(logged.runningSeconds - 360) < 1)
    }

    @Test func aWalkStageSessionIsAllWalking() throws {
        let run = Run(kind: .coached, startDate: start)
        container.mainContext.insert(run)
        let workout = CoachWorkout(kind: SessionKind.walk.rawValue, dayOffset: 0)
        container.mainContext.insert(workout)
        run.coachWorkoutValue = workout
        run.finish(at: start.addingTimeInterval(25 * 60))

        let logged = LoggedRun(run, track: nil, heartRateSettings: .off)
        #expect(run.coachWorkout?.kind == SessionKind.walk.rawValue)
        // Dates round a little, so compare to the second.
        #expect(abs((logged.walkingSeconds ?? 0) - 25 * 60) < 0.01)
        #expect(logged.walkingSeconds == logged.movingSeconds)
        #expect(logged.steps == nil)
    }

    @Test func aPlainRunHasNoStepsOrWalking() {
        let run = Run(kind: .free, startDate: start)
        container.mainContext.insert(run)
        run.finish(at: start.addingTimeInterval(30 * 60))

        let logged = LoggedRun(run, track: nil, heartRateSettings: .off)
        #expect(logged.steps == nil)
        #expect(logged.walkingSeconds == nil)
        #expect(logged.heartRate == nil)
    }

    @Test func heartRateIsReadFromTheRunsSamples() throws {
        let run = runWalkRun()
        let settings = HeartRateSettings(device: .chestStrap, useForCoaching: true)
        let heartRate = try #require(LoggedRun(run, track: nil, heartRateSettings: settings).heartRate)

        #expect(heartRate.source == .chestStrap)
        #expect(heartRate.coverage > 0.95)
        #expect(!heartRate.implausible)
        #expect(heartRate.mean == 140)
        // Three run steps, each graded from its 2nd minute.
        #expect(heartRate.workSteps.count == 3)
        #expect(heartRate.workSteps.allSatisfy { $0.mean == 140 })
        // Step rate isn't recorded, so the cadence check is unknown and the run stays shown only.
        #expect(heartRate.cadenceLock == nil)
        #expect(HeartRateRules.badge(heartRate) == .shownOnly)
    }

    @Test func aJumpOf30BeatsIsImplausible() throws {
        let run = runWalkRun { $0 == 200 ? 175 : 140 }
        let heartRate = try #require(LoggedRun(run, track: nil, heartRateSettings: HeartRateSettings(device: .chestStrap)).heartRate)
        #expect(heartRate.implausible)
    }

    @Test func aWatchOnlyCountsSteadyStretchesAfterMinuteFive() {
        // Samples every 5 s for 20 minutes at 130, then 150 for the rest.
        let samples = stride(from: 0, through: 1_800, by: 5).map { second in
            RunHeartRateReading.Sample(elapsed: TimeInterval(second), beatsPerMinute: second <= 1_200 ? 130 : 150, date: start.addingTimeInterval(TimeInterval(second)))
        }
        let reading = RunHeartRateReading(samples: samples, movingSeconds: 1_800)
        let watch = reading.decisionGradeSpans(device: .appleWatch, steadyStretches: [.init(start: 0, end: 1_200), .init(start: 1_200, end: 1_440)])
        // The first stretch counts from minute 5; the second is under 5 minutes, so it doesn't count.
        #expect(watch == [.init(start: 300, end: 1_200)])
        #expect(reading.mean(in: watch) == 130)
        #expect(reading.decisionGradeSpans(device: .chestStrap, steadyStretches: []) == [.init(start: 300, end: 1_800)])
        #expect(reading.peak30s(in: [.init(start: 1_200, end: 1_800)]) == 150)
    }
}
