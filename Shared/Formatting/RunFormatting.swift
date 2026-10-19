//
//  RunFormatting.swift
//  Wind Run
//

import Foundation

/// The runner's preferred distance unit.
enum DistanceUnit: String, CaseIterable, Identifiable {
    case kilometers
    case miles

    static let storageKey = "distanceUnit"

    var id: Self { self }

    var name: String {
        switch self {
        case .kilometers: "Kilometers"
        case .miles: "Miles"
        }
    }

    var symbol: String {
        switch self {
        case .kilometers: "km"
        case .miles: "mi"
        }
    }

    var meters: Double {
        switch self {
        case .kilometers: 1_000
        case .miles: 1_609.344
        }
    }
}

enum RunFormat {
    /// "5.02 km". Distance is shown without the unit when `withUnit` is false, for big readouts.
    static func distance(_ meters: Double, unit: DistanceUnit, withUnit: Bool = true) -> String {
        let value = (meters / unit.meters).formatted(.number.precision(.fractionLength(2)))
        return withUnit ? "\(value) \(unit.symbol)" : value
    }

    /// "32:10" under an hour, "1:02:03" past it.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// "5:12 /km" from seconds per kilometer, or a dash when there's no pace yet.
    static func pace(_ secondsPerKilometer: TimeInterval?, unit: DistanceUnit, withUnit: Bool = true) -> String {
        guard let secondsPerKilometer, secondsPerKilometer.isFinite, secondsPerKilometer > 0 else {
            return withUnit ? "–:–– /\(unit.symbol)" : "–:––"
        }
        let perUnit = secondsPerKilometer * unit.meters / 1_000
        // Slower than an hour per unit is a walk or a stop, not a pace worth showing.
        guard perUnit < 3600 else { return withUnit ? "–:–– /\(unit.symbol)" : "–:––" }
        let value = duration(perUnit)
        return withUnit ? "\(value) /\(unit.symbol)" : value
    }

    /// "142 bpm", or a dash when there's no reading yet.
    static func heartRate(_ beatsPerMinute: Double?, withUnit: Bool = true) -> String {
        guard let beatsPerMinute, beatsPerMinute.isFinite, beatsPerMinute > 0 else {
            return withUnit ? "–– bpm" : "––"
        }
        let value = Int(beatsPerMinute.rounded())
        return withUnit ? "\(value) bpm" : "\(value)"
    }

    /// "3 min" or "400 m" or "Open" for an interval step.
    static func goal(_ goal: IntervalGoal, unit: DistanceUnit) -> String {
        switch goal {
        case .time(let seconds):
            let minutes = seconds / 60
            if seconds.truncatingRemainder(dividingBy: 60) == 0 {
                return "\(Int(minutes)) min"
            }
            return duration(seconds)
        case .distance(let meters):
            if meters < 1_000 {
                return "\(Int(meters)) m"
            }
            return distance(meters, unit: unit)
        case .open:
            return "Open"
        }
    }
}
