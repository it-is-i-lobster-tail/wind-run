//
//  CoachToday.swift
//  Wind Run
//

import Foundation

/// What the coach has for today, for the Run screen's second start button.
enum CoachToday: Equatable {
    /// A run still to do today.
    case workout(CoachWorkout)
    /// Today's run is done.
    case done(next: CoachWorkout?)
    /// No run today.
    case rest(next: CoachWorkout?)
    /// The plan's first day is still to come.
    case startsLater(next: CoachWorkout?)
    /// The plan is on hold until the runner says they're ready.
    case paused

    /// Nil when the plan is over, so only the plain run is offered.
    static func of(_ plan: CoachPlan, state: CoachState, now: Date, calendar: Calendar) -> CoachToday? {
        if state.status.isPaused { return .paused }
        guard state.status.isActive else { return nil }
        if let workout = workouts(plan, state: state, now: now, calendar: calendar).first {
            return .workout(workout)
        }
        let next = nextRun(plan, state: state, now: now, calendar: calendar)
        if calendar.startOfDay(for: now) < calendar.startOfDay(for: plan.startDate) {
            return .startsLater(next: next)
        }
        let stored = plan.weeks.flatMap(\.workouts)
        let ranToday = CoachEngine.todaysSessions(state, now: now, calendar: calendar).contains { session in
            guard session.kind.isRun else { return false }
            if case .done = session.status { return true }
            return stored.contains { $0.sessionID == session.id && $0.isDone }
        }
        return ranToday ? .done(next: next) : .rest(next: next)
    }

    /// Today's runs from the coach that are still to do.
    static func workouts(_ plan: CoachPlan, state: CoachState, now: Date, calendar: Calendar) -> [CoachWorkout] {
        let workouts = plan.weeks.flatMap(\.workouts)
        return CoachEngine.todaysSessions(state, now: now, calendar: calendar)
            .filter { $0.kind.isRun && $0.status.isPlanned }
            .compactMap { session in workouts.first { $0.sessionID == session.id && !$0.isDone } }
    }

    /// The first planned run after today, when the plan has one yet. Later weeks are planned as they come.
    static func nextRun(_ plan: CoachPlan, state: CoachState, now: Date, calendar: Calendar) -> CoachWorkout? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
        let upcoming = state.weeks.map(\.plan).flatMap { week in
            week.sessions
                .filter { $0.kind.isRun && $0.status.isPlanned }
                .map { (date: state.date(of: $0, in: week, calendar: calendar), id: $0.id) }
        }
        .filter { $0.date >= tomorrow }
        .sorted { $0.date < $1.date }
        let workouts = plan.weeks.flatMap(\.workouts)
        return upcoming.lazy.compactMap { next in workouts.first { $0.sessionID == next.id && !$0.isDone } }.first
    }
}
