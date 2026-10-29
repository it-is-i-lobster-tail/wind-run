//
//  CoachBasics.swift
//  Wind Run
//

import Foundation

/// A day of the week, numbered like `Calendar`'s weekday component (Sunday is 1).
enum Weekday: Int, Codable, CaseIterable, Comparable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var name: String {
        switch self {
        case .sunday: "Sunday"
        case .monday: "Monday"
        case .tuesday: "Tuesday"
        case .wednesday: "Wednesday"
        case .thursday: "Thursday"
        case .friday: "Friday"
        case .saturday: "Saturday"
        }
    }

    var shortName: String { String(name.prefix(3)) }

    var isWeekend: Bool { self == .saturday || self == .sunday }

    /// The weekday `days` after this one, wrapping around the week.
    func adding(_ days: Int) -> Weekday {
        let index = ((rawValue - 1 + days) % 7 + 7) % 7
        return Weekday(rawValue: index + 1) ?? self
    }

    init(of date: Date, calendar: Calendar) {
        self = Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .sunday
    }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension Double {
    /// Rounded down to a multiple of `step` (for "rounded down to 0.1 km").
    func floored(toMultipleOf step: Double) -> Double {
        guard step > 0 else { return self }
        return (self / step + 1e-9).rounded(.down) * step
    }

    func rounded(toMultipleOf step: Double) -> Double {
        guard step > 0 else { return self }
        return (self / step).rounded() * step
    }

    func ceiled(toMultipleOf step: Double) -> Double {
        guard step > 0 else { return self }
        return (self / step - 1e-9).rounded(.up) * step
    }

    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

/// Static safety text (AD-19, AD-19b). Never a question, a gate or a pause.
enum SafetyText {
    static let safetyLine = "Wind Run is a training app, not a medical device. Stop and get medical help if you have chest pain or pressure, faint, or feel unusually short of breath or unwell. In an emergency, call your local emergency number."
    static let stopLine = "Stop if you feel chest pain or pressure, faint, dizzy or very short of breath. If pain builds or makes you limp, stop and walk home, then tap Report injury."
}
