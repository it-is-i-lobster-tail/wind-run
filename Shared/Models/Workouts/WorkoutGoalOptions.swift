//
//  WorkoutGoalOptions.swift
//  Wind Run
//

import Foundation

/// One of the built-in workouts on the Workout page: a distance run, a timed run or a free run. The runner's
/// own workouts are saved as `IntervalPlan`s and open their own page.
struct WorkoutChoice: Hashable {
    let name: String
    let type: WorkoutType
    var sport: WorkoutSport = .running

    var systemImage: String { sport == .running ? type.systemImage : sport.systemImage }

    static let distanceRun = WorkoutChoice(name: "Distance Run", type: .distance)
    static let timedRun = WorkoutChoice(name: "Timed Run", type: .time)
    static let freeRun = WorkoutChoice(name: "Free Run", type: .free)

    static let cycling = WorkoutChoice(name: "Cycling", type: .free, sport: .cycling)

    static let hike = WorkoutChoice(name: "Hike", type: .free, sport: .hiking)

    /// The built-in workouts, in the order the page lists them under the coach's.
    static let builtIn: [WorkoutChoice] = [.distanceRun, .timedRun, .freeRun, .cycling, .hike]

    /// The distance or time picked for this workout last time, in meters or seconds.
    func lastGoal(defaults: UserDefaults = .standard) -> Double? {
        let value = defaults.double(forKey: goalKey)
        return value.isFinite && value > 0 ? value : nil
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

enum DistanceGoalOptions {
    static let range = 1...100

    /// A race distance, to the meter.
    struct Race: Hashable {
        let name: String
        /// What VoiceOver says.
        let spokenName: String
        let meters: Double
    }

    /// Race distances to the meter, so a half marathon's goal buzz comes at 21.1 km, not at 21.
    static let races = [
        Race(name: "5K", spokenName: "5K", meters: 5_000),
        Race(name: "10K", spokenName: "10K", meters: 10_000),
        Race(name: "Half", spokenName: "Half marathon", meters: 21_097.5),
        Race(name: "Marathon", spokenName: "Marathon", meters: 42_195),
    ]

    /// Last time's distance in whole units of this unit, or 5 km or 3 mi the first time.
    static func startingAmount(lastMeters: Double?, unit: DistanceUnit) -> Int {
        guard let lastMeters, lastMeters.isFinite, lastMeters > 0 else { return unit == .kilometers ? 5 : 3 }
        let amount = (lastMeters / unit.meters).rounded()
        return Int(amount.clamped(to: Double(range.lowerBound)...Double(range.upperBound)))
    }

    /// Where the picker opens: last time's race distance as it was, anything else to the whole unit.
    static func startingMeters(lastMeters: Double?, unit: DistanceUnit) -> Double {
        if let lastMeters, let race = race(at: lastMeters) { return race.meters }
        return Double(startingAmount(lastMeters: lastMeters, unit: unit)) * unit.meters
    }

    /// The race at this distance, if it's one.
    static func race(at meters: Double) -> Race? {
        races.first { abs($0.meters - meters) < 1 }
    }
}

enum TimeGoalOptions {
    /// The most the hours wheel offers. The starting time is capped to what the wheels can show.
    static let maxHours = 9
    static let maxMinutes = maxHours * 60 + 59

    /// Last time's time to the minute, or 30 minutes the first time.
    static func startingSeconds(last: Double?) -> Double {
        guard let last, last.isFinite, last > 0 else { return 30 * 60 }
        let minutes = (last / 60).rounded().clamped(to: 1...Double(maxMinutes))
        return minutes * 60
    }
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

    /// "45 min", "1 h", "1 h 30 min", written as the coach writes a time.
    static func time(_ seconds: TimeInterval) -> String {
        CoachFormat.minutes(seconds)
    }
}
