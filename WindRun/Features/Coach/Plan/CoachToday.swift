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
}
