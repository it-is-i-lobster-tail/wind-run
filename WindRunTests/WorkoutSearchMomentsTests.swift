import Foundation
import SwiftData
import Testing
@testable import WindRun

/// Place names before other words, time of day and weekday, best efforts, effort, similar routes,
/// suggestions, and the time zone each run keeps.
@MainActor
struct WorkoutSearchMomentsTests {
    private let pacific = TimeZone(identifier: "America/Los_Angeles")!
    private let eastern = TimeZone(identifier: "America/New_York")!

    /// 2026-11-25, a Wednesday, at this local hour in Los Angeles.
    private func date(day: Int = 25, hour: Int, minute: Int = 0, zone: TimeZone? = nil) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone ?? pacific
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func record(_ city: String = "Portland", state: String = "OR", passed: [String]? = nil, km: Double = 5,
                        minutes: Double = 30, at date: Date = .now, zone: TimeZone? = nil, title: String = "",
                        heartRate: Double? = nil, efforts: [Int: Double]? = nil, cells: [Int64]? = nil,
                        sport: String = "running") -> WorkoutSearchRecord {
        WorkoutSearchRecord(id: UUID(), date: date, sport: sport, type: "free", title: title, notes: "",
                            distance: km * 1000, duration: minutes * 60,
                            place: WorkoutSearchPlace(address: "", city: city, state: state, country: "US", passed: passed),
                            terrain: [], heartRate: heartRate, timeZone: zone ?? pacific, bestEfforts: efforts, cells: cells)
    }

    private func search(_ query: String, in records: [WorkoutSearchRecord], now: Date? = nil) -> WorkoutSearchResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = pacific
        let intent = WorkoutSearchEngine.parse(query, now: now ?? date(hour: 20), calendar: calendar,
                                               places: WorkoutSearchPlaceNames.known(in: records))
        return WorkoutSearchEngine.search(intent, in: records)
    }

    // MARK: Places first

    @Test func aKnownPlaceIsReadBeforeHillsAndOtherWords() {
        let nob = record("San Francisco", state: "CA", passed: ["Nob Hill"])
        let other = record("Portland")
        #expect(search("Nob Hill", in: [nob, other]).ids == [nob.id])
        #expect(search("runs through Nob Hill", in: [nob, other]).ids == [nob.id])
        #expect(search("runs through Nob Hill", in: [nob, other]).notUnderstood.isEmpty)
        // With no Nob Hill in the history, hill still means hills.
        let filters = search("Nob Hill", in: [other]).appliedIntent.filters
        #expect(filters.contains(.terrain(.hills)))
    }

    @Test func shortFormsAndNicknamesReadAsTheirPlace() {
        let louis = record("St. Louis", state: "MO"), vernon = record("Mount Vernon", state: "WA")
        let sf = record("San Francisco", state: "CA"), pdx = record("Portland", state: "OR")
        let all = [louis, vernon, sf, pdx]
        #expect(search("Saint Louis", in: all).ids == [louis.id])
        #expect(search("Saint Louis", in: all).notUnderstood.isEmpty)
        #expect(search("Mt Vernon", in: all).ids == [vernon.id])
        #expect(search("SF", in: all).ids == [sf.id])
        #expect(search("PDX", in: all).ids == [pdx.id])
        // A nickname only counts when the history has that city.
        #expect(search("NYC", in: all).ids.isEmpty)
        // "LA" stays Louisiana unless typed as "L.A." with Los Angeles in the history.
        #expect(!search("LA", in: all + [record("Los Angeles", state: "CA")]).appliedIntent.filters.contains(.place("Los Angeles, CA")))
    }

    // MARK: Time of day and weekday

    @Test func partsOfTheDayReadTheZoneEachRunStartedIn() {
        let dawn = record(at: date(hour: 6))
        let lunch = record(at: date(hour: 12, minute: 15))
        let dusk = record(at: date(hour: 18))
        // 7 AM in New York is 4 AM in Los Angeles: the run's own zone decides.
        let travel = record(at: date(day: 24, hour: 7, zone: eastern), zone: eastern)
        let all = [dawn, lunch, dusk, travel]
        #expect(Set(search("morning runs", in: all).ids) == [dawn.id, travel.id])
        #expect(search("lunch runs", in: all).ids == [lunch.id])
        #expect(search("evening runs", in: all).ids == [dusk.id])
        #expect(Set(search("before 8am", in: all).ids) == [dawn.id, travel.id])
        #expect(search("before 7am", in: all).ids == [dawn.id])
        #expect(search("after 5 pm", in: all).ids == [dusk.id])
        #expect(search("this morning", in: all, now: date(hour: 9)).ids == [dawn.id])
    }

    @Test func weekdaysWeekendsAndOneNamedDay() {
        let wednesday = record(at: date(day: 25, hour: 7))
        let saturday = record(at: date(day: 21, hour: 8))
        let sunday = record(at: date(day: 22, hour: 8))
        let earlierSaturday = record(at: date(day: 14, hour: 8))
        let all = [wednesday, saturday, sunday, earlierSaturday]
        #expect(Set(search("Saturday runs", in: all).ids) == [saturday.id, earlierSaturday.id])
        #expect(Set(search("weekend runs", in: all).ids) == [saturday.id, sunday.id, earlierSaturday.id])
        #expect(search("weekday runs", in: all).ids == [wednesday.id])
        #expect(search("last Saturday", in: all).ids == [saturday.id])
        #expect(Set(search("last weekend", in: all).ids) == [saturday.id, sunday.id])
        #expect(Set(search("Saturdays and Sundays", in: all).ids) == [saturday.id, sunday.id, earlierSaturday.id])
    }

    // MARK: Best efforts

    @Test func bestEffortsFindTheFastestStretchInsideLongerRuns() {
        // 10 km at a steady 5:00 per km, with the middle 5 km at 4:00 per km.
        var times: [TimeInterval] = [0], meters: [Double] = [0]
        for step in 1...100 {
            let pace: Double = step > 25 && step <= 75 ? 240 : 300
            times.append(times.last! + pace / 10)
            meters.append(Double(step) * 100)
        }
        let best = WorkoutSearchEfforts.best(times: times, meters: meters, stretches: Array(repeating: 0, count: times.count),
                                             totalMeters: 10_000)
        #expect(best[5_000] == 1_200)
        #expect(best[1_000] == 240)
        #expect(best[10_000] == 2_700)
        #expect(best[21_098] == nil)
    }

    @Test func aBestEffortNeverReadsAcrossAPause() {
        let times: [TimeInterval] = [0, 100, 200, 300, 400]
        let meters: [Double] = [0, 500, 1_000, 1_500, 2_000]
        // Two stretches of 1 km: the second starts after a pause, so no 2 km best.
        let best = WorkoutSearchEfforts.best(times: times, meters: meters, stretches: [0, 0, 0, 1, 1], totalMeters: 2_000)
        #expect(best[1_000] == 200)
        #expect(best[1_609] == nil)
    }

    @Test func fastestFiveKRanksBestEffortsAndSaysSo() {
        let quick = record(km: 10, efforts: [5_000: 1_250])
        let slow = record(km: 5, efforts: [5_000: 1_500])
        let short = record(km: 3, efforts: [1_000: 250])
        for query in ["fastest 5k", "best 5K time", "5k PR"] {
            let result = search(query, in: [slow, quick, short])
            #expect(result.appliedIntent.sort == .bestEffort, "\(query)")
            #expect(result.ids == [quick.id, slow.id], "\(query)")
        }
        #expect(search("best mile", in: [slow]).appliedIntent.effortMeters == 1_609.344)
        #expect(search("half marathon PR", in: [slow]).appliedIntent.effortMeters == 21_097.5)
    }

    // MARK: Effort and similar routes

    @Test func hardestAndEasiestCompareWithTheRunnersUsual() {
        let hard = record(minutes: 22, heartRate: 175)
        let usual = record(minutes: 28, heartRate: 150)
        let easy = record(minutes: 35, heartRate: 130)
        #expect(search("hardest runs", in: [usual, easy, hard]).ids.first == hard.id)
        #expect(search("easiest run", in: [usual, hard, easy]).ids.first == easy.id)
        #expect(search("hardest runs", in: [usual]).appliedIntent.filters.allSatisfy { if case .unsupported = $0 { false } else { true } })
    }

    @Test func similarRunsShareMostOfTheRoute() {
        let lats = stride(from: 45.50, to: 45.53, by: 0.0005).map { $0 }
        let route = WorkoutSearchSimilarity.cells(latitudes: lats, longitudes: lats.map { _ in -122.65 })
        let elsewhere = WorkoutSearchSimilarity.cells(latitudes: lats, longitudes: lats.map { _ in -122.75 })
        let latest = record(km: 5, at: date(hour: 7), cells: route)
        let again = record(km: 5.1, at: date(day: 20, hour: 7), cells: route)
        let other = record(km: 5, at: date(day: 18, hour: 7), cells: elsewhere)
        let result = search("runs like my last one", in: [latest, again, other])
        #expect(result.ids == [again.id])
        #expect(!result.closeIDs.contains(latest.id))
        #expect(WorkoutSearchEngine.search(WorkoutSearchIntent(filters: [.similar(again.id, "Like this run")]),
                                           in: [latest, again, other]).ids == [latest.id])
    }

    // MARK: Suggestions and recent searches

    @Test func suggestionsComeFromTheHistoryAndUnit() {
        let runs = (0..<4).map { record("Boise", state: "ID", km: 8, at: date(day: 20 - $0, hour: 7), efforts: [5_000: 1_500]) }
        let miles = WorkoutSearchSuggestions.phrases(for: runs, unit: .miles, now: date(hour: 20))
        #expect(miles.contains("Runs in Boise"))
        #expect(miles.contains("Fastest 5K"))
        #expect(miles.contains("Morning runs"))
        #expect(miles.contains("Runs over 4 miles"))
        #expect(WorkoutSearchSuggestions.phrases(for: runs, unit: .kilometers).contains("Runs over 7 km"))
        // Every suggestion finds something in the history it came from.
        for phrase in miles { #expect(!search(phrase, in: runs, now: date(hour: 20)).ids.isEmpty, "\(phrase)") }
    }

    @Test func recentSearchesKeepTheNewestFiveOnce() throws {
        let defaults = try #require(UserDefaults(suiteName: "recents-\(UUID())"))
        for query in ["a", "b", "c", "d", "e", "f", "C"] { WorkoutSearchRecents.add(query, to: defaults) }
        #expect(WorkoutSearchRecents.load(defaults) == ["C", "f", "e", "d", "b"])
        #expect(!SettingsSync.keys.contains(WorkoutSearchRecents.storageKey))
        WorkoutSearchRecents.clear(defaults)
        #expect(WorkoutSearchRecents.load(defaults).isEmpty)
    }

    // MARK: Time zone

    @Test func aRunKeepsItsTimeZoneThroughTheWatch() throws {
        let run = Run(startDate: date(hour: 7))
        run.timeZoneIdentifierValue = "America/New_York"
        run.finish(at: date(hour: 8))
        let record = try #require(WatchRunRecord.decode(try #require(WatchRunRecord(run)?.encoded())))
        #expect(record.timeZone == "America/New_York")
        let iPhone = WindRunSchema.makeContainer(inMemory: true)
        let copy = try #require(try record.save(into: iPhone.mainContext))
        #expect(copy.timeZone.identifier == "America/New_York")
        #expect(HealthWorkout(copy)?.timeZone?.identifier == "America/New_York")
        // A new run keeps the zone it started in.
        #expect(Run().timeZoneIdentifierValue == TimeZone.current.identifier)
    }

    @Test func startTimesShowTheirOwnZoneWhenItIsNotThisOne() {
        let start = date(hour: 7, zone: eastern)
        #expect(RunFormat.startTime(start, in: pacific, here: pacific).hasPrefix("4:00"))
        #expect(!RunFormat.startTime(start, in: pacific, here: pacific).contains("PST"))
        let away = RunFormat.startTime(start, in: eastern, here: pacific)
        #expect(away.hasPrefix("7:00"))
        #expect(away.contains("EST") || away.contains("GMT-5"))
        #expect(RunFormat.startTime(start, in: nil, here: pacific).hasPrefix("4:00"))
    }
}
