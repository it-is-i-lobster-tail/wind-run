//
//  RunWeather.swift
//  Wind Run
//

import CoreLocation
import Foundation

/// The weather during a run, from Apple Weather, kept with the run as JSON (`Run.weatherDataValue`). It holds
/// readings only, never the place it was asked for.
nonisolated struct RunWeather: Codable, Equatable, Sendable {
    /// Degrees Celsius.
    var temperature: Double
    /// What the air felt like, in degrees Celsius.
    var feelsLike: Double?
    /// Relative humidity, 0 to 1.
    var humidity: Double
    /// How much of the sky was covered by cloud, 0 to 1.
    var cloudCover: Double
    /// Meters a second.
    var windSpeed: Double
    /// Meters a second, when Apple Weather gave gusts.
    var windGust: Double?
    /// The way the wind blew from, in degrees clockwise from north.
    var windFrom: Double
    /// The SF Symbol Apple Weather gave for the sky, such as "cloud.sun".
    var symbolName: String
    /// The sky in a few words, such as "Partly Cloudy".
    var condition: String
    /// Whether it was light out, for the condition's symbol.
    var isDaylight: Bool?
    /// The time the readings are for: the finish, when asked right after it, or else the start of the
    /// hour nearest the run's middle.
    var date: Date
    /// Whether these are the readings at the finish (true) or that hour's (false).
    var isCurrent: Bool
}

// MARK: - The place sent

extension RunWeather {
    /// How far to round the start, in degrees, before asking for its weather: 0.05° is about 5.5 km north to
    /// south, and less east to west away from the equator. Weather barely changes across that, and it says
    /// only roughly where the run was.
    static let roundingDegrees = 0.05

    /// The point sent to Apple Weather for a run that started at `start`: the middle of the 0.05° square it
    /// falls in, so every run in that square asks for the same place, and the place asked for is never more
    /// than about 4 km from the start.
    static func roundedLocation(near start: CLLocationCoordinate2D) -> CLLocation {
        func rounded(_ degrees: Double) -> Double {
            // Rounded to thousandths, so the result is exactly the square's middle.
            (((degrees / roundingDegrees).rounded(.down) + 0.5) * roundingDegrees * 1_000).rounded() / 1_000
        }
        return CLLocation(latitude: rounded(start.latitude), longitude: rounded(start.longitude))
    }

    /// Apple Weather's hourly history starts on August 1, 2021, so older runs have no weather to ask for.
    static let earliestHistory = Date(timeIntervalSince1970: 1_627_776_000)

    /// Runs that finished less than this long ago get the weather now, rather than that hour's.
    static let currentWindow: TimeInterval = 30 * 60
}

// MARK: - Showing it

extension RunWeather {
    /// "35°" in Fahrenheit for miles, or "2°" in Celsius for kilometers.
    static func temperature(_ celsius: Double, unit: DistanceUnit) -> String {
        let value = unit == .miles ? celsius * 9 / 5 + 32 : celsius
        let whole = Int(value.rounded())
        // "-0°" reads oddly, so a reading that rounds to nothing is 0.
        return "\(whole == 0 ? 0 : whole)°"
    }

    /// "17" mph for miles or km/h for kilometers, without the unit.
    static func windNumber(_ metersPerSecond: Double, unit: DistanceUnit) -> String {
        let value = unit == .miles ? metersPerSecond * 2.236_936 : metersPerSecond * 3.6
        return "\(Int(value.rounded()))"
    }

    /// "17 mph" or "27 km/h".
    static func wind(_ metersPerSecond: Double, unit: DistanceUnit) -> String {
        "\(windNumber(metersPerSecond, unit: unit)) \(windUnit(unit))"
    }

    static func windUnit(_ unit: DistanceUnit) -> String {
        unit == .miles ? "mph" : "km/h"
    }

    /// "62%".
    static func percent(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    /// The 16 compass points, "N" to "NNW", for where the wind blew from.
    static func compass(_ degrees: Double) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let normalized = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return points[Int((normalized / 22.5).rounded()) % 16]
    }

    /// The pill's words for VoiceOver: "35 degrees, Cloudy, wind 17 miles an hour from the west".
    func spoken(unit: DistanceUnit) -> String {
        let speed = Self.windNumber(windSpeed, unit: unit)
        let speedUnit = unit == .miles ? "miles an hour" : "kilometers an hour"
        let degrees = Self.temperature(temperature, unit: unit).dropLast()
        return "\(degrees) degrees, \(condition), wind \(speed) \(speedUnit) from the \(Self.spokenCompass(windFrom))"
    }

    private static func spokenCompass(_ degrees: Double) -> String {
        let words = ["N": "north", "E": "east", "S": "south", "W": "west"]
        return compass(degrees).map { words[String($0)] ?? "" }.joined(separator: " ")
    }
}

// MARK: - Stored on the run

extension Run {
    /// The weather during the run, or nil when none was fetched.
    var weather: RunWeather? {
        Self.decodedJSON(RunWeather.self, from: weatherDataValue)
    }

    func saveWeather(_ weather: RunWeather) {
        weatherDataValue = try? JSONEncoder().encode(weather)
    }
}
