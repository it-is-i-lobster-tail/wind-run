import Foundation

// The engine reads only these parts of the app's distance setting.
enum DistanceUnit: String {
    case kilometers, miles
    static let storageKey = "distanceUnit"
    var meters: Double { self == .miles ? 1609.344 : 1000 }
}
