//
//  Workout.swift
//  Wind Run
//

import Foundation
import SwiftData

/// What a workout's main part is: a time, a distance, intervals, or a free run. The built-in rows on the
/// Workout page are one each too. Later each type can bring its own display screen.
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

    func name(for sport: WorkoutSport) -> String {
        guard sport == .cycling else { return name }
        return switch self {
        case .distance: "Distance ride"
        case .time: "Timed ride"
        case .intervals: "Intervals"
        case .free: "Open ride"
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

/// A named workout of the first kind the Workout page had: just a name on one of the types. No longer made or
/// shown: the runner's workouts are now a warm-up, a main part and a cooldown, saved as an `IntervalPlan`
/// (see `WorkoutDraft`), and `WorkoutMigration` deletes these. The model stays so stores that hold it still
/// open, and so iCloud's schema doesn't change.
@Model
final class Workout {
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
