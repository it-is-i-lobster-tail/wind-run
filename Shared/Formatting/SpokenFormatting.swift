//
//  SpokenFormatting.swift
//  Wind Run
//

import Foundation

/// Words for the voice, not the screen: "2 minutes 13 seconds per mile" instead of "2:13 /mi".
///
/// Numbers stay as digits so the speech voice reads them naturally.
enum SpokenFormat {
    /// "Quarter mile", "1 and a half miles", "250 meters", "1.5 kilometers".
    static func distance(_ meters: Double, unit: DistanceUnit) -> String {
        // Rounded to hundredths so 4 × 402.336 m comes out as exactly 1 mile.
        let value = (meters / unit.meters * 100).rounded() / 100
        let whole = Int(value.rounded(.down))
        let hundredths = Int(((value - Double(whole)) * 100).rounded())

        switch unit {
        case .miles:
            if hundredths == 0 {
                return count(whole, "mile")
            }
            let fraction: String? = switch hundredths {
            case 25: "a quarter"
            case 50: "a half"
            case 75: "three quarters"
            default: nil
            }
            guard let fraction else { return "\(number(value)) miles" }
            if whole == 0 {
                return switch hundredths {
                case 25: "quarter mile"
                case 50: "half mile"
                default: "three quarters of a mile"
                }
            }
            return "\(whole) and \(fraction) miles"
        case .kilometers:
            if whole == 0 {
                return count(Int(meters.rounded()), "meter")
            }
            if hundredths == 0 {
                return count(whole, "kilometer")
            }
            return "\(number(value)) kilometers"
        }
    }

    /// "30 seconds", "5 minutes", "1 hour 5 minutes".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded())
        let parts = [
            (total / 3600, "hour"),
            ((total % 3600) / 60, "minute"),
            (total % 60, "second"),
        ]
        let spoken = parts.filter { $0.0 > 0 }.map { count($0.0, $0.1) }
        return spoken.isEmpty ? count(0, "second") : spoken.joined(separator: " ")
    }

    /// "8 minutes 33 seconds per mile", or nil when there's no pace worth saying.
    static func pace(_ secondsPerKilometer: TimeInterval?, unit: DistanceUnit) -> String? {
        guard let secondsPerKilometer, secondsPerKilometer.isFinite, secondsPerKilometer > 0 else { return nil }
        let perUnit = secondsPerKilometer * unit.meters / 1_000
        // Same cutoff as the screen: slower than an hour per unit is a stop, not a pace.
        guard perUnit < 3600 else { return nil }
        return "\(duration(perUnit)) per \(unitName(unit))"
    }

    private static func unitName(_ unit: DistanceUnit) -> String {
        switch unit {
        case .kilometers: "kilometer"
        case .miles: "mile"
        }
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        value == 1 ? "1 \(noun)" : "\(value) \(noun)s"
    }

    /// "1.5" or "2.25", always with a dot since the phrases around it are English.
    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX")))
    }
}
