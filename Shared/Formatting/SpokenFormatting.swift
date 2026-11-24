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
            guard let fraction = mileFractions[hundredths] else { return "\(number(value)) miles" }
            return whole == 0 ? fraction.alone : "\(whole) and \(fraction.after) miles"
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

    /// The quarters of a mile said in words, keyed by hundredths: on their own ("quarter mile"), and after a
    /// whole number of miles ("1 and a quarter miles").
    private static let mileFractions: [Int: (alone: String, after: String)] = [
        25: ("quarter mile", "a quarter"),
        50: ("half mile", "a half"),
        75: ("three quarters of a mile", "three quarters"),
    ]

    /// "30 seconds", "5 minutes", "1 hour 5 minutes". Cut down to the second like the screen, so a pace
    /// shown as 5:12 is said as 5 minutes 12 seconds.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = RunFormat.wholeSeconds(seconds)
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
        RunFormat.secondsPerUnit(secondsPerKilometer, unit: unit).map { "\(duration($0)) per \(unit.singularName)" }
    }

    /// "7.5 miles per hour" or "12 kilometers per hour", to the nearest tenth, or nil when there's no
    /// speed worth saying. Whole numbers drop the ".0", as the voice clips were recorded.
    static func speed(_ secondsPerKilometer: TimeInterval?, unit: DistanceUnit) -> String? {
        guard let secondsPerKilometer, secondsPerKilometer > 0, secondsPerKilometer.isFinite else { return nil }
        let perHour = 3_600 / unit.perUnit(secondsPerKilometer)
        let tenths = (perHour * 10).rounded(.toNearestOrAwayFromZero)
        guard tenths > 0 else { return nil }
        let value = tenths / 10
        let spoken = value.formatted(.number.precision(.fractionLength(0...1)).locale(Locale(identifier: "en_US_POSIX")))
        let noun = tenths == 10 ? unit.singularName : unit.pluralName
        return "\(spoken) \(noun) per hour"
    }

    private static func count(_ value: Int, _ noun: String) -> String {
        value == 1 ? "1 \(noun)" : "\(value) \(noun)s"
    }

    /// "1.5" or "2.25", always with a dot since the phrases around it are English.
    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US_POSIX")))
    }
}
