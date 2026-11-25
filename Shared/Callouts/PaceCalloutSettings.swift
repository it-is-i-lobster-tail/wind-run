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
    /// The split just run, as a speed: "5.4 miles per hour".
    case speed

    var id: Self { self }

    /// How long "current" looks back.
    static let currentWindow: TimeInterval = 30

    func name(unit: DistanceUnit) -> String {
        switch self {
        case .split: "This split"
        case .lastUnit: "Last \(unit.singularName)"
        case .average: "Average"
        case .current: "Current"
        case .speed: "Speed"
        }
    }

    func detail(unit: DistanceUnit, sport: WorkoutSport = .running) -> String {
        let verb = sport == .hiking ? "hiked" : sport == .cycling ? "rode" : "ran"
        return switch self {
        case .split: "The pace of the split you just \(verb)."
        case .lastUnit: "Your pace over the last \(unit.singularName), however long your splits are."
        case .average: "Your pace over the whole \(sport.noun) so far."
        case .current: "Your pace right now, over the last 30 seconds."
        case .speed: "Your speed over the split you just \(verb), in \(unit.pluralName) per hour."
        }
    }

    /// What's said before the pace: "pace", "average pace", "last mile pace", or "speed".
    func spokenLabel(unit: DistanceUnit) -> String {
        switch self {
        case .split: "pace"
        case .lastUnit: "last \(unit.singularName) pace"
        case .average: "average pace"
        case .current: "current pace"
        case .speed: "speed"
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
    /// The paces said until the runner picks others.
    static let defaultPaceKinds: [PaceKind] = [.split]
    /// `defaultPaceKinds` as stored: "split".
    static let defaultPaces = PaceKind.encode(defaultPaceKinds)

    static func defaultPaceKinds(for sport: WorkoutSport) -> [PaceKind] {
        switch sport {
        case .running, .hiking: defaultPaceKinds
        case .cycling: [.speed]
        }
    }

    static let distanceOptions: [Double] = [0.25, 0.5, 1, 2, 5]
    static let secondsOptions: [TimeInterval] = [30, 60, 120, 300, 600, 900, 1_800]
    static let defaultDistance: Double = 1
    static let defaultSeconds: TimeInterval = 300

    /// Running keeps the original preference keys, including across app upgrades.
    static func key(_ base: String, for sport: WorkoutSport) -> String {
        sport == .running ? base : "\(base).\(sport.rawValue)"
    }

    static let syncedKeys = WorkoutSport.allCases.flatMap { sport in
        [modeKey, distanceKey, secondsKey, pacesKey].map { key($0, for: sport) }
    }
    static let numericKeys = WorkoutSport.allCases.flatMap { sport in
        [distanceKey, secondsKey].map { key($0, for: sport) }
    }

    let sport: WorkoutSport
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
        paces: [PaceKind]? = nil,
        sport: WorkoutSport = .running
    ) {
        self.sport = sport
        self.mode = mode
        self.unit = unit
        self.distance = distance
        self.seconds = seconds
        self.paces = paces ?? Self.defaultPaceKinds(for: sport)
    }

    /// Reads the same values the settings screens write through `@AppStorage`.
    static func current(for sport: WorkoutSport = .running, in defaults: UserDefaults = .standard) -> PaceCalloutSettings {
        let mode = defaults.string(forKey: key(modeKey, for: sport)).flatMap(PaceCalloutMode.init) ?? .off
        let unit = DistanceUnit.current(in: defaults)
        let distance = defaults.object(forKey: key(distanceKey, for: sport)) as? Double ?? defaultDistance
        let seconds = defaults.object(forKey: key(secondsKey, for: sport)) as? Double ?? defaultSeconds
        let paces = defaults.string(forKey: key(pacesKey, for: sport)).map { PaceKind.decode($0) }
        return PaceCalloutSettings(mode: mode, unit: unit, distance: distance, seconds: seconds, paces: paces, sport: sport)
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

    /// "Off", "Every ¼ mi" or "Every 5 min", for the call-outs row in Settings.
    static func summary(mode: PaceCalloutMode, distance: Double, seconds: TimeInterval, unit: DistanceUnit) -> String {
        switch mode {
        case .off: "Off"
        case .distance: "Every \(distanceName(distance, unit: unit))"
        case .time: "Every \(secondsName(seconds))"
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
        return RunFormat.wholeMinutes(seconds) ?? RunFormat.duration(seconds)
    }
}
