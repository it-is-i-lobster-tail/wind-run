//
//  WorkoutRoutes.swift
//  Wind Run
//

import Foundation

/// A workout picked on the Workout page: one of the built-in ones, or one the runner added.
struct WorkoutChoice: Hashable {
    let name: String
    let type: WorkoutType
    /// The runner's own workout, or nil for a built-in one.
    var workout: Workout?

    static let distanceRun = WorkoutChoice(name: "Distance Run", type: .distance)
    static let timedRun = WorkoutChoice(name: "Timed Run", type: .time)
    static let intervals = WorkoutChoice(name: "Intervals", type: .intervals)
    static let freeRun = WorkoutChoice(name: "Free Run", type: .free)

    /// The built-in workouts, in the order the page lists them under the coach's.
    static let builtIn: [WorkoutChoice] = [.distanceRun, .timedRun, .intervals, .freeRun]

    init(name: String, type: WorkoutType, workout: Workout? = nil) {
        self.name = name
        self.type = type
        self.workout = workout
    }

    init(_ workout: Workout) {
        self.init(name: workout.name, type: workout.type, workout: workout)
    }

    /// The first page after picking it: how far, how long, which intervals, or straight to Start for a free run.
    var firstStep: WorkoutRoute {
        switch type {
        case .distance: .distance(self)
        case .time: .time(self)
        case .intervals: .intervals(self)
        case .free: .ready(.free(name: name))
        }
    }

    /// The distance or time picked for this workout last time, in meters or seconds.
    func lastGoal(defaults: UserDefaults = .standard) -> Double? {
        if let workout { return workout.lastGoal }
        let key = type == .distance ? WorkoutGoalMemory.distanceKey : WorkoutGoalMemory.timeKey
        let value = defaults.double(forKey: key)
        return value > 0 ? value : nil
    }

    /// Keeps what was picked, so the next run of this workout starts from it.
    func saveGoal(_ value: Double, defaults: UserDefaults = .standard) {
        if let workout {
            workout.lastGoal = value
        } else {
            defaults.set(value, forKey: type == .distance ? WorkoutGoalMemory.distanceKey : WorkoutGoalMemory.timeKey)
        }
    }
}

/// The distance and time last picked for the built-in Distance Run and Timed Run. The runner's own workouts
/// keep theirs with the workout.
enum WorkoutGoalMemory {
    static let distanceKey = "workoutDistanceMeters"
    static let timeKey = "workoutSeconds"
}

/// What's ready to start, shown on the "When you're ready" page.
enum ReadyWorkout: Hashable {
    case free(name: String)
    case distance(name: String, meters: Double)
    case time(name: String, seconds: TimeInterval)
    case intervals(IntervalPlan)
    case coach(CoachWorkout)

    /// The page's title.
    var name: String {
        switch self {
        case .free(let name), .distance(let name, _), .time(let name, _): name
        case .intervals(let plan): plan.name
        case .coach(let workout): workout.title
        }
    }

    /// The kind of run, for the trace. Never the runner's own names.
    var traceKind: String {
        switch self {
        case .free: "free"
        case .distance: "distance"
        case .time: "time"
        case .intervals: "intervals"
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
    /// Pick one of the saved interval workouts.
    case intervals(WorkoutChoice)
    /// "When you're ready", with Start.
    case ready(ReadyWorkout)
    /// Pick what the run screen shows.
    case editDisplay
}

/// How the Workout pages write a distance or time picked on the wheels.
enum WorkoutFormat {
    /// "5 km", "13 mi", or "21.1 km" for a distance that isn't whole.
    static func distance(_ meters: Double, unit: DistanceUnit) -> String {
        let amount = meters / unit.meters
        let rounded = amount.rounded()
        if abs(amount - rounded) < 0.005 {
            return "\(Int(rounded)) \(unit.symbol)"
        }
        return "\(amount.formatted(.number.precision(.fractionLength(0...2)))) \(unit.symbol)"
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
