//
//  DisplayLibraryTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// Saved displays: moving over from the one display there was, the default, adding, deleting, and which
/// display each kind of run and each workout shows.
@MainActor
struct DisplayLibraryTests {
    private func defaults() -> UserDefaults {
        let name = "DisplayLibraryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private let hills = DisplayScreen(name: "Hills", primary: .elapsed, secondary: .distance, tiles: [.grade, .gradeAdjustedPace, .elevation, .heartRate])

    // MARK: Moving over

    @Test func withNothingSavedTheOnlyDisplayIsEverydayShowingStandard() {
        let library = DisplayLibrary.current(in: defaults())

        #expect(library.screens.count == 1)
        #expect(library.defaultScreen.name == DisplayLibrary.firstName)
        #expect(library.defaultScreen.metrics == DisplayScreen.standard.metrics)
        // The same id on every device, so two devices moving over at once agree.
        #expect(library.defaultID == DisplayScreen.standard.id)
    }

    @Test func theOldDisplayBecomesTheDefaultAndReadingWritesNothing() {
        let defaults = defaults()
        var old = DisplayScreen.standard
        old.place(.grade, in: .tile(3))
        old.save(in: defaults)

        let library = DisplayLibrary.current(in: defaults)

        #expect(library.defaultScreen.metrics == old.metrics)
        #expect(library.defaultScreen.name == "Everyday")
        #expect(defaults.string(forKey: DisplayLibrary.screensKey) == nil)
    }

    @Test func savingKeepsTheListAndWritesTheDefaultWhereOlderVersionsLook() {
        let defaults = defaults()
        var library = DisplayLibrary.current(in: defaults)
        let added = library.add()!
        library.makeDefault(added.id)
        library.save(in: defaults)

        let read = DisplayLibrary.current(in: defaults)
        #expect(read == library)
        #expect(read.defaultID == added.id)
        #expect(DisplayScreen.legacy(in: defaults) == added)
    }

    @Test func listTextThatDoesntDecodeFallsBackToTheOldDisplay() {
        let defaults = defaults()
        defaults.set("not json", forKey: DisplayLibrary.screensKey)

        let library = DisplayLibrary.current(in: defaults)
        #expect(library.screens.count == 1)
        #expect(library.defaultScreen.metrics == DisplayScreen.standard.metrics)
    }

    @Test func aListThatDoesntDecodeFollowsTheOldDisplayWhenItChanges() {
        let defaults = defaults()
        defaults.set("[]", forKey: DisplayLibrary.screensKey)
        hills.save(in: defaults)
        #expect(DisplayLibrary.current(in: defaults).defaultScreen.metrics == hills.metrics)

        // An older version writes the old key through settings sync while the list stays as it was.
        var changed = hills
        changed.place(.heartRate, in: .tile(0))
        changed.save(in: defaults)
        #expect(DisplayLibrary.current(in: defaults).defaultScreen.metrics == changed.metrics)
    }

    @Test func twoStoresWithTheSameBrokenListDontShareALibrary() {
        let first = defaults()
        let second = defaults()
        for store in [first, second] {
            store.set("not json", forKey: DisplayLibrary.screensKey)
        }
        hills.save(in: first)

        #expect(DisplayLibrary.current(in: first).defaultScreen.metrics == hills.metrics)
        #expect(DisplayLibrary.current(in: second).defaultScreen.metrics == DisplayScreen.standard.metrics)
    }

    @Test func aMissingDefaultFallsToTheFirstDisplay() {
        let library = DisplayLibrary(screens: [hills, .standard], defaultID: UUID())
        #expect(library.defaultID == hills.id)
    }

    // MARK: Changing

    @Test func aNewDisplayCopiesTheDefaultUnderANameNoOtherHas() {
        var library = DisplayLibrary(screens: [hills])
        let first = library.add()!
        let second = library.add()!
        let copy = library.add(copying: hills)!

        #expect(first.name == "New Display")
        #expect(second.name == "New Display 2")
        #expect(copy.name == "Hills Copy")
        #expect(first.metrics == hills.metrics)
        #expect(Set([first.id, second.id, copy.id, hills.id]).count == 4)
    }

    @Test func theListStopsAtItsLimit() {
        var library = DisplayLibrary(screens: [hills])
        for _ in 1..<DisplayLibrary.limit { #expect(library.add() != nil) }
        #expect(library.isFull)
        #expect(library.add() == nil)
        #expect(library.screens.count == DisplayLibrary.limit)
    }

    @Test func theDefaultCantBeDeletedButOthersCan() {
        var library = DisplayLibrary(screens: [hills])
        let other = library.add()!

        library.delete(hills.id)
        #expect(library.screens.count == 2)

        library.delete(other.id)
        #expect(library.screens == [hills])
    }

    @Test func aBlankNameKeepsTheOldOneAndLongNamesAreCut() {
        var library = DisplayLibrary(screens: [hills])
        var renamed = hills
        renamed.name = "   "
        library.update(renamed)
        #expect(library.screens[0].name == "Hills")

        renamed.name = String(repeating: "a", count: 50)
        library.update(renamed)
        #expect(library.screens[0].name.count == DisplayLibrary.nameLimit)
    }

    @Test func aDeletedOrMissingDisplayShowsTheDefault() {
        let library = DisplayLibrary(screens: [hills])
        #expect(library.screen(id: nil) == hills)
        #expect(library.screen(id: UUID()) == hills)
        #expect(library.screen(id: hills.id) == hills)
    }

    // MARK: Which display a run shows

    @Test func eachKindOfRunShowsItsOwnPick() {
        let defaults = defaults()
        let intervals = UUID()
        DisplayRunKind.coach.setPick(intervals, in: defaults)
        DisplayRunKind.timed.setPick(hills.id, in: defaults)

        #expect(RunRecorder.pickedDisplayScreenID(coached: true, intervalPlan: nil, goal: nil, defaults: defaults) == intervals)
        #expect(RunRecorder.pickedDisplayScreenID(coached: false, intervalPlan: nil, goal: .time(seconds: 600), defaults: defaults) == hills.id)
        #expect(RunRecorder.pickedDisplayScreenID(coached: false, intervalPlan: nil, goal: .distance(meters: 5_000), defaults: defaults) == nil)
        #expect(RunRecorder.pickedDisplayScreenID(coached: false, intervalPlan: nil, goal: nil, defaults: defaults) == nil)

        DisplayRunKind.timed.setPick(nil, in: defaults)
        #expect(defaults.string(forKey: DisplayRunKind.timed.storageKey) == nil)
    }

    @Test func aSavedWorkoutShowsItsOwnPickAndItGoesToTheWatch() {
        let container = WindRunSchema.makeContainer(inMemory: true)
        let draft = WorkoutDraft(name: "Hill repeats", main: .time(20 * 60), displayScreenID: hills.id)
        let plan = draft.save(replacing: nil, in: container.mainContext)

        #expect(plan.displayScreenID == hills.id)
        #expect(WorkoutDraft(plan).displayScreenID == hills.id)
        #expect(RunRecorder.pickedDisplayScreenID(coached: false, intervalPlan: plan, goal: nil, defaults: defaults()) == hills.id)

        let sent = WatchSavedWorkout(plan)
        let received = WatchSavedWorkout.decode(WatchSavedWorkout.encode([sent]))
        let watch = WindRunSchema.makeContainer(inMemory: true)
        #expect(received[0].makePlan(in: watch.mainContext).displayScreenID == hills.id)
    }

    @Test func aWatchWorkoutFromAnOlderIPhoneShowsTheDefault() throws {
        let json = #"[{"name":"Old","createdDate":0,"blocks":[]}]"#
        let received = WatchSavedWorkout.decode(Data(json.utf8))
        #expect(received.first?.displayScreenID == nil)
    }

    @Test func deletingADisplaySendsEveryRunThatPickedItBackToTheDefault() {
        let defaults = defaults()
        let container = WindRunSchema.makeContainer(inMemory: true)
        let context = container.mainContext
        DisplayLibrary(screens: [.standard, hills]).save(in: defaults)
        DisplayRunKind.free.setPick(hills.id, in: defaults)
        let plan = WorkoutDraft(name: "Hill repeats", main: .time(20 * 60), displayScreenID: hills.id).save(replacing: nil, in: context)

        DisplayActions.delete(hills.id, in: context, defaults: defaults)

        #expect(!DisplayLibrary.current(in: defaults).contains(hills.id))
        #expect(DisplayRunKind.free.pick(in: defaults) == nil)
        #expect(plan.displayScreenID == nil)
    }
}
