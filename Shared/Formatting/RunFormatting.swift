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

    /// The unit system this unit goes with, which also sets height and weight in the coach.
    var systemName: String {
        switch self {
        case .kilometers: "Metric"
        case .miles: "Imperial"
        }
    }

    /// "km, kg, cm" or "mi, lb, ft and in", for where the runner picks a system.
    var systemExamples: String {
        switch self {
        case .kilometers: "km, kg, cm"
        case .miles: "mi, lb, ft and in"
        }
    }

    /// What this device's region uses for distance. The UK counts in miles too.
    static var regionDefault: DistanceUnit {
        Locale.current.measurementSystem == .metric ? .kilometers : .miles
    }

    /// Whether the runner has picked a unit on this device, or it came from another one.
    static func isChosen(in defaults: UserDefaults = .standard) -> Bool {
        defaults.string(forKey: storageKey).flatMap(DistanceUnit.init(rawValue:)) != nil
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

    /// "37 m", or "121 ft" for a runner who counts in miles. `sign` puts "+" or "−" in front.
    static func elevation(_ meters: Double, unit: DistanceUnit, sign: FloatingPointSign? = nil) -> String {
        let value = unit == .miles ? meters / 0.3048 : meters
        let number = Int(value.rounded())
        let prefix = switch sign {
        case .plus: "+"
        case .minus: "−"
        case nil: ""
        }
        return "\(prefix)\(number) \(unit == .miles ? "ft" : "m")"
    }

    /// "142 bpm", or a dash when there's no reading yet.
    static func heartRate(_ beatsPerMinute: Double?, withUnit: Bool = true) -> String {
        guard let beatsPerMinute, beatsPerMinute.isFinite, beatsPerMinute > 0 else {
            return withUnit ? "–– bpm" : "––"
        }
        let value = Int(beatsPerMinute.rounded())
        return withUnit ? "\(value) bpm" : "\(value)"
    }

    /// "172 spm", steps a minute, or a placeholder until the sensor says.
    static func cadence(_ stepsPerMinute: Double?, withUnit: Bool = true) -> String {
        guard let stepsPerMinute, stepsPerMinute.isFinite, stepsPerMinute >= 0 else {
            return withUnit ? "–– spm" : "––"
        }
        let value = Int(stepsPerMinute.rounded())
        return withUnit ? "\(value) spm" : "\(value)"
    }

    /// "8,412", a run's step count.
    static func steps(_ count: Double) -> String {
        Int(count.rounded()).formatted()
    }

    /// "64 bpm²", how widely heart rate varied around its mean.
    static func heartRateVariance(_ variance: Double) -> String {
        "\(max(0, variance).formatted(.number.precision(.fractionLength(0)))) bpm²"
    }

    /// "±8 bpm", the standard deviation, which is variance in plain beats per minute.
    static func heartRateDeviation(_ standardDeviation: Double) -> String {
        "±\(Int(max(0, standardDeviation).rounded())) bpm"
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

    /// How long an interval workout is: "45 min", "22 min + open warm up and cool down", "16 min + 2.00 km",
    /// "3 open steps". Open steps have no length, so they're named rather than left out of a total.
    static func intervalLength(_ timeline: [PlannedIntervalStep], unit: DistanceUnit) -> String {
        var seconds = 0.0
        var meters = 0.0
        var open: [IntervalStepChoice] = []
        for step in timeline {
            switch step.goal {
            case .time(let time): seconds += time
            case .distance(let distance): meters += distance
            case .open: open.append(IntervalStepChoice(kind: step.kind, isWalk: step.isWalk))
            }
        }

        var parts: [String] = []
        if seconds > 0 {
            parts.append("\(max(1, Int((seconds / 60).rounded()))) min")
        }
        if meters > 0 {
            parts.append(goal(.distance(meters: meters), unit: unit))
        }
        if !open.isEmpty {
            parts.append(openSteps(open))
        }
        return parts.isEmpty ? "No steps" : parts.joined(separator: " + ")
    }

    /// "open warm up and cool down" when only the ends are open, as runners usually build them; otherwise
    /// "2 open steps".
    private static func openSteps(_ open: [IntervalStepChoice]) -> String {
        let ends = [IntervalStepChoice.warmup, .cooldown].filter(open.contains)
        if open.count == ends.count {
            return "open " + ends.map { $0.name.lowercased() }.joined(separator: " and ")
        }
        return open.count == 1 ? "1 open step" : "\(open.count) open steps"
    }
}
