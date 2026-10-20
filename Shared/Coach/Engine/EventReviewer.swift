//
//  EventReviewer.swift
//  Wind Run
//

import Foundation

/// The event forecast each week, the race and what comes after (EF-1 to EF-9, EV-9, EV-10).
enum EventReviewer {
    /// The week-end step for event plans: once the race's recovery is over (EV-9), the plan is complete and the
    /// next goal is offered. Safe to run again for the same week.
    static func weekEnded(_ index: Int, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        var questions: [CoachQuestion] = []
        if state.status.isActive, let event = state.event, let end = recoveryEnd(state, calendar: calendar) {
            let nextWeek = state.weekStart(index + 1, calendar: calendar)
            if nextWeek > calendar.startOfDay(for: event.raceDate), nextWeek >= end {
                state.status = .complete(on: now)
                questions.append(.nextGoal)
            }
        }
        return CoachUpdate(state: state, questions: questions)
    }

    /// A run on race day, matched to the race (EV-9): a finish or a DNF by its distance (`recordRace`).
    static func raceLogged(_ run: LoggedRun, state: CoachState, now: Date, calendar: Calendar) -> CoachUpdate {
        recordRace(meters: run.meters, seconds: run.movingSeconds, run: run, state: state, now: now, calendar: calendar)
    }

    /// Questions about the race (EV-9): "Did you race?" from the day after race day while no run is matched to the
    /// race and nothing was answered, and "What next?" while the plan is complete or stopped by a race not
    /// started.
    static func questions(_ state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> [CoachQuestion] {
        var questions: [CoachQuestion] = []
        if let event = state.event, state.eventReview.outcome == nil, state.eventReview.raceRunID == nil,
           calendar.startOfDay(for: now) > calendar.startOfDay(for: event.raceDate) {
            questions.append(.didYouRace)
        }
        switch state.status {
        case .complete, .stopped(reason: .didNotStart, on: _):
            questions.append(.nextGoal)
        case .active, .paused, .stopped:
            break
        }
        return questions
    }
}
