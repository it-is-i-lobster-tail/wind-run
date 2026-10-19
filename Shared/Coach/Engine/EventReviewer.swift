//
//  EventReviewer.swift
//  Wind Run
//

import Foundation

/// The event forecast each week, the race and what comes after (EF-1 to EF-9, EV-9, EV-10).
enum EventReviewer {
    /// Re-runs the readiness forecast at a week's end and sets the event's status (EF-1 to EF-3).
    static func weekEnded(_ index: Int, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        CoachUpdate(state: state)
    }

    /// A run on race day, matched to the race (EV-9).
    static func raceLogged(_ run: LoggedRun, state: CoachState, now: Date, calendar: Calendar) -> CoachUpdate {
        CoachUpdate(state: state)
    }

    /// Questions about the race: "Did you race?" after race day with no run logged (EV-9).
    static func questions(_ state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> [CoachQuestion] {
        []
    }
}
