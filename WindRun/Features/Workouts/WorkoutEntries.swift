//
//  WorkoutEntries.swift
//  Wind Run
//

import Foundation

/// What the target pace page shows and how it reads back: m:ss per kilometer or mile, stored as seconds per
/// kilometer.
struct PaceEntry: Equatable {
    var isRange: Bool
    var single: String
    var faster: String
    var slower: String
    /// The workout's unit, which the boxes are in.
    let unit: DistanceUnit
    // Each box's pace in seconds per kilometer as the workout has it, kept until the box is changed, so opening
    // the page or switching the workout's unit never rounds it: only the boxes round to whole seconds.
    private var exactSingle: TimeInterval?
    private var exactFaster: TimeInterval?
    private var exactSlower: TimeInterval?

    /// The page for a workout's pace, or for a new one: 6:00 /km or 9:30 /mi to change from.
    init(_ pace: ClosedRange<TimeInterval>?, unit: DistanceUnit) {
        self.unit = unit
        let fallback = unit == .miles ? Self.perKilometer(9 * 60 + 30, unit: .miles) : 6 * 60
        let start = pace ?? fallback...fallback
        isRange = start.lowerBound != start.upperBound
        exactFaster = start.lowerBound
        exactSlower = start.upperBound
        let middle = isRange ? (start.lowerBound + start.upperBound) / 2 : start.lowerBound
        exactSingle = middle
        single = Self.text(middle, unit: unit)
        faster = Self.text(start.lowerBound, unit: unit)
        slower = Self.text(start.upperBound, unit: unit)
    }

    /// The pace as typed, seconds per kilometer, fastest first, or nil while a box doesn't read as a pace.
    var pace: ClosedRange<TimeInterval>? {
        if isRange {
            guard let fast = Self.value(faster, exact: exactFaster, unit: unit),
                  let slow = Self.value(slower, exact: exactSlower, unit: unit) else { return nil }
            return min(fast, slow)...max(fast, slow)
        }
        guard let one = Self.value(single, exact: exactSingle, unit: unit) else { return nil }
        return one...one
    }

    /// A box's pace, seconds per kilometer: its exact pace while it still shows it, or else what's typed.
    private static func value(_ text: String, exact: TimeInterval?, unit: DistanceUnit) -> TimeInterval? {
        if let exact, text == Self.text(exact, unit: unit) { return exact }
        return IntervalSetEntry.seconds(text).map { perKilometer($0, unit: unit) }
    }

    /// Seconds per kilometer from seconds per `unit`.
    static func perKilometer(_ seconds: TimeInterval, unit: DistanceUnit) -> TimeInterval {
        unit.perKilometer(seconds)
    }

    /// "8:45" for a pace per `unit`, from seconds per kilometer.
    static func text(_ secondsPerKilometer: TimeInterval, unit: DistanceUnit) -> String {
        WorkoutDistance.pacePerUnit(secondsPerKilometer, unit: unit)
    }
}

/// The intervals card: work and recovery, both a time or both a distance in one unit. A time is typed as m:ss,
/// such as 5:00, and a distance as a number, such as 0.25. Each kind keeps what was typed, so switching
/// between them and back loses nothing.
struct IntervalSetEntry: Equatable {
    enum Kind: String {
        case time
        case distance
        case waypoint
    }

    var workEnd = WaypointEnd.startingPoint
    var recoveryEnd = WaypointEnd.startingPoint
    var kind: Kind
    var workTime: String
    var recoveryTime: String
    var workDistance: String
    var recoveryDistance: String
    /// The workout's unit, which the distances are typed in.
    let unit: DistanceUnit
    // The distances in meters as the workout has them, kept while their boxes still show them, so opening the
    // page never rounds them.
    private var exactWork: Double?
    private var exactRecovery: Double?

    /// The card for a saved set. One from before sets were all one kind, or with a step that waited for
    /// Next, takes its kind from the work and starts the odd step from a sensible amount.
    init(_ intervals: WorkoutMain.Intervals, unit: DistanceUnit) {
        var kind = Kind.time
        var workSeconds = WorkoutMain.Intervals.starterWorkSeconds
        var recoverySeconds = WorkoutMain.Intervals.starterRecoverySeconds
        // A quarter mile or 400 m.
        var workMeters = unit == .miles ? DistanceUnit.miles.meters / 4 : 400
        var recoveryMeters = workMeters
        switch (intervals.work, intervals.recovery) {
        case (.time(let work), .time(let recovery)):
            workSeconds = work
            recoverySeconds = recovery
        case (.time(let work), _):
            workSeconds = work
        case (.distance(let work), .distance(let recovery)):
            kind = .distance
            workMeters = work
            recoveryMeters = recovery
        case (.distance(let work), _):
            kind = .distance
            workMeters = work
            recoveryMeters = work
        case (.open, .time(let recovery)):
            recoverySeconds = recovery
        case (.open, .distance(let recovery)):
            kind = .distance
            workMeters = recovery
            recoveryMeters = recovery
        case (.waypoint(let work), .waypoint(let recovery)):
            kind = .waypoint
            workEnd = work
            recoveryEnd = recovery
        case (.waypoint, _), (.open, .waypoint), (.open, .open):
            break
        }
        self.kind = kind
        self.unit = unit
        workTime = Self.timeText(workSeconds)
        recoveryTime = Self.timeText(recoverySeconds)
        workDistance = WorkoutDistance.amount(workMeters, in: unit)
        recoveryDistance = WorkoutDistance.amount(recoveryMeters, in: unit)
        exactWork = workMeters
        exactRecovery = recoveryMeters
    }

    /// The set as typed, or nil while a box is empty or doesn't read as a time or distance.
    func intervals(repeats: Int) -> WorkoutMain.Intervals? {
        switch kind {
        case .waypoint: return .init(work: .waypoint(workEnd), recovery: .waypoint(recoveryEnd), repeats: repeats)
        case .time:
            guard let work = Self.seconds(workTime), let recovery = Self.seconds(recoveryTime) else { return nil }
            return .init(work: .time(work), recovery: .time(recovery), repeats: repeats)
        case .distance:
            guard let work = meters(workDistance, exact: exactWork), let recovery = meters(recoveryDistance, exact: exactRecovery) else { return nil }
            return .init(work: .distance(meters: work), recovery: .distance(meters: recovery), repeats: repeats)
        }
    }

    /// "14 min" or "2.5 km": the work and recovery, repeated.
    func total(repeats: Int) -> String? {
        guard let set = intervals(repeats: repeats) else { return nil }
        switch (set.work, set.recovery) {
        case (.time(let work), .time(let recovery)):
            return RunFormat.goal(.time(Double(repeats) * (work + recovery)), unit: unit)
        case (.distance(let work), .distance(let recovery)):
            return "\(WorkoutDistance.amount(Double(repeats) * (work + recovery), in: unit)) \(unit.symbol)"
        default:
            return nil
        }
    }

    /// A box's distance in meters: the exact one while the box still shows it, or else what's typed.
    private func meters(_ text: String, exact: Double?) -> Double? {
        if let exact, text == WorkoutDistance.amount(exact, in: unit) { return exact }
        return Self.amount(text).map { $0 * unit.meters }
    }

    /// "5:00" for 300 seconds.
    static func timeText(_ seconds: TimeInterval) -> String {
        WorkoutDistance.minutesSeconds(seconds)
    }

    /// The seconds in "5:00", "1:30" or "5" (minutes), or nil when it's empty, zero, or the seconds run past 59.
    static func seconds(_ text: String) -> TimeInterval? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count) else { return nil }
        let minutes = parts[0].isEmpty ? 0 : Int(parts[0])
        let seconds = parts.count == 2 ? (parts[1].isEmpty ? 0 : Int(parts[1])) : 0
        guard let minutes, let seconds, minutes >= 0, (0..<60).contains(seconds) else { return nil }
        let total = minutes * 60 + seconds
        return total > 0 ? TimeInterval(total) : nil
    }

    /// The number in "0.25" or "0,25", or nil when it's empty or zero.
    static func amount(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return value
    }
}
