import Foundation
import Testing
@testable import WindRun

/// Ranked, forgiving search: near misses show as close matches, typos and synonyms still find workouts,
/// and the best fit comes first.
@MainActor
struct WorkoutSearchRankingTests {
    private let day: TimeInterval = 86_400

    private func record(_ meters: Double, seconds: Double = 1_800, daysAgo: Double = 1, type: String = "free",
                        title: String = "", notes: String = "", city: String? = nil, state: String = "OR",
                        terrain: Set<WorkoutSearchTerrain>? = []) -> WorkoutSearchRecord {
        WorkoutSearchRecord(id: UUID(), date: Date(timeIntervalSince1970: 1_800_000_000 - daysAgo * day), sport: "running",
                            type: type, title: title, notes: notes, distance: meters, duration: seconds,
                            place: city.map { WorkoutSearchPlace(address: "\($0), \(state)", city: $0, state: state, country: "US") },
                            terrain: terrain)
    }

    private func search(_ query: String, in records: [WorkoutSearchRecord]) -> WorkoutSearchResult {
        WorkoutSearchEngine.search(WorkoutSearchEngine.parse(query, now: Date(timeIntervalSince1970: 1_800_000_000)),
                                   in: records)
    }

    @Test func aNearMissIsACloseMatchNotAnEmptyList() {
        let short = record(4_700)
        let result = search("runs over 5 km", in: [short])
        #expect(result.ids.isEmpty)
        #expect(result.closeIDs == [short.id])
        #expect(result.misses[short.id]?.first?.kind == .under)
        // Far outside the fade, it isn't shown at all.
        #expect(search("runs over 5 km", in: [record(2_000)]).closeIDs.isEmpty)
    }

    @Test func meetingEveryPartComesBeforeANearMiss() {
        let fits = record(8_200, city: "Portland")
        let short = record(7_700, city: "Portland")
        let elsewhere = record(8_400, city: "Bend")
        let result = search("runs over 8 km in Portland", in: [fits, short, elsewhere])
        #expect(result.ids == [fits.id])
        #expect(result.closeIDs == [short.id])
    }

    @Test func exactlyAndDatesStayHard() {
        let near = record(5_050)
        #expect(search("exactly 5 km", in: [near]).closeIDs.isEmpty)
        let old = record(5_000, daysAgo: 60)
        let lastWeek = search("5k last week", in: [old])
        #expect(lastWeek.ids.isEmpty && lastWeek.closeIDs.isEmpty)
    }

    @Test func typosStillFindTheWorkout() {
        let portland = record(6_000, city: "Portland")
        let bend = record(6_000, city: "Bend")
        let bare = search("Portand", in: [portland, bend])
        #expect(bare.ids == [portland.id])
        #expect(bare.looseReadings["Portland"] == "Portland (from portand)")
        let phrased = search("runs in Portand", in: [portland, bend])
        #expect(phrased.ids == [portland.id])
        #expect(phrased.looseReadings["Portand"] == "Portland (from Portand)")
        // Short words must match exactly, so "5k" never becomes "6k".
        #expect(WorkoutSearchVocabulary.allowedSlips("6k") == 0)
        #expect(WorkoutSearchVocabulary.slips("portand", "portland", limit: 1) == 1)
        #expect(WorkoutSearchVocabulary.slips("rvier", "river", limit: 1) == 1)
    }

    @Test func anUnknownWordLowersTheScoreInsteadOfEmptyingIt() {
        let tempo = record(8_000, title: "Tempo Tuesday")
        let easy = record(5_000, title: "Easy loop")
        // A word the spell checker has no usable fix for, so it stays unknown.
        let result = search("tempo qxvbz", in: [tempo, easy])
        #expect(result.ids == [tempo.id])
        #expect(result.notUnderstood == ["qxvbz"])
        // Only words nothing has: everything that passes shows as close matches under the chip.
        let unknown = search("zzyzx", in: [tempo, easy])
        #expect(unknown.ids.isEmpty)
        #expect(Set(unknown.closeIDs) == [tempo.id, easy.id])
    }

    @Test func endingsAndSynonymsShareOneTable() {
        #expect(WorkoutSearchVocabulary.stem("rides") == WorkoutSearchVocabulary.stem("riding"))
        #expect(WorkoutSearchVocabulary.stem("ride") == WorkoutSearchVocabulary.stem("rides"))
        #expect(WorkoutSearchVocabulary.stem("hills") == WorkoutSearchVocabulary.stem("hilly"))
        let foggy = record(5_000, notes: "Easy recovery jog by the river")
        let tempo = record(5_000, notes: "Hard tempo")
        // "easy" is the word itself; "gentle" means the same, so it is a close match.
        #expect(search("easy", in: [foggy, tempo]).ids == [foggy.id])
        let gentle = search("gentle", in: [foggy, tempo])
        #expect(gentle.ids.isEmpty && gentle.closeIDs == [foggy.id])
        #expect(WorkoutSearchEngine.parse("hilly runs").filters.contains(.terrain(.hills)))
    }

    @Test func bestFitComesFirstAndDateBreaksTies() {
        let newer = record(6_000, daysAgo: 1, title: "River run")
        let older = record(6_000, daysAgo: 5, title: "River run")
        let typo = record(6_000, daysAgo: 0, title: "Rvier edge")
        let result = search("river run", in: [older, typo, newer])
        #expect(result.ids.prefix(2) == [newer.id, older.id])
    }

    @Test func superlativesStillRankByValueWithinTheMatches() {
        let long = record(20_000, city: "Portland"), short = record(5_000, city: "Portland")
        #expect(search("longest run in Portland", in: [short, long]).ids == [long.id, short.id])
    }

    @Test func closeMatchesAreCapped() {
        let records = (0..<40).map { record(4_800 - Double($0), daysAgo: Double($0)) }
        #expect(search("runs over 5 km", in: records).closeIDs.count == WorkoutSearchScoring.closeLimit)
    }

    @Test func paceIsSearchableAndFadesOut() {
        let quick = record(8_047, seconds: 2_280) // 7:36 per mile
        let close = record(8_047, seconds: 2_430) // 8:06 per mile
        let slow = record(8_047, seconds: 2_900)  // 9:40 per mile
        let result = search("runs under 8 min/mi", in: [quick, close, slow])
        #expect(result.ids == [quick.id])
        #expect(result.closeIDs == [close.id])
        #expect(WorkoutSearchEngine.parse("pace faster than 5:30 per km").filters == [.pace(.less, 330, "pace faster than 5:30 per km")])
        #expect(WorkoutSearchEngine.isPerMile("under 8 min/mi"))
        #expect(!WorkoutSearchEngine.isPerMile("under 5 min/km"))
    }

    @Test func stateCodesThatAreWordsNeedAReason() {
        let maine = record(5_000, notes: "Me and the dog", city: "Bangor", state: "ME")
        let oregon = record(5_000, city: "Portland", state: "OR")
        // The whole query, or after "in": a place.
        #expect(WorkoutSearchEngine.parse("ME").filters == [.place("ME")])
        #expect(WorkoutSearchEngine.parse("or").filters == [.place("OR")])
        #expect(search("runs in ME", in: [maine, oregon]).ids == [maine.id])
        // After a city.
        #expect(WorkoutSearchEngine.parse("runs in Portland OR").filters.contains(.place("Portland, OR")))
        // In capitals elsewhere: a place only when a workout started there.
        #expect(search("OR trail runs", in: [oregon]).appliedIntent.filters.contains(.place("OR")))
        #expect(!search("OK trail runs", in: [oregon]).appliedIntent.filters.contains(.place("OK")))
        // Otherwise it is the English word.
        #expect(WorkoutSearchEngine.parse("runs with me and Sam").filters.allSatisfy { if case .place = $0 { false } else { true } })
    }

    @Test func flatAndDescentReadAsTerrain() {
        let flat = record(5_000, terrain: [])
        let hilly = record(5_000, terrain: [.uphill])
        #expect(search("flat runs", in: [flat, hilly]).ids == [flat.id])
        #expect(WorkoutSearchEngine.parse("descent practice").filters.contains(.terrain(.downhill)))
    }

    @Test func dayOfMonthAndSoFarReadAsDates() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let intent = WorkoutSearchEngine.parse("On 2025-03-02, find runs shorter than 8 kilometers so far this year.",
                                               now: Date(timeIntervalSince1970: 1_741_000_000), calendar: calendar)
        #expect(intent.terms.isEmpty)
        let cutoff = intent.filters.compactMap { if case .date(let span, _) = $0 { span } else { nil } }
        #expect(cutoff.contains { $0.end == calendar.date(from: DateComponents(year: 2025, month: 3, day: 3)) })
        let monthly = WorkoutSearchEngine.parse("runs on day 7 of a month", calendar: calendar)
        #expect(monthly.filters.contains { if case .dayOfMonth(7, _, _) = $0 { true } else { false } })
    }

    @Test func requestWordsAreNotSearchTerms() {
        #expect(WorkoutSearchEngine.parse("Pull up my bridge training for my log at week 4").terms == ["bridge"])
        #expect(WorkoutSearchEngine.parse("Which run holds my distance record?").sort == .longest)
        #expect(WorkoutSearchEngine.parse("which outing has the greatest mileage so far").sort == .longest)
        #expect(WorkoutSearchEngine.parse("most recent ride").sort == .newest)
        #expect(WorkoutSearchEngine.parse("title matches for lake").filters == [.title("lake")])
        #expect(WorkoutSearchEngine.parse("runs with distance of 6 km or greater").filters
                    .contains(.distance(.atLeast, 6_000, "6 km or greater")))
    }

    @Test func thousandWorkoutsScoreQuickly() {
        let records = (0..<1_000).map { index in
            record(3_000 + Double(index * 13 % 12_000), daysAgo: Double(index), title: index % 7 == 0 ? "Tempo" : "Easy",
                   notes: "Loop by the river with the dog number \(index % 31)", city: ["Portland", "Bend", "Eugene"][index % 3])
        }
        let intents = ["tempo rnu", "runs over 5 km in Portand", "river", "hilly runs last month"]
            .map { WorkoutSearchEngine.parse($0) }
        for intent in intents { _ = WorkoutSearchEngine.search(intent, in: records) }
        let clock = ContinuousClock()
        var slowest = Duration.zero
        for intent in intents {
            let elapsed = clock.measure { _ = WorkoutSearchEngine.search(intent, in: records) }
            slowest = max(slowest, elapsed)
        }
        // The target is 5 ms on an iPhone 15. Simulators and CI machines vary, so allow headroom here.
        #expect(slowest < .milliseconds(50))
    }

    @Test func aMonthWithNoYearIsTheMostRecentOne() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2025, month: 2, day: 14, hour: 12))!
        func span(_ query: String) -> DateInterval? {
            WorkoutSearchEngine.parse(query, now: now, calendar: calendar).filters
                .compactMap { if case .date(let span, _) = $0 { span } else { nil } }.first
        }
        func day(_ year: Int, _ month: Int, _ day: Int = 1) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day))!
        }
        // October hasn't started this year, so it is last October.
        #expect(span("October runs")?.start == day(2024, 10))
        // The month we are in has started, so it is this one.
        #expect(span("runs in February")?.start == day(2025, 2))
        #expect(span("January runs")?.start == day(2025, 1))
        // A typed year always wins, even one still ahead.
        #expect(span("October 2025 runs")?.start == day(2025, 10))
        #expect(span("runs in oct 2023")?.start == day(2023, 10))
        // A day with no year works the same way.
        #expect(span("runs on Dec 25")?.start == day(2024, 12, 25))
        #expect(span("runs on Feb 14")?.start == day(2025, 2, 14))
    }

    @Test func anUnknownWordCanReadAsAKnownOneWithTheSameMeaning() {
        let saved = WorkoutSearchMeanings.vector
        defer { WorkoutSearchMeanings.vector = saved }
        let table: [String: [Double]] = ["downpour": [1, 0.05, 0], "rain": [1, 0, 0], "river": [0, 1, 0],
                                         "sprint": [0, 0, 1], "loop": [0.2, 0.9, 0.1]]
        WorkoutSearchMeanings.vector = { table[$0] }
        let wet = record(5_000, notes: "Heavy rain the whole loop")
        let dry = record(5_000, notes: "Loop by the river")
        let result = search("downpour", in: [wet, dry])
        // Read as "rain": a close match under a chip, never a best match, and never every workout.
        #expect(result.ids.isEmpty)
        #expect(result.closeIDs == [wet.id])
        #expect(result.meanings == ["downpour": "rain"])
        #expect(result.notUnderstood.isEmpty)
        #expect(result.misses[wet.id]?.contains { $0.kind == .loose("rain") } == true)
        // Nothing close enough in meaning: still not understood.
        let far = search("sprint", in: [wet, dry])
        #expect(far.meanings.isEmpty && far.notUnderstood == ["sprint"])
        // Numbers and short words are never read this way.
        #expect(WorkoutSearchMeanings.nearest("5k", in: ["rain"]) == nil)
    }

    @Test(.enabled(if: WorkoutSearchMeanings.systemVector("rain") != nil, "Needs the on-device English word embedding"))
    func theDeviceEmbeddingJoinsOnlyNearIdenticalMeanings() {
        #expect(WorkoutSearchMeanings.nearest("downpour", in: ["rain", "river", "loop"]) == "rain")
        // Neighbors and opposites sit close in an embedding. They must stay apart.
        #expect(WorkoutSearchMeanings.nearest("ankle", in: ["knee"]) == nil)
        #expect(WorkoutSearchMeanings.nearest("cat", in: ["dog"]) == nil)
        #expect(WorkoutSearchMeanings.nearest("evening", in: ["morning"]) == nil)
        #expect(WorkoutSearchMeanings.nearest("lake", in: ["river"]) == nil)
    }
}
