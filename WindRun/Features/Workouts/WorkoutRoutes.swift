//
//  WorkoutRoutes.swift
//  Wind Run
//

import Foundation

extension WorkoutChoice {
    /// The first page after picking it: how far, how long, or straight to Start for a free run.
    var firstStep: WorkoutRoute {
        switch type {
        case .distance: .distance(self)
        case .time: .time(self)
        case .intervals, .waypoint, .free: .ready(.free(name: name, sport: sport))
        }
    }
}

/// What's ready to start, shown on the "When you're ready" page.
enum ReadyWorkout: Hashable {
    case free(name: String, sport: WorkoutSport = .running)
    case distance(name: String, meters: Double)
    case time(name: String, seconds: TimeInterval)
    /// One of the runner's own workouts.
    case saved(IntervalPlan)
    case coach(CoachWorkout)

    /// The page's title.
    var name: String {
        switch self {
        case .free(let name, _), .distance(let name, _), .time(let name, _): name
        case .saved(let plan): plan.name
        case .coach(let workout): workout.title
        }
    }

    /// The kind of run, for the trace. Never the runner's own names.
    var traceKind: String {
        switch self {
        case .free: "free"
        case .distance: "distance"
        case .time: "time"
        case .saved: "saved"
        case .coach: "coach"
        }
    }
}

/// The pages the Workout page can go to.
enum WorkoutRoute: Hashable {
    /// Pick how far.
    case distance(WorkoutChoice)
    /// Pick how long.
    case time(WorkoutChoice)
    /// "When you're ready", with Start.
    case ready(ReadyWorkout)
    /// The saved displays.
    case displays
    /// Pick what one saved display shows.
    case editDisplay(UUID)
}
