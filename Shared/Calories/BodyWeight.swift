//
//  BodyWeight.swift
//  Wind Run
//

import Foundation

/// The runner's weight, for working out calories. Asked when the iPhone app first opens and changed in
/// Settings. It stays on this iPhone: it isn't in `CloudSettings.keys`, and the watch doesn't get it.
enum BodyWeight {
    static let storageKey = "bodyWeightKilograms"
    /// Weights outside this are taken as a typo.
    static let range: ClosedRange<Double> = 25...300
    static let kilogramsPerPound = 0.453_592_37

    /// The saved weight in kilograms, or nil when none was given.
    static func kilograms(in defaults: UserDefaults = .standard) -> Double? {
        let value = defaults.double(forKey: storageKey)
        return range.contains(value) ? value : nil
    }

    /// Saves a weight, or forgets it when it's nil or out of range.
    static func save(_ kilograms: Double?, in defaults: UserDefaults = .standard) {
        if let kilograms, range.contains(kilograms) {
            defaults.set(kilograms, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
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
