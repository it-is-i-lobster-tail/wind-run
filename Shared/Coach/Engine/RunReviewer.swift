//
//  RunReviewer.swift
//  Wind Run
//

import Foundation

/// What the coach makes of each saved run: the match to the plan, the data gate, extra runs and spikes,
/// insights and milestones, and the questions after it (AD-1, AD-2, AD-8, FB-1 to FB-4).
enum RunReviewer {
    /// A run's duration may differ from the planned run's by this much and still match it (AD-8).
    static let matchTolerance = 0.25

    /// Reviews a saved run. Calling it again for the same run (after its check-in) updates the review.
    static func review(_ run: LoggedRun, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> (CoachState, RunReview) {
        var state = state
        let match = self.match(run, state: state, calendar: calendar)
        if case .planned(let sessionID) = match {
            state = markDone(sessionID: sessionID, runID: run.id, state: state)
        }
        if !state.runReview.reviewedRunIDs.contains(run.id) {
            state.runReview.reviewedRunIDs.append(run.id)
        }
        var questions: [CoachQuestion] = []
        if run.checkIn?.answeredAt == nil { questions.append(.runCheckIn(runID: run.id)) }
        return (state, RunReview(runID: run.id, match: match, questions: questions))
    }

    // MARK: Matching (AD-8)

    /// The planned session a run completes, or extra. A run started from a planned session matches it.
    /// Otherwise: the same day or one day either side, with a duration within ±25%; the nearer date wins,
    /// then the closer duration. A planned run can be matched once.
    static func match(_ run: LoggedRun, state: CoachState, calendar: Calendar) -> RunMatch {
        // Already matched.
        for record in state.weeks {
            if let session = record.plan.sessions.first(where: { $0.status == .done(runID: run.id) }) {
                return .planned(sessionID: session.id)
            }
        }
        if let id = run.plannedSessionID,
           let session = state.weeks.lazy.flatMap(\.plan.sessions).first(where: { $0.id == id }),
           session.status.isPlanned || session.status == .missed {
            return .planned(sessionID: id)
        }
        let runDay = calendar.startOfDay(for: run.start)
        var best: (id: UUID, days: Int, difference: Double)?
        for record in state.weeks {
            for session in record.plan.sessions where session.kind.isRun && (session.status.isPlanned || session.status == .missed) {
                let day = state.date(of: session, in: record.plan, calendar: calendar)
                let days = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: runDay).day ?? 99)
                guard days <= 1 else { continue }
                guard let difference = relativeDifference(run, session) else { continue }
                guard difference <= matchTolerance + 1e-9 else { continue }
                if best == nil || days < best!.days || (days == best!.days && difference < best!.difference) {
                    best = (session.id, days, difference)
                }
            }
        }
        return best.map { .planned(sessionID: $0.id) } ?? .extra
    }

    /// |run − planned| ÷ planned, by duration when the session has one, else by distance.
    static func relativeDifference(_ run: LoggedRun, _ session: PlannedSession) -> Double? {
        if session.target.seconds > 0 {
            return abs(run.movingSeconds - session.target.seconds) / session.target.seconds
        }
        if session.target.meters > 0, run.meters > 0 {
            return abs(run.meters - session.target.meters) / session.target.meters
        }
        return nil
    }

    static func markDone(sessionID: UUID, runID: UUID, state: CoachState) -> CoachState {
        var state = state
        for weekIndex in state.weeks.indices {
            for sessionIndex in state.weeks[weekIndex].plan.sessions.indices where state.weeks[weekIndex].plan.sessions[sessionIndex].id == sessionID {
                state.weeks[weekIndex].plan.sessions[sessionIndex].status = .done(runID: runID)
            }
        }
        return state
    }

    /// Done sessions whose run was deleted go back to planned (or missed, once their day has passed).
    static func syncMatches(_ state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachState {
        var state = state
        let ids = Set(runs.map(\.id))
        let today = calendar.startOfDay(for: now)
        for weekIndex in state.weeks.indices {
            let week = state.weeks[weekIndex].plan
            for sessionIndex in week.sessions.indices {
                let session = week.sessions[sessionIndex]
                if case .done(let runID) = session.status, !ids.contains(runID) {
                    let day = state.date(of: session, in: week, calendar: calendar)
                    state.weeks[weekIndex].plan.sessions[sessionIndex].status = day < today ? .missed : .planned
                }
            }
        }
        state.runReview.reviewedRunIDs.removeAll { !ids.contains($0) }
        return state
    }
}
