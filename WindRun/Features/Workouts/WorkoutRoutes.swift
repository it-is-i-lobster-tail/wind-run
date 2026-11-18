//
//  WorkoutRoutes.swift
//  Wind Run
//

import Foundation

/// One of the built-in workouts on the Workout page: a distance run, a timed run or a free run. The runner's
/// own workouts are saved as `IntervalPlan`s and open their own page.
struct WorkoutChoice: Hashable {
    let name: String
    let type: WorkoutType

    static let distanceRun = WorkoutChoice(name: "Distance Run", type: .distance)
    static let timedRun = WorkoutChoice(name: "Timed Run", type: .time)
    static let freeRun = WorkoutChoice(name: "Free Run", type: .free)

    /// The built-in workouts, in the order the page lists them under the coach's.
    static let builtIn: [WorkoutChoice] = [.distanceRun, .timedRun, .freeRun]

    /// The first page after picking it: how far, how long, or straight to Start for a free run.
    var firstStep: WorkoutRoute {
        switch type {
        case .distance: .distance(self)
        case .time: .time(self)
        case .intervals, .free: .ready(.free(name: name))
        }
    }

    /// The distance or time picked for this workout last time, in meters or seconds.
    func lastGoal(defaults: UserDefaults = .standard) -> Double? {
        let value = defaults.double(forKey: goalKey)
        return value > 0 ? value : nil
    }

    /// Keeps what was picked, so the next run of this workout starts from it.
    func saveGoal(_ value: Double, defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: goalKey)
    }

    /// Only the distance and timed runs remember a goal; others would share the time key.
    private var goalKey: String {
        type == .distance ? WorkoutGoalMemory.distanceKey : WorkoutGoalMemory.timeKey
    }
}

/// The distance and time last picked for the built-in Distance Run and Timed Run.
enum WorkoutGoalMemory {
    static let distanceKey = "workoutDistanceMeters"
    static let timeKey = "workoutSeconds"
}

/// What's ready to start, shown on the "When you're ready" page.
enum ReadyWorkout: Hashable {
    case free(name: String)
    case distance(name: String, meters: Double)
    case time(name: String, seconds: TimeInterval)
    /// One of the runner's own workouts.
    case saved(IntervalPlan)
    case coach(CoachWorkout)

    /// The page's title.
    var name: String {
        switch self {
        case .free(let name), .distance(let name, _), .time(let name, _): name
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

/// How the Workout pages write a distance or time picked on the wheels.
enum WorkoutFormat {
    /// "5 km", "13 mi", or "21.1 km" and "26.2 mi" for a distance that isn't whole, to a tenth as runners
    /// name race distances.
    static func distance(_ meters: Double, unit: DistanceUnit) -> String {
        let amount = meters / unit.meters
        let rounded = amount.rounded()
        if abs(amount - rounded) < 0.05 {
            return "\(Int(rounded)) \(unit.symbol)"
        }
        return "\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(unit.symbol)"
    }

    /// "45 min", "1 h", "1 h 30 min".
    static func time(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(rest) min"
        }
    }
}
