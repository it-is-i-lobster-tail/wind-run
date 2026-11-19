//
//  IntervalPlanStorageTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// How a workout's steps and settings read from what's stored, which can come from iCloud or an older
/// version, and the note of workouts this device took off the page.
@MainActor
struct IntervalPlanStorageTests {
    private let container = WindRunSchema.makeContainer(inMemory: true)
    private var context: ModelContext { container.mainContext }

    @Test func anOpenGoalStoresNoAmount() {
        let step = IntervalStep(kind: .work, goal: .distance(meters: 400))
        context.insert(step)
        #expect(step.goalAmountValue == 400)
        step.goal = .open
        #expect(step.goal == .open)
        #expect(step.goalAmountValue == 0)
        step.goal = .time(90)
        #expect(step.goal == .time(90))
        #expect(step.goalAmountValue == 90)
    }

    @Test func aTargetPaceReadsFastestFirstAndNeedsBothEnds() {
        let plan = IntervalPlan(name: "Tempo", isCustom: true)
        context.insert(plan)
        #expect(plan.targetPace == nil)
        plan.targetPaceFastValue = 320
        plan.targetPaceSlowValue = 300
        #expect(plan.targetPace == 300...320)
        plan.targetPaceFastValue = 0
        #expect(plan.targetPace == nil)
        plan.targetPaceFastValue = -5
        #expect(plan.targetPace == nil)
        plan.targetPaceFastValue = nil
        #expect(plan.targetPace == nil)
        plan.targetPace = 280...290
        #expect(plan.targetPaceFastValue == 280)
        #expect(plan.targetPaceSlowValue == 290)
        plan.targetPace = nil
        #expect(plan.targetPaceFastValue == nil)
        #expect(plan.targetPaceSlowValue == nil)
    }

    @Test func unreadableStoredSettingsReadAsNone() {
        let plan = IntervalPlan(name: "Old", isCustom: true)
        context.insert(plan)
        plan.distanceUnitValue = "furlongs"
        #expect(plan.distanceUnit == nil)
        plan.distanceUnit = .miles
        #expect(plan.distanceUnitValue == "miles")
        #expect(plan.distanceUnit == .miles)
        plan.displayScreenIDValue = "x"
        #expect(plan.displayScreenID == nil)
        let id = UUID()
        plan.displayScreenID = id
        #expect(plan.displayScreenIDValue == id.uuidString)
        #expect(plan.displayScreenID == id)
    }

    @Test func aWorkoutTakenOffKeepsWhenItWasFirstTakenOff() throws {
        let suiteName = "IntervalPlanStorageTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let plan = IntervalPlan(name: "Hills", isCustom: true)
        context.insert(plan)
        try context.save()
        let first = Date(timeIntervalSinceReferenceDate: 0)
        let later = first.addingTimeInterval(3_600)

        var removed = RemovedIntervalPlans(defaults: defaults)
        #expect(removed.isEmpty)
        removed.add(plan.persistentModelID, at: first)
        removed.add(plan.persistentModelID, at: later)
        #expect(removed.date(of: plan.persistentModelID) == first)
        #expect(removed.keys.count == 1)
        // Read back from the defaults by a new note.
        #expect(RemovedIntervalPlans(defaults: defaults).date(of: plan.persistentModelID) == first)

        removed.keep([])
        #expect(removed.isEmpty)
        #expect(defaults.object(forKey: RemovedIntervalPlans.storageKey) == nil)
    }

    private struct Flag: StatusProviding {
        let isActive: Bool
        let number: Int
    }

    @Test func theFirstActiveItemIsTheActiveOne() {
        let flags = [Flag(isActive: false, number: 0), Flag(isActive: true, number: 1), Flag(isActive: true, number: 2)]
        #expect(flags.active?.number == 1)
        #expect([Flag(isActive: false, number: 0)].active == nil)
        #expect([Flag]().active == nil)
    }
}
