//
//  WorkoutMigration.swift
//  Wind Run
//

import Foundation
import SwiftData

/// Clears out the workouts made before workouts became a warm-up, a main part and a cooldown. Runs once on
/// each device.
///
/// The old interval workouts are taken off the list the way deleting one does (`IntervalPlan.remove`), so
/// runs done with them keep their steps and the unused ones are deleted a day later. The named workouts of
/// the short-lived name-and-type kind (`Workout`) are deleted outright: no run points at them.
///
/// Only workouts made before `cutoff`, or ones that don't have the new shape, go. A device that updates
/// later must not take away workouts already built in the new way on another device, which reach it
/// through iCloud.
enum WorkoutMigration {
    private static let hikeUpgradeDateKey = "hikeWorkoutUpgradeDate"
    static let doneKey = "workoutsRebuiltAsThreeParts"
    /// Before any build could make a workout in the new shape.
    static let cutoff = Date(timeIntervalSince1970: 1_794_960_000) // 2026-11-18 00:00 UTC

    static func runIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        do {
            try migrateHikes(in: context, defaults: defaults)
            guard !defaults.bool(forKey: doneKey) else { return }
            try run(in: context, defaults: defaults)
            defaults.set(true, forKey: doneKey)
        } catch {
            // Tried again next launch.
            Trace.error("Workout migration", error)
        }
    }

    static func hikeUpgradeDate(in defaults: UserDefaults = .standard) -> Date {
        // Only pre-upgrade names imply the sport. A new workout can explicitly select any sport.
        let upgradeDate = defaults.object(forKey: hikeUpgradeDateKey) as? Date ?? Date.now
        if defaults.object(forKey: hikeUpgradeDateKey) == nil {
            defaults.set(upgradeDate, forKey: hikeUpgradeDateKey)
        }
        return upgradeDate
    }

    /// Reconcile matching plans in place, including archived versions retained by history.
    /// Repeating this also catches plans downloaded from iCloud after the first upgrade.
    static func migrateHikes(in context: ModelContext, defaults: UserDefaults) throws {
        let upgradeDate = hikeUpgradeDate(in: defaults)
        let plans = try context.fetch(FetchDescriptor<IntervalPlan>(
            predicate: #Predicate { $0.isCustomValue != nil && $0.createdDateValue <= upgradeDate }
        ))
        var changed = false
        for plan in plans where WorkoutSport.isHikeName(plan.name) {
            if plan.sport != .hiking {
                plan.workoutTypeValue = WorkoutSport.hiking.rawValue
                changed = true
            }
            for run in plan.runs where run.kind != .coached && run.sport != .hiking {
                run.workoutTypeValue = WorkoutSport.hiking.rawValue
                changed = true
            }
        }
        if changed { try context.save() }
    }

    static func run(in context: ModelContext, defaults: UserDefaults = .standard) throws {
        let plans = try context.fetch(FetchDescriptor<IntervalPlan>()).filter(\.isSavedWorkout)
        let old = plans.filter { !WorkoutSport.isHikeName($0.name) && ($0.createdDateValue < cutoff || !WorkoutDraft.fits($0)) }
        for plan in old {
            plan.remove(defaults: defaults)
        }
        let named = try context.fetch(FetchDescriptor<Workout>())
        for workout in named {
            if WorkoutSport.isHikeName(workout.nameValue) {
                let goal: IntervalGoal
                switch (WorkoutType(rawValue: workout.typeValue), workout.lastGoalValue) {
                case (.distance, let meters?) where meters > 0: goal = .distance(meters: meters)
                case (.time, let seconds?) where seconds > 0: goal = .time(seconds)
                default: goal = .open
                }
                let plan = IntervalPlan(name: workout.nameValue, createdDate: workout.createdDateValue, isCustom: true)
                context.insert(plan)
                plan.workoutTypeValue = WorkoutSport.hiking.rawValue
                plan.addBlock().addStep(.work, goal: goal)
            }
            context.delete(workout)
        }
        if !old.isEmpty || !named.isEmpty {
            try context.save()
        }
        Trace.log(.data, "Old workouts cleared", ["intervals": old.count, "kept": plans.count - old.count, "named": named.count])
    }
}
