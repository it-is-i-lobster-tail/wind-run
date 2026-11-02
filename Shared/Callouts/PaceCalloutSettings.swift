//
//  PaceCalloutSettings.swift
//  Wind Run
//

import Foundation

/// What sets off a spoken split: covering a distance, or running for a time.
enum PaceCalloutMode: String, CaseIterable, Identifiable {
    case off
    case distance
    case time

    var id: Self { self }

    var name: String {
        switch self {
        case .off: "Off"
        case .distance: "Distance"
        case .time: "Time"
        }
    }
}

/// The runner's pace call-out choices, as they stand when a run starts.
struct PaceCalloutSettings: Equatable {
    static let modeKey = "paceCalloutMode"
    /// Stored in the runner's unit, so 0.25 is a quarter mile or 250 m.
    static let distanceKey = "paceCalloutDistance"
    static let secondsKey = "paceCalloutSeconds"

    static let distanceOptions: [Double] = [0.25, 0.5, 1, 2, 5]
    static let secondsOptions: [TimeInterval] = [30, 60, 120, 300, 600, 900, 1_800]
    static let defaultDistance: Double = 1
    static let defaultSeconds: TimeInterval = 300

    var mode: PaceCalloutMode
    var unit: DistanceUnit
    var distance: Double
    var seconds: TimeInterval

    init(
        mode: PaceCalloutMode,
        unit: DistanceUnit,
        distance: Double = Self.defaultDistance,
        seconds: TimeInterval = Self.defaultSeconds
    ) {
        self.mode = mode
        self.unit = unit
        self.distance = distance
        self.seconds = seconds
    }

    /// Reads the same values the settings screens write through `@AppStorage`.
    static func current(in defaults: UserDefaults = .standard) -> PaceCalloutSettings {
        let mode = defaults.string(forKey: modeKey).flatMap(PaceCalloutMode.init) ?? .off
        let unit = defaults.string(forKey: DistanceUnit.storageKey).flatMap(DistanceUnit.init) ?? .kilometers
        let distance = defaults.object(forKey: distanceKey) as? Double ?? defaultDistance
        let seconds = defaults.object(forKey: secondsKey) as? Double ?? defaultSeconds
        return PaceCalloutSettings(mode: mode, unit: unit, distance: distance, seconds: seconds)
    }

    /// When splits end, or nil when call-outs are off.
    var trigger: PaceCalloutTrigger? {
        switch mode {
        case .off:
            return nil
        case .distance:
            guard distance > 0 else { return nil }
            return .distance(meters: distance * unit.meters)
        case .time:
            guard seconds > 0 else { return nil }
            return .time(seconds: seconds)
        }
    }

    /// "¼ mi" or "250 m" for a distance option.
    static func distanceName(_ distance: Double, unit: DistanceUnit) -> String {
        switch unit {
        case .miles:
            switch distance {
            case 0.25: return "¼ mi"
            case 0.5: return "½ mi"
            case 0.75: return "¾ mi"
            default: return "\(distance.formatted()) \(unit.symbol)"
            }
        case .kilometers:
            if distance < 1 {
                return "\(Int((distance * 1_000).rounded())) m"
            }
            return "\(distance.formatted()) \(unit.symbol)"
        }
    }

    /// "30 sec" or "5 min" for a time option.
    static func secondsName(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds)) sec"
        }
        if seconds.truncatingRemainder(dividingBy: 60) == 0 {
            return "\(Int(seconds / 60)) min"
        }
        return RunFormat.duration(seconds)
    }
}
