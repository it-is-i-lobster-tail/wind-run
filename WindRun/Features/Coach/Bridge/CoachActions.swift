//
//  CoachActions.swift
//  Wind Run
//

import Foundation
import SwiftData

/// What the coach screens do with the runner's answers: call the engine on the current plan and
/// pass what comes back to the inbox.
@MainActor
struct CoachActions {
    let context: ModelContext
    let plan: CoachPlan
    let inbox: CoachInbox

    var service: CoachService { CoachService(context: context) }

    /// Runs an engine call and shows what it said, then catches the plan up so every question the
    /// coach is still waiting on stays listed.
    @discardableResult
    func perform(_ call: (CoachState, [LoggedRun], Date, Calendar) -> CoachUpdate) -> CoachUpdate? {
        let service = service
        guard let update = service.perform(on: plan, call) else { return nil }
        inbox.receive(update)
        if let refreshed = service.refresh(plan) {
            inbox.receive(refreshed, after: update.questions)
        }
        return update
    }

    /// Answers one of the coach's simpler questions. A route means another screen should open.
    func answer(_ answer: CoachAnswer) -> CoachRoute? {
        var route: CoachRoute?
        perform { state, runs, now, calendar in
            let (update, nextRoute) = CoachEngine.answer(answer, state: state, runs: runs, now: now, calendar: calendar)
            route = nextRoute
            return update
        }
        return route
    }

    /// Tells the coach about a saved run and returns what it made of it.
    func logRun(_ run: Run) -> RunReview? {
        let service = service
        guard let (update, review) = service.logRun(run, in: plan) else { return nil }
        inbox.receive(update)
        if let refreshed = service.refresh(plan) {
            inbox.receive(refreshed, after: update.questions)
        }
        return review
    }

    /// Stores the after-run answers and returns the coach's updated review.
    func saveCheckIn(_ checkIn: RunCheckIn, for run: Run) -> RunReview? {
        let service = service
        guard let (update, review) = service.saveCheckIn(checkIn, for: run, in: plan) else { return nil }
        inbox.receive(update)
        if let refreshed = service.refresh(plan) {
            inbox.receive(refreshed, after: update.questions)
        }
        return review
    }

    func state() -> CoachState? { service.state(of: plan) }

    /// The run with this coach id, if it's still stored.
    func run(withID id: UUID) -> Run? {
        let descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.runIDValue == id })
        return try? context.fetch(descriptor).first
    }
}
