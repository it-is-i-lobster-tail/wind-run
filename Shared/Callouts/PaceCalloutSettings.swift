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

/// Which pace a split call-out says. The runner can pick more than one; they're said in this order.
enum PaceKind: String, CaseIterable, Identifiable {
    /// The split just run: the last quarter mile, or the last 5 minutes.
    case split
    /// The last whole kilometer or mile, whatever the split length.
    case lastUnit
    /// The whole run so far.
    case average
    /// Right now: the last 30 seconds of running.
    case current

    var id: Self { self }

    /// How long "current" looks back.
    static let currentWindow: TimeInterval = 30

    func name(unit: DistanceUnit) -> String {
        switch self {
        case .split: "This split"
        case .lastUnit: unit == .miles ? "Last mile" : "Last kilometer"
        case .average: "Average"
        case .current: "Current"
        }
    }

    func detail(unit: DistanceUnit) -> String {
        switch self {
        case .split: "The pace of the split you just ran."
        case .lastUnit: "Your pace over the last \(unit == .miles ? "mile" : "kilometer"), however long your splits are."
        case .average: "Your pace over the whole run so far."
        case .current: "Your pace right now, over the last 30 seconds."
        }
    }

    /// What's said before the pace: "pace", "average pace", "last mile pace".
    func spokenLabel(unit: DistanceUnit) -> String {
        switch self {
        case .split: "pace"
        case .lastUnit: unit == .miles ? "last mile pace" : "last kilometer pace"
        case .average: "average pace"
        case .current: "current pace"
        }
    }

    /// "split,average" as stored, in the order they're said. Unknown names are skipped.
    static func decode(_ stored: String) -> [PaceKind] {
        let picked = Set(stored.split(separator: ",").compactMap { PaceKind(rawValue: String($0)) })
        return allCases.filter { picked.contains($0) }
    }

    static func encode(_ kinds: some Sequence<PaceKind>) -> String {
        let picked = Set(kinds)
        return allCases.filter { picked.contains($0) }.map(\.rawValue).joined(separator: ",")
    }
}

/// The runner's pace call-out choices, as they stand when a run starts.
struct PaceCalloutSettings: Equatable {
    static let modeKey = "paceCalloutMode"
    /// Stored in the runner's unit, so 0.25 is a quarter mile or 250 m.
    static let distanceKey = "paceCalloutDistance"
    static let secondsKey = "paceCalloutSeconds"
    /// Which paces to say, as `PaceKind` names joined by commas. Empty says just the distance or time.
    static let pacesKey = "paceCalloutPaces"
    static let defaultPaces = PaceKind.split.rawValue

    static let distanceOptions: [Double] = [0.25, 0.5, 1, 2, 5]
    static let secondsOptions: [TimeInterval] = [30, 60, 120, 300, 600, 900, 1_800]
    static let defaultDistance: Double = 1
    static let defaultSeconds: TimeInterval = 300

    var mode: PaceCalloutMode
    var unit: DistanceUnit
    var distance: Double
    var seconds: TimeInterval
    var paces: [PaceKind]

    init(
        mode: PaceCalloutMode,
        unit: DistanceUnit,
        distance: Double = Self.defaultDistance,
        seconds: TimeInterval = Self.defaultSeconds,
        paces: [PaceKind] = [.split]
    ) {
        self.mode = mode
        self.unit = unit
        self.distance = distance
        self.seconds = seconds
        self.paces = paces
    }

    /// Reads the same values the settings screens write through `@AppStorage`.
    static func current(in defaults: UserDefaults = .standard) -> PaceCalloutSettings {
        let mode = defaults.string(forKey: modeKey).flatMap(PaceCalloutMode.init) ?? .off
        let unit = defaults.string(forKey: DistanceUnit.storageKey).flatMap(DistanceUnit.init) ?? .kilometers
        let distance = defaults.object(forKey: distanceKey) as? Double ?? defaultDistance
        let seconds = defaults.object(forKey: secondsKey) as? Double ?? defaultSeconds
        let paces = PaceKind.decode(defaults.string(forKey: pacesKey) ?? defaultPaces)
        return PaceCalloutSettings(mode: mode, unit: unit, distance: distance, seconds: seconds, paces: paces)
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
