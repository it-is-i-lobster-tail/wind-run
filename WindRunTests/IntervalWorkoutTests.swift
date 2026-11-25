//
//  IntervalWorkoutTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
import UIKit
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

    /// Warm-up until Next, 3 × (3 min work, 90 s recover), then a cooldown until Next: the owner's shape,
    /// with open parts at each end.
    private func openEndedDraft() -> WorkoutDraft {
        WorkoutDraft(
            name: "  Track night  ",
            warmup: .open,
            main: .intervals(.init(work: .time(180), recovery: .time(90), repeats: 3)),
            cooldown: .open
        )
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

    @Test func theWorkoutPageSaysHowOpenPartsEnd() {
        // The draft's own timeline, the same as the saved workout's, so this test stays out of the store.
        let timeline = openEndedDraft().timeline
        #expect(SavedWorkoutView.openStepNote(timeline)?.hasSuffix("The last one runs until you finish.") == true)
        #expect(SavedWorkoutView.openStepNote(Array(timeline.dropFirst())) == "The last part runs until you finish.")
        #expect(SavedWorkoutView.openStepNote(Array(timeline.dropLast())) == "A part until Next ends when you tap Next on the run screen, your Lock Screen or your Apple Watch.")
        #expect(SavedWorkoutView.openStepNote(Array(timeline.dropFirst().dropLast())) == nil)
    }

    // MARK: Workout icons
    @Test func iconMatchingPrefersWorkoutMeaningToTheWordInterval() {
        let examples = [
            "Really Really Hard interval": "flame.fill", "Hill repeats": "mountain.2.fill",
            "Easy recovery": "leaf.fill", "5 × 3 min": "repeat", "123": "figure.run",
            "": "figure.run", "Unfamiliar name": "figure.run"
        ]
        for (name, icon) in examples {
            #expect(WorkoutIconMatcher.match(name) { _, _ in .infinity } == icon)
        }
        #expect(WorkoutIconMatcher.match("Sunday unwind") { _, example in
            example == "relaxed recovery jog" ? 0.2 : 0.9
        } == "leaf.fill")
        #expect(WorkoutIconMatcher.match("Sunday unwind") { _, _ in 0.9 } == "figure.run")
        #expect(WorkoutIconMatcher.match("Unfamiliar name", fallback: WorkoutSport.cycling.systemImage) { _, _ in .infinity } == "figure.outdoor.cycle")
        for (name, expected) in [("Weekend hike", "figure.hiking"), ("Stationary bike", "figure.indoor.cycle"),
                                 ("Sunrise", "sunrise.fill"), ("Yoga intervals", "figure.yoga")] {
            #expect(WorkoutIconMatcher.match(name) { _, _ in .infinity } == expected)
        }
    }

    @Test func everyWorkoutNicknameSelectsAnAvailableIconWithoutAnEmbedding() {
        for (id, names) in WorkoutNickname.phrases {
            #expect(WorkoutIcon.identifiers.contains(id))
            for name in names {
                #expect(WorkoutIconMatcher.match(name) { _, _ in .infinity } == id, "Unexpected icon for \(name)")
            }
        }
        let examples = [
            "FUN!!": "party.popper.fill", "silly-goose shuffle": "workout.goose",
            "Friday café ride": "cup.and.saucer.fill", "coffee yap walk": "cup.and.saucer.fill",
            "fun on two wheels": "party.popper.fill", "my functional training": "figure.strengthtraining.functional",
            "fundraiser": WorkoutIcon.fallback,
        ]
        for (name, expected) in examples {
            #expect(WorkoutIconMatcher.match(name) { _, _ in .infinity } == expected)
        }
    }

    @Test func everyPickerTitleOwnsItsExactMatch() {
        for entry in WorkoutSymbolEntry.sections.flatMap(\.entries) {
            #expect(WorkoutIconMatcher.match(entry.title) { _, _ in .infinity } == entry.id)
            #expect(WorkoutSymbolEntry.search(entry.title).first?.entries.first?.id == entry.id)
        }
    }

    @Test func workoutNamesAndPickerAgreeOnTheMostSpecificSymbol() {
        let cases = [
            "Big": "workout.elephant", "Big Run": "workout.elephant", "Big Cat": "workout.cheetah",
            "Big Hills": "mountain.2.fill", "Light": "leaf.fill", "Light Jog": "leaf.fill",
            "First Light": "sunrise.fill", "Light Rain": "cloud.rain",
            "Race": "flag.pattern.checkered", "Fast Run": "workout.cheetah", "🐆 Run": "workout.cheetah", "Fast Swimming": "workout.cheetah",
            "Fast Hiking": "workout.cheetah", "Fast Finish": "bolt.fill", "Gotta Go Fast": "hare.fill",
            "Rain Run": "cloud.rain", "Geese Run": "workout.goose", "Snow Run": "snowflake",
            "Track Meet": "figure.track.and.field", "Speed Up": "forward.fill", "Surges": "forward.fill",
            "Five by a mile": "repeat", "Billat 30/30s": "repeat", "5 × ½ mile": "repeat",
            "4x(400 on / 200 float)": "repeat", "Headlamp miles": "moon.stars.fill",
            "Eight before brunch": "fork.knife", "Takeout Pickup Shakeout": "fork.knife",
            "Sunday 12": "road.lanes", "Sun LR 90 min rolling": "road.lanes",
            "Last 20 min at MP": "target", "Dual meet mile + 2 mile": "figure.track.and.field",
            "Ten miles with the club": "person.2.fill", "One lap with the dog": "dog",
            "Boardwalk to the Bluff": "map", "The Quarry Circuit": "map", "From town to campus": "map",
            "Sunday run with the stroller": "workout.stroller", "First miles of vacation": "workout.vacation",
            "Back Past the Beavers": "workout.beaver", "Miles Through the Mist": "workout.mist",
            "Mist on the Greenway": "workout.mist", "Library Return Run": "workout.library",
            "The After-Nap 5K": "workout.nap", "The One Before the Dentist": "workout.dentist",
            "Run to Meet the Train": "workout.train",
            "Racing": "flag.pattern.checkered", "Steady 45": "metronome", "8x600": "repeat",
            "Four by five minutes": "repeat", "45 on / 60 off": "repeat", "Negative split": "forward.fill",
            "Cycling": "figure.outdoor.cycle", "Cadence drills": "metronome", "Out and back": "map",
            "12x200": "figure.track.and.field", "12 × 200": "figure.track.and.field",
            "12 x 200": "figure.track.and.field", "PR": "medal", "Butterfly stroke": "figure.pool.swim"
        ]
        for (name, symbol) in cases {
            #expect(WorkoutIconMatcher.match(name) { _, _ in .infinity } == symbol)
            #expect(WorkoutSymbolEntry.search(name).first?.entries.first?.id == symbol)
        }
        for (query, unwanted) in [("ant", "workout.elephant"), ("rain", "brain"), ("fast run", "mountain.2.fill")] {
            #expect(!WorkoutSymbolEntry.search(query).flatMap(\.entries).contains { $0.id == unwanted })
        }
        #expect(WorkoutSymbolEntry.search("chee").first?.entries.first?.id == "workout.cheetah")
        for (word, symbol) in [("evening", "sunset.fill"), ("jump", "figure.jumprope"), ("kick", "figure.kickboxing")] {
            #expect(WorkoutSymbolEntry.search(word).flatMap(\.entries).contains { $0.id == symbol })
            #expect(WorkoutSymbolEntry.bestMatch([word]) == nil)
        }
    }

    @Test func catalogContainsRenderableSymbolsAndLegacyEmojiRevertToAutomatic() {
        let ids = WorkoutSymbolGroup.all.flatMap(\.symbols)
        #expect(ids.count == Set(ids).count)
        #expect(ids.count == 108)
        #expect(!ids.contains("bicycle.circle.fill"))
        #expect(WorkoutIcon.supported("bicycle.circle.fill") == "bicycle.circle.fill")
        for name in ["Fast", "FAST!", "Fast Run", "cheta"] {
            #expect(WorkoutIconMatcher.match(name) { _, _ in .infinity } == "workout.cheetah")
        }
        #expect(WorkoutSymbolEntry.search("Fast").first?.entries.first?.id == "workout.cheetah")
        #expect(WorkoutIconMatcher.match("Fast Finish") { _, _ in .infinity } == "bolt.fill")
        let missing = ids.filter { id in
            if id.hasPrefix("workout.") { return UIImage(named: id)?.isSymbolImage != true }
            return UIImage(systemName: id) == nil
        }
        #expect(missing.isEmpty)
        #expect(WorkoutSymbolEntry.search("stationary bike").flatMap(\.entries).contains { $0.id == "figure.indoor.cycle" })
        #expect(WorkoutSymbolEntry.search("intensity").flatMap(\.entries).contains { $0.id == "flame.fill" })
        let animals = Set(WorkoutSymbolEntry.search("animals").flatMap(\.entries).map(\.id))
        #expect(animals.isSuperset(of: ["hare.fill", "tortoise.fill", "dog", "teddybear", "workout.snail", "workout.goose"]))
        #expect(WorkoutSymbolEntry.search("cafe ride").flatMap(\.entries).contains { $0.id == "cup.and.saucer.fill" })
        #expect(WorkoutSymbolEntry.search("qzqzqz").isEmpty)
        let plan = IntervalPlan(name: "Weekend Hike")
        plan.iconIsManualValue = true
        plan.iconValue = "🏃🏽‍♀️"
        #expect(plan.workoutSymbol == nil)
        #expect(WorkoutDraft(plan).manualIcon == nil)
        #expect(WatchSavedWorkout(plan).icon == nil)
    }

    @Test func iconsSurviveRenamesWatchSyncAndEditingUsedPlans() throws {
        let original = openEndedDraft().save(replacing: nil, in: context, defaults: defaults, automaticIcon: "bolt.fill")
        var edit = WorkoutDraft(original)
        edit.name = "Hill repeats"
        edit.manualIcon = "figure.hiking"
        #expect(original.iconValue == "bolt.fill")
        let run = Run(kind: .intervals)
        context.insert(run)
        run.intervalPlanValue = original
        let saved = edit.save(replacing: original, in: context, defaults: defaults, automaticIcon: "mountain.2.fill")
        #expect(run.intervalPlan?.iconValue == "bolt.fill")
        var reopened = WorkoutDraft(saved)
        #expect(reopened.manualIcon == "figure.hiking")
        reopened.name = "Easy recovery"
        let renamed = reopened.save(replacing: saved, in: context, defaults: defaults, automaticIcon: "leaf.fill")
        let data = WatchSavedWorkout.encode([WatchSavedWorkout(renamed)])
        let watch = try #require(WatchSavedWorkout.decode(data).first)
        #expect(watch.makePlan(in: context).iconValue == "figure.hiking")
        reopened.manualIcon = nil
        let automatic = reopened.save(replacing: renamed, in: context, defaults: defaults, automaticIcon: "leaf.fill")
        #expect(automatic.iconValue == "leaf.fill")
        #expect(WorkoutDraft(automatic).manualIcon == nil)

        let legacy = Data(#"[{"name":"Old","createdDate":0,"blocks":[]}]"#.utf8)
        let old = try #require(WatchSavedWorkout.decode(legacy).first)
        #expect(old.icon == nil)
    }

    // MARK: The three parts

    @Test func aDraftSavesAsWarmupMainAndCooldown() {
        let plan = openEndedDraft().save(replacing: nil, in: context)

        #expect(plan.isSavedWorkout)
        #expect(plan.name == "Track night")
        #expect(plan.blocks.count == 3)
        let timeline = plan.timeline
        #expect(timeline.count == 8)
        #expect(timeline.first == PlannedIntervalStep(kind: .warmup, goal: .open, repetition: 1, repeatCount: 1))
        #expect(timeline.filter { $0.kind == .work }.count == 3)
        #expect(timeline[2] == PlannedIntervalStep(kind: .recovery, goal: .time(90), repetition: 1, repeatCount: 3))
        #expect(timeline.last == PlannedIntervalStep(kind: .cooldown, goal: .open, repetition: 1, repeatCount: 1))
        #expect(WorkoutDraft(plan) == WorkoutDraft(name: "Track night", warmup: .open, main: openEndedDraft().main, cooldown: .open))
        #expect(WorkoutDraft.fits(plan))
    }

    @Test func everyMainPartRoundTrips() {
        let mains: [WorkoutMain] = [
            .time(45 * 60),
            .distance(meters: 5_000),
            .free,
            .intervals(.init(work: .distance(meters: 400), recovery: .open, repeats: 8)),
            .intervals(.init(work: .open, recovery: .time(60), repeats: 1)),
        ]
        for main in mains {
            let ends: [(warmup: IntervalGoal?, cooldown: IntervalGoal?)] = [(nil, nil), (.time(600), nil), (nil, .distance(meters: 1_000)), (.open, .open)]
            for (warmup, cooldown) in ends {
                let draft = WorkoutDraft(name: "W", warmup: warmup, main: main, cooldown: cooldown)
                let plan = draft.save(replacing: nil, in: context)
                #expect(WorkoutDraft(plan) == draft)
                #expect(WorkoutDraft.fits(plan))
            }
        }
    }

    /// A time, distance or free main part is a single work step; a free one waits for Next, or runs to the finish
    /// as the last part.
    @Test func aSingleMainPartIsOneStep() {
        let free = WorkoutDraft(name: "", main: .free, cooldown: .time(600))
        #expect(free.timeline.map(\.goal) == [.open, .time(600)])
        #expect(free.timeline.first?.kind == .work)
        var tracker = StepTracker(timeline: WorkoutDraft(name: "", warmup: .time(600), main: .free).timeline)
        _ = tracker.update(elapsed: 600, meters: 1_500)
        #expect(tracker.runsUntilFinish)
    }

    @Test func aWorkoutFromAnOlderVersionIsReadAsCloseAsItCanBe() {
        let plan = IntervalPlan(name: "Old", isCustom: true)
        plan.addBlock().addStep(.warmup, goal: .time(600))
        let first = plan.addBlock(repeatCount: 3)
        first.addStep(.work, goal: .time(60))
        first.addStep(.recovery, goal: .time(60))
        first.addStep(.recovery, goal: .open, isWalk: true)
        plan.addBlock().addStep(.work, goal: .time(300))
        plan.addBlock().addStep(.cooldown, goal: .open)
        context.insert(plan)

        let draft = WorkoutDraft(plan)
        #expect(draft.warmup == .time(600))
        #expect(draft.main == .intervals(.init(work: .time(60), recovery: .time(60), repeats: 3)))
        #expect(draft.cooldown == .open)
        #expect(!WorkoutDraft.fits(plan))
    }

    /// A new workout is a 5 min warm-up, a 20 min run and a 5 min cooldown, and a blank name saves as the
    /// hint shows it.
    @Test func aNewWorkoutStartsSimpleAndABlankNameIsMyNewRun() {
        let draft = WorkoutDraft.starter()
        #expect(draft.warmup == .time(5 * 60))
        #expect(draft.main == .time(20 * 60))
        #expect(draft.cooldown == .time(5 * 60))
        #expect(draft.save(replacing: nil, in: context).name == "My New Run")
        #expect(WorkoutDraft(name: "   ", main: .free).trimmedName == "My New Run")
        #expect(WorkoutDraft(name: " Track night ", main: .free).trimmedName == "Track night")
    }

    /// Distances read in the workout's unit, kilometers or miles, to one decimal, and never as "0".
    @Test func aDistanceReadsInTheWorkoutsUnit() {
        #expect(WorkoutDistance.text(1_609.344, in: .miles) == "1 mi")
        #expect(WorkoutDistance.text(8_851.392, in: .miles) == "5.5 mi")
        #expect(WorkoutDistance.text(5_000, in: .miles) == "3.1 mi")
        #expect(WorkoutDistance.text(14_300, in: .kilometers) == "14.3 km")
        #expect(WorkoutDistance.text(8_851.392, in: .kilometers) == "8.9 km")
        #expect(WorkoutDistance.text(5_000, in: .kilometers) == "5 km")
        #expect(WorkoutDistance.text(400, in: .kilometers) == "0.4 km")
        #expect(WorkoutDistance.text(402, in: .kilometers) == "0.4 km")
        #expect(WorkoutDistance.text(250, in: .kilometers) == "0.3 km")
        #expect(WorkoutDistance.text(402.336, in: .miles) == "0.3 mi")
        #expect(WorkoutDistance.text(804.672, in: .miles) == "0.5 mi")
        #expect(WorkoutDistance.text(200, in: .miles) == "0.1 mi")
        // Nothing reads "0".
        #expect(WorkoutDistance.text(30, in: .miles) == "0.1 mi")
        #expect(WorkoutDistance.text(40, in: .kilometers) == "0.1 km")
        #expect(WorkoutDistance.amount(400, in: .kilometers) == "0.4")
    }

    /// Switching a workout's unit changes how it reads, never what's kept: 1 mi to km and back is still 1 mi.
    @Test func switchingTheUnitKeepsEveryDistanceExact() {
        var draft = WorkoutDraft(
            name: "Mixed",
            warmup: .distance(meters: 1_609.344),
            main: .intervals(.init(work: .distance(meters: 400), recovery: .distance(meters: 400), repeats: 4)),
            cooldown: .distance(meters: 8_851.392),
            unit: .miles
        )
        let kept = draft.storedBlocks
        // A quarter mile switched to km and back is still exactly 402.336 m, and reads 0.3 mi.
        let quarter = WorkoutDraft(name: "", main: .distance(meters: 402.336), unit: .miles)
        var switched = quarter
        switched.unit = .kilometers
        #expect(WorkoutSummary.parts(switched).map(\.value) == ["0.4 km run"])
        switched.unit = .miles
        #expect(switched == quarter)
        #expect(WorkoutSummary.parts(switched).map(\.value) == ["0.3 mi run"])
        draft.unit = .kilometers
        #expect(WorkoutSummary.parts(draft).map(\.value) == ["1.6 km", "Intervals", "8.9 km"])
        draft.unit = .miles
        #expect(draft.storedBlocks == kept)
        #expect(WorkoutSummary.parts(draft).map(\.value) == ["1 mi", "Intervals", "5.5 mi"])

        // Opening a distance's page in either unit, without typing, gives back the exact meters.
        var entry = IntervalSetEntry(.init(work: .distance(meters: 5_000), recovery: .distance(meters: 1_609.344), repeats: 2), unit: .miles)
        #expect(entry.workDistance == "3.1")
        #expect(entry.intervals(repeats: 2) == .init(work: .distance(meters: 5_000), recovery: .distance(meters: 1_609.344), repeats: 2))
        // Typed, it's the typed amount in the workout's unit.
        entry.workDistance = "3.1"
        entry.workDistance = "2"
        #expect(entry.intervals(repeats: 2)?.work == .distance(meters: 2 * 1_609.344))
    }

    /// The unit is saved with the workout, and one saved before reads in the unit its distances are round in.
    @Test func aWorkoutKeepsItsUnit() {
        let saved = WorkoutDraft(name: "Miles", main: .distance(meters: 5_000), unit: .miles).save(replacing: nil, in: context, defaults: defaults)
        #expect(saved.distanceUnit == .miles)
        #expect(WorkoutDraft(saved, preferred: .kilometers).unit == .miles)

        let older = WorkoutDraft(name: "Older", main: .distance(meters: 8_046.72)).save(replacing: nil, in: context, defaults: defaults)
        older.distanceUnit = nil
        #expect(WorkoutDraft(older, preferred: .kilometers).unit == .miles)
        let timed = WorkoutDraft(name: "Timed", main: .time(600)).save(replacing: nil, in: context, defaults: defaults)
        timed.distanceUnit = nil
        #expect(WorkoutDraft(timed, preferred: .miles).unit == .miles)
    }

    @Test func timesAndDistancesStayInRange() {
        #expect(WorkoutDraft.clamped(.time(0)) == .time(5))
        #expect(WorkoutDraft.clamped(.distance(meters: 10)) == .distance(meters: 50))
        #expect(WorkoutDraft.clamped(.open) == .open)
    }

    // MARK: Changing and deleting

    @Test func aWorkoutNoRunUsedChangesInPlace() throws {
        let plan = openEndedDraft().save(replacing: nil, in: context)
        var draft = WorkoutDraft(plan)
        draft.cooldown = nil
        draft.name = "Shorter"

        let saved = draft.save(replacing: plan, in: context)
        #expect(saved === plan)
        #expect(plan.name == "Shorter")
        #expect(plan.timeline.count == 7)
        // The old blocks went with the change.
        #expect(try context.fetch(FetchDescriptor<IntervalBlock>()).count == 2)
    }

    @Test func aWorkoutARunUsedIsKeptForThatRun() {
        let plan = openEndedDraft().save(replacing: nil, in: context)
        let run = Run(kind: .intervals)
        context.insert(run)
        run.intervalPlanValue = plan
        try? context.save()

        var draft = WorkoutDraft(plan)
        draft.main = .time(30 * 60)
        let saved = draft.save(replacing: plan, in: context, defaults: defaults)

        #expect(saved !== plan)
        #expect(run.intervalPlan === plan)
        #expect(plan.timeline.count == 8)
        #expect(!plan.isSavedWorkout)
        #expect(savedPlans().map(\.name) == ["Track night"])
        // The run isn't finished, so the original was never run and the copy keeps its date.
        #expect(saved.createdDateValue == plan.createdDateValue)
        // The original is kept for its run, and this device sweeps it once the run is gone.
        #expect(!RemovedIntervalPlans(defaults: defaults).isEmpty)
    }

    /// Changing the workout run every week keeps it at the top, rather than sinking to when it was made.
    @Test func aChangedWorkoutKeepsItsPlaceInTheList() {
        let weekly = WorkoutDraft(name: "Weekly", main: .free).save(replacing: nil, in: context)
        weekly.createdDateValue = Date(timeIntervalSince1970: 1_000)
        let newer = WorkoutDraft(name: "Newer", main: .free).save(replacing: nil, in: context)
        newer.createdDateValue = Date(timeIntervalSince1970: 2_000)
        let run = Run(kind: .intervals, startDate: Date(timeIntervalSince1970: 3_000))
        context.insert(run)
        run.intervalPlanValue = weekly
        run.finish(at: Date(timeIntervalSince1970: 3_600))
        try? context.save()

        var draft = WorkoutDraft(weekly)
        draft.cooldown = WorkoutDraft.defaultEnd
        let changed = draft.save(replacing: weekly, in: context, defaults: defaults)

        #expect(changed !== weekly)
        #expect(changed.createdDateValue == Date(timeIntervalSince1970: 3_000))
        #expect(savedPlans().savedWorkouts.map(\.name) == ["Weekly", "Newer"])
    }

    @Test func deletingKeepsTheStepsOfRunsDoneWithIt() throws {
        let used = openEndedDraft().save(replacing: nil, in: context)
        let unused = WorkoutDraft.starter().save(replacing: nil, in: context)
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
        #expect(run.intervalPlan?.timeline.count == 8)
    }

    /// A workout that reached this device already taken off the page, through iCloud, may have runs still on
    /// their way, so only the device that took it off deletes it.
    @Test func aWorkoutTakenOffElsewhereIsntDeletedHere() throws {
        let fromAnotherDevice = WorkoutDraft.starter().save(replacing: nil, in: context)
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
        let older = WorkoutDraft(name: "Older", main: .free).save(replacing: nil, in: context)
        older.createdDateValue = Date(timeIntervalSince1970: 1_000)
        let newer = WorkoutDraft(name: "Newer", main: .free).save(replacing: nil, in: context)
        newer.createdDateValue = Date(timeIntervalSince1970: 2_000)
        #expect([older, newer].savedWorkouts.map(\.name) == ["Newer", "Older"])

        let run = Run(kind: .intervals, startDate: Date(timeIntervalSince1970: 3_000))
        context.insert(run)
        run.intervalPlanValue = older
        run.finish(at: Date(timeIntervalSince1970: 3_600))
        try? context.save()
        #expect([older, newer].savedWorkouts.map(\.name) == ["Older", "Newer"])
    }

    // MARK: Clearing out the old workouts

    @Test func theOldWorkoutsGoOnceAndRunsKeepTheirSteps() throws {
        // An old interval workout a run used, an old one nobody ran, and one in a shape this version can't build.
        let usedOld = WorkoutDraft.starter().save(replacing: nil, in: context)
        usedOld.createdDateValue = WorkoutMigration.cutoff - 86_400
        let unusedOld = WorkoutDraft(name: "Old", main: .free).save(replacing: nil, in: context)
        unusedOld.createdDateValue = WorkoutMigration.cutoff - 60
        let oddShape = IntervalPlan(name: "Odd", createdDate: WorkoutMigration.cutoff + 60, isCustom: true)
        oddShape.addBlock().addStep(.work, goal: .time(60))
        oddShape.addBlock().addStep(.work, goal: .time(60))
        context.insert(oddShape)
        // One already built the new way, which reached this device through iCloud.
        let rebuilt = WorkoutDraft.starter().save(replacing: nil, in: context)
        rebuilt.createdDateValue = WorkoutMigration.cutoff + 3_600
        // A named workout of the first kind.
        context.insert(Workout(name: "City Run", type: .distance))
        let run = Run(kind: .intervals)
        context.insert(run)
        run.intervalPlanValue = usedOld
        try context.save()

        WorkoutMigration.runIfNeeded(in: context, defaults: defaults)

        #expect(savedPlans() == [rebuilt])
        #expect(try context.fetch(FetchDescriptor<Workout>()).isEmpty)
        #expect(run.intervalPlan?.timeline == WorkoutDraft.starter().timeline)
        #expect(defaults.bool(forKey: WorkoutMigration.doneKey))

        // Once only: a workout made later stays, whatever its date says.
        let later = WorkoutDraft(name: "Later", main: .free).save(replacing: nil, in: context)
        later.createdDateValue = WorkoutMigration.cutoff - 1
        WorkoutMigration.runIfNeeded(in: context, defaults: defaults)
        #expect(savedPlans().contains(later))
    }

    // MARK: Length

    private func step(_ kind: IntervalStepKind, _ goal: IntervalGoal, isWalk: Bool = false) -> PlannedIntervalStep {
        PlannedIntervalStep(kind: kind, goal: goal, repetition: 1, repeatCount: 1, isWalk: isWalk)
    }

    @Test func aTimedWorkoutShowsItsMinutes() {
        #expect(RunFormat.intervalLength(IntervalPlan.classicFiveByThree().timeline, unit: .kilometers) == "45 min")
    }

    /// Open ends are named where they fall, so 22 timed minutes don't read as the whole workout.
    @Test func openEndsAreNamedBesideTheTimedMinutes() {
        var timeline = [step(.warmup, .open)]
        for _ in 1...4 {
            timeline += [step(.work, .time(240)), step(.recovery, .time(90))]
        }
        timeline.append(step(.cooldown, .open))
        #expect(RunFormat.intervalLength(timeline, unit: .kilometers) == "Warm-up + 22 min + cooldown")
        #expect(RunFormat.intervalLength(Array(timeline.dropLast()), unit: .kilometers) == "Warm-up + 22 min")
        #expect(RunFormat.intervalLength(Array(timeline.dropFirst()), unit: .kilometers) == "22 min + cooldown")
    }

    @Test func distancesAndOtherOpenStepsAreCountedOnTheirOwn() {
        let timeline = [step(.work, .time(180)), step(.recovery, .distance(meters: 400)), step(.recovery, .open, isWalk: true), step(.cooldown, .open)]
        #expect(RunFormat.intervalLength(timeline, unit: .kilometers) == "3 min + 400 m + 1 step until Next + cooldown")
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

    @Test func aWorkoutSavedWithoutAUnitReadsInTheSameUnitOnTheWatch() {
        let plan = IntervalPlan(name: "Track")
        context.insert(plan)
        let block = plan.addBlock(repeatCount: 8)
        block.addStep(.work, goal: .distance(meters: 400), isWalk: false)
        block.addStep(.recovery, goal: .distance(meters: 200), isWalk: false)
        #expect(plan.distanceUnitValue == nil)

        // A miles runner's iPhone reads 8 × 400 m in meters, as its distances are round in them.
        let iPhone = WorkoutDraft(plan, preferred: .miles).unit
        #expect(iPhone == .kilometers)
        let sent = WatchSavedWorkout(plan, preferred: .miles)
        #expect(sent.distanceUnit == iPhone.rawValue)
        #expect(sent.summary(defaultUnit: .miles) == WorkoutDistance.length(plan.timeline, in: .kilometers))
    }

    // MARK: Intervals card

    /// Work and recovery are both a time or both a distance; a time is typed as m:ss.
    @Test func theIntervalsCardReadsTimesAsMinutesAndSeconds() {
        var entry = IntervalSetEntry(.init(work: .time(300), recovery: .time(120), repeats: 4), unit: .kilometers)
        #expect(entry.kind == .time)
        #expect(entry.workTime == "5:00")
        #expect(entry.recoveryTime == "2:00")
        #expect(entry.total(repeats: 2) == "14 min")
        entry.workTime = "1:30"
        entry.recoveryTime = "1"
        #expect(entry.intervals(repeats: 3) == .init(work: .time(90), recovery: .time(60), repeats: 3))
        entry.recoveryTime = "1:75"
        #expect(entry.intervals(repeats: 3) == nil)
        #expect(IntervalSetEntry.seconds(":45") == 45)
        #expect(IntervalSetEntry.seconds("0:00") == nil)
        #expect(IntervalSetEntry.seconds("") == nil)
    }

    @Test func theIntervalsCardKeepsDistancesInOneUnit() {
        var entry = IntervalSetEntry(.init(work: .distance(meters: 1_000), recovery: .distance(meters: 250), repeats: 2), unit: .kilometers)
        #expect(entry.kind == .distance)
        #expect(entry.workDistance == "1")
        #expect(entry.recoveryDistance == "0.3")
        // Shown rounded, kept exact.
        #expect(entry.intervals(repeats: 2)?.recovery == .distance(meters: 250))
        #expect(entry.total(repeats: 2) == "2.5 km")
        entry.recoveryDistance = "0.5"
        #expect(entry.intervals(repeats: 2) == .init(work: .distance(meters: 1_000), recovery: .distance(meters: 500), repeats: 2))
        let quarters = IntervalSetEntry(.init(work: .distance(meters: 402.336), recovery: .distance(meters: 402.336), repeats: 6), unit: .miles)
        #expect(quarters.workDistance == "0.3")
        #expect(quarters.intervals(repeats: 6)?.work == .distance(meters: 402.336))
        #expect(quarters.total(repeats: 6) == "3 mi")
    }

    /// Sets saved before they were all one kind still open: the work picks the kind.
    @Test func anOlderMixedSetOpensAsTheWorksKind() {
        let open = IntervalSetEntry(.init(work: .distance(meters: 200), recovery: .open, repeats: 8), unit: .kilometers)
        #expect(open.kind == .distance)
        #expect(open.intervals(repeats: 8) == .init(work: .distance(meters: 200), recovery: .distance(meters: 200), repeats: 8))
        let mixed = IntervalSetEntry(.init(work: .time(60), recovery: .distance(meters: 400), repeats: 4), unit: .kilometers)
        #expect(mixed.kind == .time)
        #expect(mixed.intervals(repeats: 4) == .init(work: .time(60), recovery: .time(120), repeats: 4))
    }

    // MARK: Target pace

    @Test func aTargetPaceIsSavedAndReadBack() {
        var draft = openEndedDraft()
        draft.targetPace = 300...315
        let plan = draft.save(replacing: nil, in: context, defaults: defaults)
        #expect(plan.targetPace == 300...315)
        #expect(WorkoutDraft(plan).targetPace == 300...315)
        #expect(WorkoutDraft.fits(plan))

        // Taken out on the next save.
        var changed = WorkoutDraft(plan)
        changed.targetPace = nil
        let resaved = changed.save(replacing: plan, in: context, defaults: defaults)
        #expect(resaved.targetPace == nil)
        #expect(resaved.targetPaceFastValue == nil)
    }

    @Test func aTargetPaceIsTypedPerMileOrKilometer() {
        // 8:45 /mi is about 5:26 /km.
        var miles = PaceEntry(nil, unit: .miles)
        #expect(!miles.isRange)
        #expect(miles.single == "9:30")
        miles.single = "8:45"
        let pace = miles.pace
        #expect(pace.map { abs($0.lowerBound - 525 / 1.609344) < 0.001 } == true)
        #expect(pace?.lowerBound == pace?.upperBound)
        #expect(pace.map { WorkoutDistance.paceText($0, unit: .miles) } == "8:45 min/mi")
        #expect(WorkoutDistance.paceText(300...315, unit: .kilometers) == "5:00–5:15 min/km")

        var range = PaceEntry(300...315, unit: .kilometers)
        #expect(range.isRange)
        #expect(range.faster == "5:00")
        #expect(range.slower == "5:15")
        // Typed the wrong way round, it's still fastest first.
        range.faster = "5:20"
        #expect(range.pace == 315...320)
        range.slower = ""
        #expect(range.pace == nil)
    }

    @Test func theTargetPaceIsOnlyForTheMainPart() {
        var draft = openEndedDraft()
        draft.targetPace = 300...300
        let plan = draft.save(replacing: nil, in: context, defaults: defaults)
        let targets = plan.timeline.map { RunRecorder.paceTarget(during: $0, of: plan) }
        #expect(zip(plan.timeline, targets).allSatisfy { step, target in (step.kind == .work) == (target != nil) })
        #expect(targets.compactMap { $0 }.count == 3)
        // The coach's steps never carry one.
        #expect(RunRecorder.paceTarget(during: plan.timeline[1], of: IntervalPlan.classicFiveByThree()) == nil)
    }

    @Test func theWatchGetsTheTargetPace() {
        var draft = openEndedDraft()
        draft.targetPace = 300...315
        let plan = draft.save(replacing: nil, in: context, defaults: defaults)
        let received = WatchSavedWorkout.decode(WatchSavedWorkout.encode([WatchSavedWorkout(plan)]))
        let watch = WindRunSchema.makeContainer(inMemory: true)
        #expect(received.first?.makePlan(in: watch.mainContext).targetPace == 300...315)
        // A workout from an iPhone app that doesn't send a pace still reads, without one.
        let older = #"[{"name":"Old","createdDate":0,"blocks":[]}]"#
        #expect(WatchSavedWorkout.decode(Data(older.utf8)).first?.targetPaceFast == nil)
        #expect(WatchSavedWorkout.decode(Data(older.utf8)).count == 1)
    }

    @Test func theListPutsThePaceOnTheMainPart() {
        let draft = WorkoutDraft(name: "Tempo", warmup: .open, main: .distance(meters: 5_000), cooldown: .open, targetPace: 300...315)
        #expect(WorkoutSummary.parts(draft).map(\.value) == ["Until Next", "5 km run @ 5:00–5:15 min/km", "Until Next"])
        let free = WorkoutDraft(name: "", main: .free, targetPace: 570 / 1.609344...690 / 1.609344, unit: .miles)
        #expect(WorkoutSummary.parts(free).map(\.value) == ["Free run @ 9:30–11:30 min/mi"])
    }

    /// The pace reads in the workout's unit, and opening the page in either one keeps it exact.
    @Test func aTargetPaceReadsInEitherUnitAndStaysExact() {
        let exact = PaceEntry.perKilometer(570, unit: .miles)
        let miles = PaceEntry(exact...exact, unit: .miles)
        #expect(miles.single == "9:30")
        #expect(miles.pace == exact...exact)
        var kilometers = PaceEntry(exact...exact, unit: .kilometers)
        #expect(kilometers.single == "5:54")
        #expect(kilometers.pace == exact...exact)
        #expect(PaceEntry(kilometers.pace, unit: .miles).single == "9:30")
        // Typed in kilometers, it's that pace.
        kilometers.single = "5:00"
        #expect(kilometers.pace == 300...300)
        #expect(PaceEntry(300...300, unit: .miles).single == "8:03")
        // The page's "Target:" line reads as the box does.
        #expect(WorkoutDistance.paceText(300...300, unit: .miles) == "8:03 min/mi")
    }
}
