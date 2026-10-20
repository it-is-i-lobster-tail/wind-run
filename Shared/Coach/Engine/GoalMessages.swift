//
//  GoalMessages.swift
//  Wind Run
//

import Foundation

/// The pieces the realism check's sentences share (RC-1, RC-8, SW-1a, EF-3).
extension CoachFormat {
    /// "about 2 weeks" when the ends match, "about 2-4 weeks" otherwise (RC-8d's earliest-likely range).
    static func weekRange(_ low: Int, _ high: Int) -> String {
        let low = max(0, low)
        let high = max(0, high)
        if low == high { return "about \(weeks(low))" }
        return "about \(min(low, high))-\(max(low, high)) weeks"
    }

    /// A round number the rules give in both units, such as "16 km" or "10 mi" (RC-1, HL-26).
    static func distance(km: Double, mi: Double, unit: DistanceUnit) -> String {
        let value = unit == .miles ? mi : km
        let text = value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
        return "\(text) \(unit.symbol)"
    }

    /// A time goal by name: "sub-20" for 20:00, "sub-1:45" for 1:45:00, "sub-22:30" otherwise (SW-1a).
    static func goalName(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total % 60 == 0 {
            let minutes = total / 60
            if minutes >= 60 { return String(format: "sub-%d:%02d", minutes / 60, minutes % 60) }
            return "sub-\(minutes)"
        }
        return "sub-\(clock(seconds))"
    }

    /// A race time rounded to the minute past an hour ("1:54"), to the second below ("24:09").
    static func roughClock(_ seconds: Double) -> String {
        guard seconds >= 3_600 else { return clock(seconds) }
        let minutes = Int((seconds / 60).rounded())
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// The first letter in capitals, for a name that opens a sentence.
    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// "a" or "an" before a number or name as it is spoken: "an 8-week block", "an 11 km run", "a 10K".
    static func article(for text: String) -> String {
        let digits = text.prefix { $0.isNumber }
        if let value = Int(digits), !digits.isEmpty {
            if value == 8 || value == 11 || value == 18 || (80 ... 89).contains(value) || (800 ... 899).contains(value) {
                return "an"
            }
            return "a"
        }
        guard let first = text.lowercased().first else { return "a" }
        return "aeiou".contains(first) ? "an" : "a"
    }

    /// "two" to "nine" in words, digits from 10 (the coach's style for small counts).
    static func count(_ value: Int) -> String {
        let words = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        return words.indices.contains(value) ? words[value] : "\(value)"
    }
}

extension RaceDistance {
    /// The distance in a sentence after "a" or "the": "half marathon", "10K", "mile".
    var sentenceName: String {
        switch self {
        case .mile: "mile"
        case .fiveK: "5K"
        case .tenK: "10K"
        case .halfMarathon: "half marathon"
        case .marathon: "marathon"
        }
    }
}
