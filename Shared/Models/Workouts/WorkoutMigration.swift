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
    static let doneKey = "workoutsRebuiltAsThreeParts"
    /// Before any build could make a workout in the new shape.
    static let cutoff = Date(timeIntervalSince1970: 1_794_960_000) // 2026-11-18 00:00 UTC

    static func runIfNeeded(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        do {
            try run(in: context, defaults: defaults)
            defaults.set(true, forKey: doneKey)
        } catch {
            // Tried again next launch.
            Trace.error("Workout migration", error)
        }
    }

    static func run(in context: ModelContext, defaults: UserDefaults = .standard) throws {
        let plans = try context.fetch(FetchDescriptor<IntervalPlan>()).filter(\.isSavedWorkout)
        let old = plans.filter { $0.createdDateValue < cutoff || !WorkoutDraft.fits($0) }
        for plan in old {
            plan.remove(defaults: defaults)
        }
        let named = try context.fetch(FetchDescriptor<Workout>())
        for workout in named {
            context.delete(workout)
        }
        if !old.isEmpty || !named.isEmpty {
            try context.save()
        }
        Trace.log(.data, "Old workouts cleared", ["intervals": old.count, "kept": plans.count - old.count, "named": named.count])
    }
}
