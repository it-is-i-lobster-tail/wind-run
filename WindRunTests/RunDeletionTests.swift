//
//  RunDeletionTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// Deleting a finished run: what goes with it, what stays, and when the coach is asked.
@MainActor
struct RunDeletionTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    // Each test gets its own store. It has to outlive the models in it.
    private let container = WindRunSchema.makeContainer(inMemory: true)
    private var context: ModelContext { container.mainContext }

    private func finishedRun() -> Run {
        let run = Run(kind: .intervals, startDate: start)
        context.insert(run)
        run.record(RouteSample(timestamp: start.addingTimeInterval(1), latitude: 0, longitude: 0))
        run.record(HeartRateSample(timestamp: start.addingTimeInterval(2), beatsPerMinute: 140))
        run.pause(at: start.addingTimeInterval(10))
        run.resume(at: start.addingTimeInterval(20))
        run.finish(at: start.addingTimeInterval(60))
        context.saveQuietly()
        return run
    }

    @Test func theWorkoutAndCoachSessionItFollowedStayButNoLongerListIt() throws {
        let plan = IntervalPlan(name: "Hills")
        let workout = CoachWorkout(kind: "easy", dayOffset: 0)
        context.insert(plan)
        context.insert(workout)
        let run = finishedRun()
        run.intervalPlanValue = plan
        run.coachWorkoutValue = workout
        context.saveQuietly()
        #expect(plan.runs.count == 1)
        #expect(workout.runs.count == 1)

        let state = RunDeletion(context: context, coachIsOn: false).delete(run, fromHealth: false)

        #expect(state == nil)
        #expect(try context.fetch(FetchDescriptor<Run>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<IntervalPlan>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<CoachWorkout>()).count == 1)
        #expect(plan.runs.isEmpty)
        #expect(workout.runs.isEmpty)
    }

    @Test func withTheCoachOnButNoPlanThereIsNothingToReplan() throws {
        let run = finishedRun()

        let state = RunDeletion(context: context, coachIsOn: true).delete(run, fromHealth: false)

        #expect(state == nil)
        #expect(try context.fetch(FetchDescriptor<Run>()).isEmpty)
    }

    @Test func theRouteHeartRateAndPausesGoWithTheRun() throws {
        let run = finishedRun()
        #expect(try context.fetch(FetchDescriptor<RouteSample>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<HeartRateSample>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<RunPause>()).count == 1)

        RunDeletion(context: context, coachIsOn: false).delete(run, fromHealth: false)

        #expect(try context.fetch(FetchDescriptor<RouteSample>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<HeartRateSample>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<RunPause>()).isEmpty)
    }
}
