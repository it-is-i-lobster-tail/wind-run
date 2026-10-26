//
//  RunDeletion.swift
//  Wind Run
//

import Foundation
import OSLog
import SwiftData

/// Deletes a finished run for good: from this iPhone and so from iCloud when sync is on, from the
/// coach's reading of the runner's training, and from Apple Health when the runner asks.
///
/// The runner always gets their way. The coach takes back what the run did: a session it completed
/// goes back to planned (or missed, once its day has passed), and its pace changes and notes are undone.
@MainActor
struct RunDeletion {
    let context: ModelContext
    var calendar: Calendar = .current
    /// Coach mode only runs once the terms are accepted, so the coach is left alone until then.
    var coachIsOn = TermsAcceptance.isCurrent()

    /// Deletes the run and returns what the coach made of the plan without it, or nil with no plan.
    @discardableResult
    func delete(_ run: Run, fromHealth: Bool, now: Date = .now) -> CoachUpdate? {
        let healthWorkoutID = run.healthWorkoutID
        // A coach session or interval plan it followed stays. Unlink them first: they can keep listing
        // the deleted run, and reading it through them (the coach checks whether a session is done) crashes.
        run.coachWorkoutValue = nil
        run.intervalPlanValue = nil
        // Its route, pauses and heart rate go with it.
        context.delete(run)
        context.saveQuietly()
        Logger.run.debug("Deleted run")

        if fromHealth, let healthWorkoutID {
            Task { await HealthSync.shared.deleteWorkout(healthWorkoutID) }
        }

        let coach = CoachService(context: context, calendar: calendar)
        guard coachIsOn, let plan = coach.currentPlan() else { return nil }
        return coach.refresh(plan, now: now)
    }
}
