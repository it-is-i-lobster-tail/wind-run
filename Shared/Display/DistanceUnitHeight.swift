//
//  DistanceUnitHeight.swift
//  Wind Run
//

import Foundation

/// Heights go with the distance unit: feet for a runner who counts in miles, meters otherwise.
/// `metersPerFoot` and `heightSymbol` live with the rest of DistanceUnit in RunFormatting.swift.
extension DistanceUnit {
    /// `meters` in this unit's height unit, unrounded.
    func height(fromMeters meters: Double) -> Double {
        self == .miles ? meters / Self.metersPerFoot : meters
    }

    /// "feet" or "meters", for VoiceOver.
    var spokenHeightUnit: String {
        self == .miles ? "feet" : "meters"
    }
}
