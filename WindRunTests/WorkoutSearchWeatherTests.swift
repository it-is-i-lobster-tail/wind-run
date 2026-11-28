import Foundation
import Testing
@testable import WindRun

/// Searching by the weather saved with each run: the sky, temperature, wind, and the weather words a
/// runner wrote in a title or note.
@MainActor
struct WorkoutSearchWeatherTests {
    private func weather(_ celsius: Double, _ condition: String, _ symbol: String, wind: Double = 2, cloud: Double = 0.5,
                         humidity: Double = 0.5, daylight: Bool = true) -> WorkoutSearchWeather {
        WorkoutSearchWeather(temperature: celsius, humidity: humidity, cloudCover: cloud, windSpeed: wind,
                             condition: condition, symbolName: symbol, isDaylight: daylight)
    }

    private func record(_ city: String, daysAgo: Double, notes: String = "", km: Double = 8,
                        weather: WorkoutSearchWeather?) -> WorkoutSearchRecord {
        WorkoutSearchRecord(id: UUID(), date: Date.now.addingTimeInterval(-daysAgo * 86_400), sport: "running", type: "free",
                            title: "", notes: notes, distance: km * 1000, duration: km * 330,
                            place: WorkoutSearchPlace(address: "", city: city, state: "OR", country: "US"),
                            terrain: [], weather: weather)
    }

    private var drizzle: WorkoutSearchRecord { record("Portland", daysAgo: 1, weather: weather(3, "Drizzle", "cloud.drizzle", cloud: 0.9, humidity: 0.9)) }

    private func search(_ query: String, in records: [WorkoutSearchRecord], miles: Bool = true) -> WorkoutSearchResult {
        WorkoutSearchEngine.search(WorkoutSearchEngine.parse(query, climbInFeet: miles), in: records)
    }

    @Test func rainAndSnowReadTheSavedSky() {
        let rain = drizzle
        let snow = record("Bend", daysAgo: 3, weather: weather(-4, "Snow", "cloud.snow", wind: 8, cloud: 1))
        let sun = record("Salem", daysAgo: 5, weather: weather(31, "Clear", "sun.max", cloud: 0.05, humidity: 0.75))
        let none = record("Eugene", daysAgo: 7, weather: nil)
        let all = [rain, snow, sun, none]
        #expect(search("rainy runs", in: all).ids == [rain.id])
        #expect(search("runs in the rain", in: all).ids == [rain.id])
        #expect(search("runs in the rain", in: all).appliedIntent.filters.contains { if case .place = $0 { true } else { false } } == false)
        #expect(search("in the snow", in: all).ids == [snow.id])
        #expect(search("sunny", in: all).ids == [sun.id])
        #expect(search("humid runs", in: all).ids == [sun.id])
        #expect(search("weather", in: all).ids.count == 3)
    }

    @Test func aWeatherWordInANoteCountsWithoutSavedWeather() {
        let written = record("Medford", daysAgo: 9, notes: "rainy and cold", weather: nil)
        let dry = record("Salem", daysAgo: 5, weather: weather(31, "Clear", "sun.max", cloud: 0.05))
        #expect(search("rainy runs", in: [written, dry]).ids == [written.id])
        #expect(search("cold runs", in: [written, dry]).ids == [written.id])
        // A note search stays a note search.
        #expect(search("notes mention rain", in: [written, dry]).appliedIntent.filters == [.notes("rain")])
    }

    @Test func temperaturesFollowTheUnitAndRoundAsShown() {
        let cold = drizzle
        let edge = record("Ashland", daysAgo: 11, weather: weather(4.6, "Partly Cloudy", "cloud.sun", cloud: 0.4))  // Shown as 40°F.
        let hot = record("Salem", daysAgo: 5, weather: weather(31, "Clear", "sun.max", cloud: 0.05))
        let all = [cold, edge, hot]
        let below = search("below 40°F", in: all)
        #expect(below.ids == [cold.id])
        #expect(below.closeIDs == [edge.id])
        #expect(search("runs under 40 degrees", in: all).appliedIntent.filters.first?.label == "Below 40°F")
        #expect(search("runs under 5 degrees", in: all, miles: false).appliedIntent.filters.first?.label == "Below 5°C")
        #expect(search("around 40F", in: all).ids == [cold.id, edge.id])
        #expect(search("temperature above 85", in: all).ids == [hot.id])
        #expect(search("hot runs", in: all).ids == [hot.id])
        #expect(search("freezing", in: all).ids.isEmpty)
    }

    @Test func windAndWeatherRankings() {
        let calm = drizzle
        let gusty = record("Bend", daysAgo: 3, weather: weather(-4, "Snow", "cloud.snow", wind: 8, cloud: 1))
        let breezy = record("Eugene", daysAgo: 7, weather: weather(15, "Mostly Cloudy", "cloud", wind: 5, cloud: 0.8))
        let all = [calm, gusty, breezy, record("Salem", daysAgo: 9, weather: nil)]
        #expect(search("windy runs", in: all).ids == [gusty.id])
        #expect(search("wind over 10 mph", in: all).ids == [gusty.id, breezy.id])
        #expect(search("windiest runs", in: all).ids == [gusty.id, breezy.id, calm.id])
        #expect(search("coldest runs", in: all).ids == [gusty.id, calm.id, breezy.id])
        #expect(search("hottest run", in: all).ids.first == breezy.id)
        #expect(search("cloudy", in: all).ids == [breezy.id])
    }

    @Test func warmUpIsNotWarmWeather() {
        let filters = search("warm up", in: [drizzle]).appliedIntent.filters
        #expect(!filters.contains { if case .temperature = $0 { true } else { false } })
    }

    @Test func savedRunWeatherReachesTheRecord() {
        let run = Run(startDate: .now.addingTimeInterval(-3_600))
        run.finish(at: .now)
        #expect(WorkoutSearchWeather.of(run) == nil)
        run.saveWeather(RunWeather(temperature: 2, feelsLike: -1, humidity: 0.8, cloudCover: 1, windSpeed: 7, windGust: 11,
                                   windFrom: 270, symbolName: "cloud.rain", condition: "Rain", isDaylight: true,
                                   date: .now, isCurrent: true))
        let copied = WorkoutSearchWeather.of(run)
        #expect(copied?.temperature == 2)
        #expect(copied?.windSpeed == 7)
        #expect(copied.map(WorkoutSearchSky.rain.matches) == true)
        #expect(WorkoutSearchRecord(run: run, facts: nil).weather == copied)
    }

    @Test func rainShowsUpInSuggestionsWhenTheHistoryHasIt() {
        let rains = (0..<3).map { _ in drizzle }
        #expect(WorkoutSearchSuggestions.phrases(for: rains, unit: .miles).contains("Rainy runs"))
    }
}
