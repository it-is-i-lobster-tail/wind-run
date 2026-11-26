//
//  RunDeletion.swift
//  Wind Run
//

import Foundation
import SwiftData

/// Deletes a finished run for good: from this iPhone and so from iCloud when sync is on, from the
/// coach's reading of the runner's training, and from Apple Health when the runner asks.
///
/// The runner always gets their way. The coach takes back what the run did: a run it counted goes back
/// to planned (or missed, once its day has passed), and what's left of the week is shared out again.
@MainActor
struct RunDeletion {
    let context: ModelContext
    var calendar: Calendar = .current
    /// Coach mode only runs once the terms are accepted, so the coach is left alone until then.
    var coachIsOn = TermsAcceptance.isCurrent()

    /// Deletes the run and returns what the coach made of the plan without it, or nil with no plan.
    @discardableResult
    func delete(_ run: Run, fromHealth: Bool, now: Date = .now) -> BuildPlanState? {
        let healthWorkoutID = run.healthWorkoutID
        // What was deleted and what it touches, with no dates or ids.
        Trace.log(.run, "Deleted", [
            "kind": run.kind.rawValue,
            "fromHealth": fromHealth && healthWorkoutID != nil,
            "hadHealthWorkout": healthWorkoutID != nil,
            "coachSession": run.coachWorkoutValue != nil,
            "coachOn": coachIsOn,
        ])
        // A coach session or interval plan it followed stays. Unlink them first: they can keep listing
        // the deleted run, and reading it through them (the coach checks whether a session is done) crashes.
        run.coachWorkoutValue = nil
        run.intervalPlanValue = nil
        // Its route, pauses and heart rate go with it.
        let runID = run.runID
        context.delete(run)
        context.saveQuietly()
        // Search keeps the start's town for each workout, so it goes too.
        WorkoutSearchIndex.shared.forget(runID)

        if fromHealth, let healthWorkoutID {
            Task { await HealthSync.shared.deleteWorkout(healthWorkoutID) }
        }

        let coach = BuildService(context: context, calendar: calendar)
        guard coachIsOn, let plan = coach.currentPlan() else { return nil }
        let state = coach.refresh(plan, now: now)
        Trace.log(.coach, "Re-planned after a run was deleted", ["planned": state != nil])
        return state
    }
}
