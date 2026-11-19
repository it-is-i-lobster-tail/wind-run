//
//  DistanceUnitHeight.swift
//  Wind Run
//

import Foundation

/// Heights go with the distance unit: feet for a runner who counts in miles, meters otherwise.
extension DistanceUnit {
    static let metersPerFoot = 0.3048

    /// `meters` in this unit's height unit, unrounded.
    func height(fromMeters meters: Double) -> Double {
        self == .miles ? meters / Self.metersPerFoot : meters
    }

    /// "ft" or "m".
    var heightSymbol: String {
        self == .miles ? "ft" : "m"
    }

    /// "feet" or "meters", for VoiceOver.
    var spokenHeightUnit: String {
        self == .miles ? "feet" : "meters"
    }
}
