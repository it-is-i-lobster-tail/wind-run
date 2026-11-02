//
//  WatchSessionTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// Coach sessions run on the watch: the countdown and haptics at step changes, the session as the watch
/// gets it, and the run that comes back to the iPhone.
@MainActor
struct WatchSessionTests {
    private let phone = WindRunSchema.makeContainer(inMemory: true)
    private let watch = WindRunSchema.makeContainer(inMemory: true)
    private let day = Date(timeIntervalSince1970: 1_800_000_000)
    private let sessionID = UUID()

    // MARK: Countdown and haptics

    @Test func aTimedStepCountsDownItsLastThreeSeconds() {
        let timeline = [
            PlannedIntervalStep(kind: .work, goal: .time(120), repetition: 1, repeatCount: 1),
            PlannedIntervalStep(kind: .recovery, goal: .open, repetition: 1, repeatCount: 1),
        ]
        var tracker = StepTracker(timeline: timeline)
        #expect(tracker.countdown(elapsed: 116.5) == nil)
        #expect(tracker.countdown(elapsed: 117.2) == 3)
        #expect(tracker.countdown(elapsed: 118.4) == 2)
        #expect(tracker.countdown(elapsed: 119.9) == 1)
        _ = tracker.update(elapsed: 120, meters: 400)
        // An open step has no end to count down to.
        #expect(tracker.countdown(elapsed: 500) == nil)
    }

    @Test func distanceStepsHaveNoCountdown() {
        let tracker = StepTracker(timeline: [PlannedIntervalStep(kind: .work, goal: .distance(meters: 400), repetition: 1, repeatCount: 1)])
        #expect(tracker.countdown(elapsed: 90) == nil)
    }

    @Test func workStepsFeelDifferentFromEasyOnes() {
        #expect(StepHaptic.starting(PlannedIntervalStep(kind: .work, goal: .time(60), repetition: 1, repeatCount: 1)) == .work)
        #expect(StepHaptic.starting(PlannedIntervalStep(kind: .recovery, goal: .time(60), repetition: 1, repeatCount: 1)) == .easy)
        #expect(StepHaptic.starting(PlannedIntervalStep(kind: .warmup, goal: .time(60), repetition: 1, repeatCount: 1)) == .easy)
        #expect(StepHaptic.starting(PlannedIntervalStep(kind: .work, goal: .time(60), repetition: 1, repeatCount: 1, isWalk: true)) == .easy)
    }

    // MARK: The session on the watch

    /// The iPhone's copy of a 5 × 3 min session planned for `day`.
    private func phoneWorkout() -> CoachWorkout {
        let context = phone.mainContext
        let plan = IntervalPlan.classicFiveByThree()
        context.insert(plan)
        let workout = CoachWorkout(sessionID: sessionID, kind: "intervals", dayOffset: 2)
        context.insert(workout)
        workout.update(
            kind: "intervals",
            dayOffset: 2,
            date: day,
            order: 0,
            status: "planned",
            target: CoachWorkoutTarget(
                title: "5 × 3 min",
                detail: "10 min easy, 5 × 3 min hard with 2 min jogs, 10 min easy",
                notes: "",
                meters: nil,
                seconds: 45 * 60,
                pace: 250...262,
                effort: 7...8,
                runWalk: nil,
                isKeySession: true,
                isQuality: true
            )
        )
        workout.setIntervalPlan(plan)
        workout.setStepsSignature("five-by-three")
        context.saveQuietly()
        return workout
    }

    @Test func theWatchRunsTheSameStepsAsTheIPhone() throws {
        let workout = phoneWorkout()
        let session = try #require(WatchCoachSession(workout))
        let received = WatchCoachSession.decode(WatchCoachSession.encode([session]))
        #expect(received == [session])

        let copy = try #require(received.first).makeWorkout(in: watch.mainContext)
        #expect(copy.sessionID == sessionID)
        #expect(copy.stepsSignature == "five-by-three")
        #expect(copy.target.pace == 250...262)
        #expect(copy.intervalPlan?.timeline == workout.intervalPlan?.timeline)
        #expect(copy.intervalPlan?.timeline.count == 12)
    }

    @Test func aSessionWithoutStepsHasNoPlanOnTheWatch() throws {
        let workout = phoneWorkout()
        workout.setIntervalPlan(nil)
        let session = try #require(WatchCoachSession(workout))
        #expect(session.blocks.isEmpty)
        #expect(session.makeWorkout(in: watch.mainContext).intervalPlan == nil)
    }

    // MARK: The run back on the iPhone

    /// A coached run on the watch: two steps done, a route of a few fixes and some heart rate.
    private func watchRun(signature: String = "five-by-three") throws -> Run {
        let session = try #require(WatchCoachSession(phoneWorkout()))
        let context = watch.mainContext
        let workout = session.makeWorkout(in: context)
        workout.setStepsSignature(signature)
        let run = Run(kind: .coached, startDate: day)
        context.insert(run)
        run.coachWorkoutValue = workout
        run.intervalPlanValue = workout.intervalPlan
        for second in stride(from: 0, through: 60, by: 10) {
            let time = day.addingTimeInterval(TimeInterval(second))
            run.record(RouteSample(timestamp: time, latitude: 51.5 + Double(second) * 0.00003, longitude: -0.12, horizontalAccuracy: 5))
            run.record(HeartRateSample(timestamp: time, beatsPerMinute: 150, source: .appleWatch))
        }
        run.saveStepLog([
            RecordedStep(index: 0, startElapsed: 0, endElapsed: 40, startMeters: 0, endMeters: 130, cut: false),
            RecordedStep(index: 1, startElapsed: 40, endElapsed: 60, startMeters: 130, endMeters: 200, cut: true),
        ])
        run.finish(at: day.addingTimeInterval(60))
        return run
    }

    @Test func aCoachedWatchRunJoinsTheIPhoneLinkedToItsSession() throws {
        let run = try watchRun()
        let record = try #require(WatchRunRecord(run))
        let data = try #require(record.encoded())
        let received = try #require(WatchRunRecord.decode(data))

        let inserted = try #require(received.insert(into: phone.mainContext))
        #expect(inserted.runID == run.runID)
        #expect(inserted.status == .complete)
        #expect(inserted.kind == .coached)
        #expect(inserted.route.count == run.route.count)
        #expect(abs(inserted.distanceMeters - run.distanceMeters) < 0.001)
        #expect(inserted.heartRateSamples.count == run.heartRateSamples.count)
        #expect(inserted.heartRateSamples.first?.source == .appleWatch)
        #expect(inserted.coachWorkout?.sessionID == sessionID)
        #expect(inserted.coachWorkout?.isDone == true)
        #expect(inserted.stepLog == run.stepLog)
        #expect(inserted.intervalPlan?.timeline.count == 12)
    }

    @Test func theSameRunSentTwiceIsAddedOnce() throws {
        let record = try #require(WatchRunRecord(try watchRun()))
        #expect(record.insert(into: phone.mainContext) != nil)
        #expect(record.insert(into: phone.mainContext) == nil)
        #expect(try phone.mainContext.fetchCount(FetchDescriptor<Run>()) == 1)
    }

    @Test func stepsRunFromOtherStepsAreLeftOff() throws {
        // The session's steps changed on the iPhone after the watch got them.
        let record = try #require(WatchRunRecord(try watchRun(signature: "older-steps")))
        let inserted = try #require(record.insert(into: phone.mainContext))
        #expect(inserted.coachWorkout?.sessionID == sessionID)
        #expect(inserted.stepLog.isEmpty)
        #expect(inserted.intervalPlan == nil)
    }

    @Test func aRunStillGoingIsNotSent() {
        let run = Run(kind: .coached, startDate: day)
        watch.mainContext.insert(run)
        #expect(WatchRunRecord(run) == nil)
    }
}
