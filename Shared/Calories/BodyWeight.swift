//
//  BodyWeight.swift
//  Wind Run
//

import Foundation

/// The runner's weight, for working out calories. Taken from Apple Health when it has a recent one, otherwise
/// asked when the iPhone app first opens, and changed in Settings. It goes to iCloud with the other settings
/// while iCloud Sync is on (Brendon, 2026-10-27); the watch doesn't get it.
enum BodyWeight {
    static let storageKey = "bodyWeightKilograms"
    /// When the saved weight was measured: when Health took it, or when the runner typed it.
    static let dateKey = "bodyWeightDate"
    /// A weight from Health older than this is too old to use (Brendon, 2026-10-27).
    static let healthMaximumAge: TimeInterval = 90 * 24 * 60 * 60
    /// Weights outside this are taken as a typo.
    static let range: ClosedRange<Double> = 25...300
    static let kilogramsPerPound = 0.453_592_37

    /// The saved weight in kilograms, or nil when none was given.
    static func kilograms(in defaults: UserDefaults = .standard) -> Double? {
        let value = defaults.double(forKey: storageKey)
        return range.contains(value) ? value : nil
    }

    /// Saves a weight measured at `date`, or forgets it when it's nil or out of range.
    static func save(_ kilograms: Double?, measuredAt date: Date = .now, in defaults: UserDefaults = .standard) {
        if let kilograms, range.contains(kilograms) {
            defaults.set(kilograms, forKey: storageKey)
            defaults.set(date, forKey: dateKey)
        } else {
            defaults.removeObject(forKey: storageKey)
            defaults.removeObject(forKey: dateKey)
        }
    }

    /// When the saved weight was measured, or nil when there's none or it was saved before dates were kept.
    static func date(in defaults: UserDefaults = .standard) -> Date? {
        kilograms(in: defaults) == nil ? nil : defaults.object(forKey: dateKey) as? Date
    }

    /// Takes a weight from Apple Health when it's from the last 3 months and newer than the saved one.
    /// Returns whether it was taken.
    @discardableResult
    static func adoptFromHealth(_ kilograms: Double, measuredAt date: Date, now: Date = .now, in defaults: UserDefaults = .standard) -> Bool {
        guard range.contains(kilograms), now.timeIntervalSince(date) <= healthMaximumAge else { return false }
        if let saved = Self.date(in: defaults), saved >= date { return false }
        save(kilograms, measuredAt: date, in: defaults)
        return true
    }

    /// A typed weight in kilograms, read as pounds with imperial units. Nil when it isn't a weight.
    static func kilograms(fromTyped text: String, unit: DistanceUnit) -> Double? {
        guard let number = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) else { return nil }
        let kilograms = unit == .miles ? number * kilogramsPerPound : number
        return range.contains(kilograms) ? kilograms : nil
    }

    /// The weight as the runner reads it: whole pounds with imperial units, kilograms to a tenth otherwise.
    static func typed(_ kilograms: Double, unit: DistanceUnit) -> String {
        switch unit {
        case .miles: String(Int((kilograms / kilogramsPerPound).rounded()))
        case .kilometers: kilograms.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
        }
    }
}
