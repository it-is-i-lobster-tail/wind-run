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
final class IntervalWorkoutTests {
    private let container = WindRunSchema.makeContainer(inMemory: true)
    private var context: ModelContext { container.mainContext }
    /// Where this device notes the workouts it took off the page.
    private let suiteName = "IntervalWorkoutTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    /// Open warm up, 3 × (3 min work, 90 s recover), a walk, then an open cool down: the shape the owner
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
        let coolDown = PlannedIntervalStep(kind: .cooldown, goal: .open, repetition: 1, repeatCount: 1)
        #expect(RunRecorder.spokenStep(coolDown, runsUntilFinish: true) == "Cool down. Finish the run when you're done.")
    }

    @Test func theWorkoutPageSaysHowOpenStepsEnd() {
        // The draft's own timeline, the same as the saved workout's, so this test stays out of the store.
        let timeline = openEndedDraft().timeline
        #expect(IntervalWorkoutView.openStepNote(timeline)?.hasSuffix("The last one runs until you finish.") == true)
        #expect(IntervalWorkoutView.openStepNote(Array(timeline.dropFirst())) == "The last step runs until you finish.")
        #expect(IntervalWorkoutView.openStepNote(Array(timeline.dropLast())) == "A step until Next ends when you tap Next on the run screen, your Lock Screen or your Apple Watch.")
        #expect(IntervalWorkoutView.openStepNote(Array(timeline.dropFirst().dropLast())) == nil)
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
        #expect(draft.suggestedName(unit: .kilometers) == "4 × 3 min")
        #expect(draft.canSave)
        #expect(draft.save(replacing: nil, in: context).name == "4 × 3 min")

        draft.blocks = [.single(.new(.work, open: true))]
        #expect(draft.suggestedName(unit: .kilometers) == "Intervals")
    }

    /// A mile runner's quarters are named in miles, not "402 m", since the name stays with the workout.
    @Test func aBlankNameIsInTheRunnersUnit() {
        func repeats(_ meters: Double) -> IntervalDraft {
            IntervalDraft(name: "", blocks: [IntervalDraft.Block(repeatCount: 8, steps: [
                IntervalDraft.Step(choice: .work, goal: .distance(meters: meters)),
                IntervalDraft.Step(choice: .recovery, goal: .time(90)),
            ], isRepeat: true)])
        }
        #expect(repeats(402.336).suggestedName(unit: .miles) == "8 × 0.25 mi")
        #expect(repeats(1_609.344).suggestedName(unit: .miles) == "8 × 1 mi")
        #expect(repeats(400).suggestedName(unit: .kilometers) == "8 × 400 m")
        #expect(repeats(1_600).suggestedName(unit: .kilometers) == "8 × 1.6 km")
        #expect(repeats(402.336).save(replacing: nil, unit: .miles, in: context).name == "8 × 0.25 mi")
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
        let saved = draft.save(replacing: plan, in: context, defaults: defaults)

        #expect(saved !== plan)
        #expect(run.intervalPlan === plan)
        #expect(plan.timeline.count == 9)
        #expect(!plan.isSavedWorkout)
        #expect(savedPlans().map(\.name) == ["Track night"])
        // The run isn't finished, so the original was never run and the copy keeps its date.
        #expect(saved.createdDateValue == plan.createdDateValue)
        // The original is kept for its run, and this device sweeps it once the run is gone.
        #expect(!RemovedIntervalPlans(defaults: defaults).isEmpty)
    }

    /// Changing the workout run every week keeps it at the top, rather than sinking to when it was made.
    @Test func aChangedWorkoutKeepsItsPlaceInTheList() {
        let weekly = IntervalDraft(name: "Weekly", blocks: [.single(.new(.work))]).save(replacing: nil, in: context)
        weekly.createdDateValue = Date(timeIntervalSince1970: 1_000)
        let newer = IntervalDraft(name: "Newer", blocks: [.single(.new(.work))]).save(replacing: nil, in: context)
        newer.createdDateValue = Date(timeIntervalSince1970: 2_000)
        let run = Run(kind: .intervals, startDate: Date(timeIntervalSince1970: 3_000))
        context.insert(run)
        run.intervalPlanValue = weekly
        run.finish(at: Date(timeIntervalSince1970: 3_600))
        try? context.save()

        var draft = IntervalDraft(weekly)
        draft.blocks.append(.single(.new(.cooldown)))
        let changed = draft.save(replacing: weekly, in: context, defaults: defaults)

        #expect(changed !== weekly)
        #expect(changed.createdDateValue == Date(timeIntervalSince1970: 3_000))
        #expect(savedPlans().savedWorkouts.map(\.name) == ["Weekly", "Newer"])
    }

    @Test func deletingKeepsTheStepsOfRunsDoneWithIt() throws {
        let used = openEndedDraft().save(replacing: nil, in: context)
        let unused = IntervalDraft.starter().save(replacing: nil, in: context)
        let run = Run(kind: .intervals)
        context.insert(run)
        run.intervalPlanValue = used
        try? context.save()

        used.remove(defaults: defaults)
        unused.remove(defaults: defaults)
        #expect(savedPlans().isEmpty)
        #expect(RemovedIntervalPlans(defaults: defaults).date(of: unused.persistentModelID) != nil)
        // Kept for a day, for runs done with them on another device to sync here first.
        IntervalPlan.deleteRemoved(in: context, defaults: defaults)
        #expect(try context.fetch(FetchDescriptor<IntervalPlan>()).count == 2)

        IntervalPlan.deleteRemoved(in: context, now: .now + RemovedIntervalPlans.delay + 1, defaults: defaults)
        let left = try context.fetch(FetchDescriptor<IntervalPlan>())
        #expect(left.count == 1)
        #expect(left.first === used)
        #expect(run.intervalPlan?.timeline.count == 9)
    }

    /// A workout that reached this device already taken off the page, through iCloud, may have runs still on
    /// their way, so only the device that took it off deletes it.
    @Test func aWorkoutTakenOffElsewhereIsntDeletedHere() throws {
        let fromAnotherDevice = IntervalDraft.starter().save(replacing: nil, in: context)
        fromAnotherDevice.isCustomValue = false
        try context.save()

        IntervalPlan.deleteRemoved(in: context, now: .now + RemovedIntervalPlans.delay * 30, defaults: defaults)
        #expect(try context.fetch(FetchDescriptor<IntervalPlan>()).count == 1)
    }

    @Test func aRepeatCountBelowOneStillRunsOnce() {
        let plan = IntervalPlan(name: "Old")
        let block = plan.addBlock()
        block.addStep(.work, goal: .time(60))
        block.repeatCountValue = 0
        #expect(block.repeatCount == 1)
        #expect(plan.timeline.count == 1)
    }

    @Test func theCoachsStepsAreNotSavedWorkouts() {
        let coachSteps = IntervalPlan.classicFiveByThree()
        context.insert(coachSteps)
        IntervalPlan.deleteRemoved(in: context, defaults: defaults)
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

    // MARK: Length

    private func step(_ kind: IntervalStepKind, _ goal: IntervalGoal, isWalk: Bool = false) -> PlannedIntervalStep {
        PlannedIntervalStep(kind: kind, goal: goal, repetition: 1, repeatCount: 1, isWalk: isWalk)
    }

    @Test func aTimedWorkoutShowsItsMinutes() {
        #expect(RunFormat.intervalLength(IntervalPlan.classicFiveByThree().timeline, unit: .kilometers) == "45 min")
    }

    /// Open ends are named, so 22 timed minutes don't read as the whole workout.
    @Test func openEndsAreNamedBesideTheTimedMinutes() {
        var timeline = [step(.warmup, .open)]
        for _ in 1...4 {
            timeline += [step(.work, .time(240)), step(.recovery, .time(90))]
        }
        timeline.append(step(.cooldown, .open))
        #expect(RunFormat.intervalLength(timeline, unit: .kilometers) == "22 min + warm up and cool down until Next")
        #expect(RunFormat.intervalLength(Array(timeline.dropLast()), unit: .kilometers) == "22 min + warm up until Next")
    }

    @Test func distancesAndOtherOpenStepsAreCountedOnTheirOwn() {
        let timeline = [step(.work, .time(180)), step(.recovery, .distance(meters: 400)), step(.recovery, .open, isWalk: true), step(.cooldown, .open)]
        #expect(RunFormat.intervalLength(timeline, unit: .kilometers) == "3 min + 400 m + 2 steps until Next")
        #expect(RunFormat.intervalLength([step(.work, .open)], unit: .kilometers) == "1 step until Next")
    }

    /// Miles stay in miles, so a quarter reads as one, and what's left of a step rounds up.
    @Test func stepDistancesAreInTheRunnersUnit() {
        #expect(RunFormat.goal(.distance(meters: 402.336), unit: .miles) == "0.25 mi")
        #expect(RunFormat.goal(.distance(meters: 400), unit: .kilometers) == "400 m")
        #expect(RunFormat.goal(.distance(meters: 349.2), unit: .kilometers, rounding: .up) == "350 m")
        #expect(RunFormat.goal(.open, unit: .kilometers) == "Until Next")
        #expect(IntervalSummary.step(.cooldown, goal: .open, unit: .kilometers) == "cool down until Next")
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

    @Test func anOpenLastStepHasNoNextButton() {
        let now = Date(timeIntervalSinceReferenceDate: 10_000)
        let timeline = lockScreenTimeline + [PlannedIntervalStep(kind: .cooldown, goal: .open, repetition: 1, repeatCount: 1)]
        var tracker = StepTracker(timeline: timeline)
        _ = tracker.endCurrentStep(elapsed: 100, meters: 200)
        _ = tracker.update(elapsed: 280, meters: 900)
        #expect(tracker.update(elapsed: 300, meters: 1_400) == .started(timeline[3]))
        let state = RunRecorder.stepState(tracker, elapsed: 360, meters: 1_600, isGoing: true, at: now, unit: .kilometers)

        #expect(state.name == "Cool down")
        #expect(state.nextTitle == nil)
        #expect(state.startDate == now.addingTimeInterval(-60))
        #expect(state.endDate == nil)
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
