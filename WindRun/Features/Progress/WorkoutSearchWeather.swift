import Foundation

/// The weather during a workout as search reads it, copied from the run's saved Apple Weather readings
/// (`RunWeather`). Workouts without weather have none, so weather searches never match them.
nonisolated struct WorkoutSearchWeather: Hashable, Sendable {
    /// Degrees Celsius.
    var temperature: Double
    /// Relative humidity and cloud cover, 0 to 1.
    var humidity: Double
    var cloudCover: Double
    /// Meters a second.
    var windSpeed: Double
    /// Apple Weather's words and symbol for the sky, such as "Drizzle" and "cloud.drizzle".
    var condition: String
    var symbolName: String
    var isDaylight: Bool?

    /// "Windy" starts at 15 mph (24 km/h), "breezy" at 10 mph (16 km/h).
    static let windy = 6.7
    static let breezy = 4.5
    /// Below 41°F (5°C) is cold, below 50°F (10°C) chilly, freezing at 32°F (0°C) and under,
    /// warm from 68°F (20°C) and hot from 80°F (about 27°C).
    static let cold = 5.0, chilly = 10.0, freezing = 0.0, warm = 20.0, hot = (80.0 - 32) * 5 / 9
    /// A bare "40°F" finds runs within about 5°F of it, and a bare "10 mph wind" within about 3 mph.
    static let temperatureAbout = 2.5
    static let windAbout = 1.5

    private var sky: String { (condition + " " + symbolName).lowercased() }
    private func says(_ words: [String]) -> Bool { words.contains { sky.contains($0) } }

    var isRain: Bool { says(["rain", "drizzle", "shower"]) }
    var isSnow: Bool { says(["snow", "sleet", "flurr", "blizzard", "wintry", "hail"]) }
    var isStorm: Bool { says(["thunder", "storm", "bolt", "tropical"]) }
    var isFog: Bool { says(["fog", "haze", "hazy", "smoke", "mist", "dust"]) }
    var isWet: Bool { isRain || isSnow || isStorm }
    var isCloudy: Bool { !isWet && (cloudCover >= 0.65 || (says(["cloudy", "overcast"]) && !says(["partly"]))) }
    var isClear: Bool { !isWet && !isFog && cloudCover <= 0.3 }
}

/// What the sky was doing, for "rainy runs", "in the snow" or "sunny".
enum WorkoutSearchSky: String, Codable, Hashable {
    /// Any workout with weather saved.
    case any
    case rain, snow, storm, fog, cloudy, clear, sunny
    /// Muggy: humid air that's also warm.
    case humid

    var label: String {
        switch self {
        case .any: "Has weather"
        case .rain: "Rain"
        case .snow: "Snow"
        case .storm: "Storms"
        case .fog: "Fog"
        case .cloudy: "Cloudy"
        case .clear: "Clear skies"
        case .sunny: "Sunny"
        case .humid: "Humid"
        }
    }

    func matches(_ weather: WorkoutSearchWeather) -> Bool {
        switch self {
        case .any: true
        case .rain: weather.isRain || weather.isStorm
        case .snow: weather.isSnow
        case .storm: weather.isStorm
        case .fog: weather.isFog
        case .cloudy: weather.isCloudy
        case .clear: weather.isClear
        case .sunny: weather.isClear && weather.isDaylight != false
        case .humid: weather.humidity >= 0.7 && weather.temperature >= 18
        }
    }
}

enum WorkoutSearchTemperature {
    /// True when a temperature filter's label was typed in Fahrenheit, such as "Below 40°F".
    static func isFahrenheit(_ label: String) -> Bool { label.contains("°F") }

    /// A reading as the row shows it: whole degrees in the unit the search was typed in, so "below 40°F"
    /// never lists a run shown as 40°.
    static func shown(_ celsius: Double, fahrenheit: Bool) -> Double {
        fahrenheit ? ((celsius * 9 / 5 + 32).rounded() - 32) * 5 / 9 : celsius.rounded()
    }

    static func celsius(_ value: Double, fahrenheit: Bool) -> Double { fahrenheit ? (value - 32) * 5 / 9 : value }

    /// The lowest and highest reading a comparison allows. "About" is a window either side, not a share.
    static func bounds(_ op: WorkoutSearchComparison, _ target: Double, about: Double) -> (low: Double, high: Double) {
        switch op {
        case .about: (target - about, target + about)
        case .greater, .atLeast: (target, .infinity)
        case .less, .atMost: (-.infinity, target)
        case .equal: (target, target)
        }
    }

    static func matches(_ value: Double, _ op: WorkoutSearchComparison, _ target: Double, about: Double) -> Bool {
        switch op {
        case .about: abs(value - target) <= about + 0.000_001
        case .greater: value > target
        case .atLeast: value >= target - 0.000_001
        case .less: value < target
        case .atMost: value <= target + 0.000_001
        case .equal: abs(value - target) < 0.000_001
        }
    }
}

extension WorkoutSearchFilter {
    /// Words that say the same weather in a title or note, such as "rainy" or "drizzle" for rain. Runs from
    /// before weather was saved, or with it turned off, still match a weather word their runner wrote down.
    var weatherWords: Set<String> {
        switch self {
        case .sky(let sky, _):
            switch sky {
            case .any: ["weather"]
            case .rain: ["rain", "rainy", "raining", "rained", "drizzle", "drizzly", "showers", "wet", "downpour", "storm", "stormy"]
            case .snow: ["snow", "snowy", "snowing", "snowed", "sleet", "blizzard", "flurries"]
            case .storm: ["storm", "stormy", "thunder", "thunderstorm", "thunderstorms", "lightning"]
            case .fog: ["fog", "foggy", "mist", "misty", "haze", "hazy", "smoke", "smoky"]
            case .cloudy: ["cloudy", "overcast", "clouds", "grey", "gray"]
            case .clear: ["clear", "sunny", "sunshine"]
            case .sunny: ["sunny", "sunshine", "sun"]
            case .humid: ["humid", "humidity", "muggy", "sticky"]
            }
        case .temperature(_, _, let label):
            switch String(label.prefix { $0 != " " }) {
            case "Cold": ["cold", "chilly", "freezing", "frigid", "icy", "frost", "frosty"]
            case "Chilly": ["chilly", "cold", "cool", "crisp"]
            case "Freezing": ["freezing", "frozen", "icy", "frost", "frosty", "frigid"]
            case "Warm": ["warm", "hot", "heat"]
            case "Hot": ["hot", "heat", "scorching", "sweltering", "heatwave"]
            default: []
            }
        case .wind(_, _, let label):
            label.hasPrefix("Windy") || label.hasPrefix("Breezy") ? ["windy", "gusty", "breezy", "gale", "headwind", "headwinds"] : []
        default: []
        }
    }
}
