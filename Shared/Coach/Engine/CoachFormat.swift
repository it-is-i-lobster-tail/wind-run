//
//  CoachFormat.swift
//  Wind Run
//

import Foundation

/// Numbers in the coach's sentences, in the runner's unit: "10.6 km", "45 min", "6:24/km".
enum CoachFormat {
    /// "10.6 km", or "10 km" when the value is whole.
    static func distance(_ meters: Double, unit: DistanceUnit, digits: Int = 1) -> String {
        let value = meters / unit.meters
        let rounded = (value * pow(10, Double(digits))).rounded() / pow(10, Double(digits))
        if rounded == rounded.rounded() {
            return "\(Int(rounded)) \(unit.symbol)"
        }
        return String(format: "%.\(digits)f \(unit.symbol)", rounded)
    }

    /// "45 min", "1 h 30 min".
    static func minutes(_ seconds: Double) -> String {
        let total = Int((seconds / 60).rounded())
        if total >= 60 {
            let hours = total / 60
            let minutes = total % 60
            return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
        }
        return "\(total) min"
    }

    /// An amount in the plan's volume unit: a distance, or running minutes.
    static func amount(_ value: Double, in volumeUnit: VolumeUnit, unit: DistanceUnit) -> String {
        switch volumeUnit {
        case .distance: distance(value, unit: unit)
        case .time: minutes(value)
        }
    }

    /// The part of a load the plan counts.
    static func load(_ load: Load, in volumeUnit: VolumeUnit, unit: DistanceUnit) -> String {
        amount(load.amount(in: volumeUnit), in: volumeUnit, unit: unit)
    }

    /// "6:24/km" from seconds per kilometer.
    static func pace(_ secondsPerKilometer: Double, unit: DistanceUnit) -> String {
        let perUnit = secondsPerKilometer * unit.meters / 1_000
        return "\(clock(perUnit))/\(unit.symbol)"
    }

    /// "6:24-7:00/km".
    static func paceRange(_ band: PaceBand, unit: DistanceUnit) -> String {
        let fast = clock(band.fast * unit.meters / 1_000)
        let slow = clock(band.slow * unit.meters / 1_000)
        return "\(fast)-\(slow)/\(unit.symbol)"
    }

    /// "52:29" under an hour, "2:01:49" past it.
    static func clock(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// "9.1%" with one decimal, or "2%" when whole.
    static func percent(_ fraction: Double) -> String {
        let value = (fraction * 1000).rounded() / 10
        if value == value.rounded() {
            return "\(Int(value))%"
        }
        return String(format: "%.1f%%", value)
    }

    /// "21 October".
    static func date(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.day, .month], from: date)
        guard let day = components.day, let month = components.month else { return "" }
        let names = calendar.monthSymbols
        let monthName = names.indices.contains(month - 1) ? names[month - 1] : ""
        return "\(day) \(monthName)"
    }

    /// "3 weeks", "1 week".
    static func weeks(_ count: Int) -> String {
        count == 1 ? "1 week" : "\(count) weeks"
    }
}
