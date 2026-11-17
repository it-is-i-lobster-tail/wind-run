//
//  Workout.swift
//  Wind Run
//

import Foundation
import SwiftData

/// What a workout asks for before the runner starts. Every workout on the Workout page, built in or made by
/// the runner, is one of these. Later each type can bring its own display screen.
enum WorkoutType: String, Codable, CaseIterable, Identifiable {
    /// How far to run, picked before the start.
    case distance
    /// How long to run, picked before the start.
    case time
    /// One of the saved interval workouts.
    case intervals
    /// Just a run.
    case free

    var id: Self { self }

    /// Named as the built-in rows are, in the case a line under a title takes.
    var name: String {
        switch self {
        case .distance: "Distance run"
        case .time: "Timed run"
        case .intervals: "Intervals"
        case .free: "Free run"
        }
    }

    var systemImage: String {
        switch self {
        case .distance: "point.bottomleft.forward.to.point.topright.scurvepath"
        case .time: "timer"
        case .intervals: "repeat"
        case .free: "figure.run"
        }
    }
}

/// A workout the runner added to the Workout page, such as "City Run" or "Trail Blaster". It's a name on
/// one of the workout types, and starts the same way the built-in workout of that type does.
@Model
final class Workout {
    static let nameLimit = 40

    var nameValue: String = ""
    /// The type's raw value. Text, so a type added later doesn't stop older versions loading the workout.
    var typeValue: String = WorkoutType.free.rawValue
    var createdDateValue: Date = Date.now
    /// For a distance workout the meters picked last time, for a time workout the seconds, so the next run
    /// starts from them. Nil until it's been picked.
    var lastGoalValue: Double?

    init(name: String, type: WorkoutType, createdDate: Date = .now) {
        self.nameValue = name
        self.typeValue = type.rawValue
        self.createdDateValue = createdDate
    }
}

extension Workout {
    var name: String {
        get { nameValue }
        set { nameValue = String(newValue.prefix(Self.nameLimit)) }
    }

    /// A type this version doesn't know is treated as a free run.
    var type: WorkoutType {
        get { WorkoutType(rawValue: typeValue) ?? .free }
        set {
            guard newValue.rawValue != typeValue else { return }
            typeValue = newValue.rawValue
            // A distance doesn't carry over to a time, or the other way round.
            lastGoalValue = nil
        }
    }

    var lastGoal: Double? {
        get { lastGoalValue }
        set { lastGoalValue = newValue }
    }
}

/// What a distance or timed run is aiming for. The run screen shows it ("OF 5.00 KM") and the run buzzes
/// once when it's reached, then carries on until the runner finishes.
enum RunGoal: Hashable {
    case distance(meters: Double)
    case time(seconds: TimeInterval)

    /// Whether a run at `elapsed` seconds and `meters` has got there.
    func isReached(elapsed: TimeInterval, meters: Double) -> Bool {
        switch self {
        case .distance(let goal): meters >= goal
        case .time(let goal): elapsed >= goal
        }
    }

    var meters: Double? {
        if case .distance(let meters) = self { meters } else { nil }
    }

    var seconds: TimeInterval? {
        if case .time(let seconds) = self { seconds } else { nil }
    }
}
