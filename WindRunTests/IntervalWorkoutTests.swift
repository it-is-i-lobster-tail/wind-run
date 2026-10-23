//
//  IntervalWorkoutTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// The runner's own interval workouts: building and saving them, changing one a run already used, taking
/// one away, the Lock Screen's step, and the copy the watch gets.
@MainActor
struct IntervalWorkoutTests {
    private let container = WindRunSchema.makeContainer(inMemory: true)
    private var context: ModelContext { container.mainContext }

    /// Open warm up, 3 × (3 min work, 90 s recover), a walk, then an open cool down: the shape Brendon
    /// described, with open steps at each end.
    private func openEndedDraft() -> IntervalDraft {
        IntervalDraft(name: "  Track night  ", blocks: [
            .single(.new(.warmup, open: true)),
            IntervalDraft.Block(repeatCount: 3, steps: [
                IntervalDraft.Step(choice: .work, goal: .time(180)),
                IntervalDraft.Step(choice: .recovery, goal: .time(90)),
            ], isRepeat: true),
            .single(IntervalDraft.Step(choice: .walk, goal: .time(120))),
            .single(.new(.cooldown, open: true)),
        ])
    }

    private func savedPlans() -> [IntervalPlan] {
        ((try? context.fetch(FetchDescriptor<IntervalPlan>())) ?? []).filter(\.isSavedWorkout)
    }

    // MARK: Step names

    @Test func everyChoiceIsACoachStepKind() {
        for choice in IntervalStepChoice.allCases {
            #expect(IntervalStepChoice(kind: choice.kind, isWalk: choice.isWalk) == choice)
        }
        #expect(IntervalStepChoice.walk.kind == .recovery)
        #expect(IntervalStepChoice.allCases.map(\.name) == ["Warm up", "Work", "Recover", "Walk", "Cool down"])
    }

    @Test func stepsAreNamedAsTheCoachNamesThem() {
        let walk = PlannedIntervalStep(kind: .recovery, goal: .open, repetition: 1, repeatCount: 1, isWalk: true)
        let work = PlannedIntervalStep(kind: .work, goal: .time(60), repetition: 1, repeatCount: 1)
        #expect(walk.name == "Walk")
        #expect(work.name == "Work")
        #expect(RunRecorder.spokenStep(walk) == "Walk. Tap when you're ready to run again.")
    }

    // MARK: Saving

    @Test func aDraftSavesAsAWorkoutOnTheIntervalsPage() {
        let plan = openEndedDraft().save(replacing: nil, in: context)

        #expect(plan.isSavedWorkout)
        #expect(plan.name == "Track night")
        let timeline = plan.timeline
        #expect(timeline.count == 9)
        #expect(timeline.first?.goal == .open)
        #expect(timeline.first?.kind == .warmup)
        #expect(timeline.filter { $0.kind == .work }.count == 3)
        #expect(timeline[7] == PlannedIntervalStep(kind: .recovery, goal: .time(120), repetition: 1, repeatCount: 1, isWalk: true))
        #expect(timeline.last?.goal == .open)
        #expect(IntervalDraft(plan).timeline == timeline)
    }

    @Test func aBlankNameIsMadeFromTheRepeats() {
        var draft = IntervalDraft.starter()
        #expect(draft.suggestedName == "4 × 3 min")
        #expect(draft.canSave)
        #expect(draft.save(replacing: nil, in: context).name == "4 × 3 min")

        draft.blocks = [.single(.new(.work, open: true))]
        #expect(draft.suggestedName == "Intervals")
    }

    @Test func aWorkoutNeedsAStep() {
        let draft = IntervalDraft(name: "Nothing", blocks: [IntervalDraft.Block(repeatCount: 3, steps: [], isRepeat: true)])
        #expect(!draft.canSave)
    }

    @Test func timesAndDistancesStayInRange() {
        #expect(IntervalDraft.clamped(.time(0)) == .time(5))
        #expect(IntervalDraft.clamped(.distance(meters: 10)) == .distance(meters: 50))
        #expect(IntervalDraft.clamped(.open) == .open)
    }

    // MARK: Changing and deleting

    @Test func aWorkoutNoRunUsedChangesInPlace() throws {
        let plan = openEndedDraft().save(replacing: nil, in: context)
        var draft = IntervalDraft(plan)
        draft.blocks.removeLast()
        draft.name = "Shorter"

        let saved = draft.save(replacing: plan, in: context)
        #expect(saved === plan)
        #expect(plan.name == "Shorter")
        #expect(plan.timeline.count == 8)
        // The old blocks went with the change.
        #expect(try context.fetch(FetchDescriptor<IntervalBlock>()).count == 3)
    }

    @Test func aWorkoutARunUsedIsKeptForThatRun() {
        let plan = openEndedDraft().save(replacing: nil, in: context)
        let run = Run(kind: .intervals)
        context.insert(run)
        run.intervalPlanValue = plan
        try? context.save()

        var draft = IntervalDraft(plan)
        draft.blocks = [.single(.new(.work))]
        let saved = draft.save(replacing: plan, in: context)

        #expect(saved !== plan)
        #expect(run.intervalPlan === plan)
        #expect(plan.timeline.count == 9)
        #expect(!plan.isSavedWorkout)
        #expect(savedPlans().map(\.name) == ["Track night"])
        #expect(saved.createdDateValue == plan.createdDateValue)
    }

    @Test func deletingKeepsTheStepsOfRunsDoneWithIt() throws {
        let used = openEndedDraft().save(replacing: nil, in: context)
        let unused = IntervalDraft.starter().save(replacing: nil, in: context)
        let run = Run(kind: .intervals)
        context.insert(run)
        run.intervalPlanValue = used
        try? context.save()

        used.remove()
        unused.remove()
        #expect(savedPlans().isEmpty)
        IntervalPlan.deleteRemoved(in: context)

        let left = try context.fetch(FetchDescriptor<IntervalPlan>())
        #expect(left.count == 1)
        #expect(left.first === used)
        #expect(run.intervalPlan?.timeline.count == 9)
    }

    @Test func theCoachsStepsAreNotSavedWorkouts() {
        let coachSteps = IntervalPlan.classicFiveByThree()
        context.insert(coachSteps)
        IntervalPlan.deleteRemoved(in: context)
        #expect(!coachSteps.isSavedWorkout)
        #expect(savedPlans().isEmpty)
        #expect(((try? context.fetch(FetchDescriptor<IntervalPlan>())) ?? []).count == 1)
    }

    @Test func theLastWorkoutRunComesFirst() {
        let older = IntervalDraft(name: "Older", blocks: [.single(.new(.work))]).save(replacing: nil, in: context)
        older.createdDateValue = Date(timeIntervalSince1970: 1_000)
        let newer = IntervalDraft(name: "Newer", blocks: [.single(.new(.work))]).save(replacing: nil, in: context)
        newer.createdDateValue = Date(timeIntervalSince1970: 2_000)
        #expect([older, newer].savedWorkouts.map(\.name) == ["Newer", "Older"])

        let run = Run(kind: .intervals, startDate: Date(timeIntervalSince1970: 3_000))
        context.insert(run)
        run.intervalPlanValue = older
        run.finish(at: Date(timeIntervalSince1970: 3_600))
        try? context.save()
        #expect([older, newer].savedWorkouts.map(\.name) == ["Older", "Newer"])
    }

    // MARK: Lock Screen

    private var lockScreenTimeline: [PlannedIntervalStep] {
        [
            PlannedIntervalStep(kind: .warmup, goal: .open, repetition: 1, repeatCount: 1),
            PlannedIntervalStep(kind: .work, goal: .time(180), repetition: 1, repeatCount: 1),
            PlannedIntervalStep(kind: .recovery, goal: .distance(meters: 400), repetition: 1, repeatCount: 1),
        ]
    }

    @Test func anOpenStepGetsANextButtonAndCountsUp() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let tracker = StepTracker(timeline: lockScreenTimeline)
        let state = RunRecorder.stepState(tracker, elapsed: 95, meters: 200, isGoing: true, at: now, unit: .kilometers)

        #expect(state.name == "Warm up")
        #expect(state.number == 1 && state.count == 3)
        #expect(state.nextTitle == "Next step")
        #expect(state.startDate == now.addingTimeInterval(-95))
        #expect(state.endDate == nil)

        let paused = RunRecorder.stepState(tracker, elapsed: 95, meters: 200, isGoing: false, at: now, unit: .kilometers)
        #expect(paused.startDate == nil)
        #expect(paused.detail == "1:35")
        #expect(paused.nextTitle == "Next step")
    }

    @Test func aTimedStepCountsDownWithoutANextButton() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        var tracker = StepTracker(timeline: lockScreenTimeline)
        _ = tracker.endCurrentStep(elapsed: 100, meters: 200)
        let state = RunRecorder.stepState(tracker, elapsed: 160, meters: 400, isGoing: true, at: now, unit: .kilometers)

        #expect(state.name == "Work")
        #expect(state.nextTitle == nil)
        #expect(state.startDate == now.addingTimeInterval(-60))
        #expect(state.endDate == now.addingTimeInterval(120))
    }

    @Test func aDistanceStepShowsTheDistanceLeft() {
        var tracker = StepTracker(timeline: lockScreenTimeline)
        _ = tracker.endCurrentStep(elapsed: 100, meters: 200)
        _ = tracker.update(elapsed: 280, meters: 900)
        let state = RunRecorder.stepState(tracker, elapsed: 300, meters: 1_000, isGoing: true, at: .now, unit: .kilometers)

        #expect(state.name == "Recover")
        #expect(state.detail == "\(RunFormat.distance(300, unit: .kilometers)) left")

        _ = tracker.update(elapsed: 400, meters: 1_400)
        let done = RunRecorder.stepState(tracker, elapsed: 400, meters: 1_400, isGoing: true, at: .now, unit: .kilometers)
        #expect(done.isFinished)
        #expect(done.nextTitle == nil)
    }

    // MARK: Watch

    @Test func theWatchRunsTheSameSteps() {
        let plan = openEndedDraft().save(replacing: nil, in: context)
        let sent = WatchSavedWorkout(plan)
        let received = WatchSavedWorkout.decode(WatchSavedWorkout.encode([sent]))
        #expect(received == [sent])

        let watch = WindRunSchema.makeContainer(inMemory: true)
        let copy = received[0].makePlan(in: watch.mainContext)
        #expect(copy.name == "Track night")
        #expect(copy.timeline == plan.timeline)
        #expect(received[0].timeline == plan.timeline)
        // The watch's copy is only for its run; the list stays the iPhone's.
        #expect(!copy.isSavedWorkout)
    }
}
