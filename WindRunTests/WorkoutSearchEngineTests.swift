import Foundation
import Testing
@testable import WindRun

@MainActor
struct WorkoutSearchEngineTests {
    private let first = UUID(), second = UUID(), third = UUID()
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }
    private var now: Date {
        calendar.date(from: DateComponents(year: 2025, month: 3, day: 10, hour: 12))!
    }

    private var records: [WorkoutSearchRecord] {
        [
            WorkoutSearchRecord(id: first, date: now, sport: "running", type: "free", title: "Sunday",
                notes: "knee felt fine", distance: 5000, duration: 1500,
                place: .init(address: "Trail", city: "Long Beach", state: "CA", country: "US")),
            WorkoutSearchRecord(id: second, date: calendar.date(byAdding: .day, value: -1, to: now)!,
                sport: "running", type: "intervals", title: "10 × 400", notes: "California trip next",
                distance: 5500, duration: 1600,
                place: .init(address: "Park", city: "Portland", state: "OR", country: "US")),
            WorkoutSearchRecord(id: third, date: now, sport: "cycling", type: "free", title: "Steady",
                notes: "", distance: 40_000, duration: 5000,
                place: .init(address: "Waterfront", city: "Portland", state: "ME", country: "US"))
        ]
    }

    private func search(_ query: String) -> WorkoutSearchResult {
        let intent = WorkoutSearchEngine.parse(query, now: now, calendar: calendar)
        return WorkoutSearchEngine.search(intent, in: records)
    }

    @Test func novemberDistanceRangeAndStandaloneDay() {
        func workout(_ month: Int, _ day: Int, miles: Double) -> WorkoutSearchRecord {
            var row = records[0]
            row.id = UUID()
            row.date = calendar.date(from: DateComponents(year: 2025, month: month, day: day, hour: 12))!
            row.distance = miles * DistanceUnit.miles.meters
            return row
        }
        let lower = workout(11, 1, miles: 8), middle = workout(11, 8, miles: 10), upper = workout(11, 30, miles: 12)
        let short = workout(11, 8, miles: 7.99), long = workout(11, 8, miles: 12.01)
        let history = [lower, middle, upper, short, long, workout(10, 31, miles: 9), workout(12, 1, miles: 11)]
        func ids(_ text: String) -> Set<UUID> {
            let intent = WorkoutSearchEngine.parse(text, now: now, calendar: calendar)
            return Set(WorkoutSearchEngine.search(intent, in: history).ids)
        }
        #expect(ids("Nov 8-12 miles") == [lower.id, middle.id, upper.id])
        #expect(ids("November 8 – 12 mi") == [lower.id, middle.id, upper.id])
        #expect(ids("Nov 8") == [short.id, middle.id, long.id])
    }

    @Test func cutoffIncludesEarlierRunsAndHandlesExclusiveDay() {
        #expect(Set(search("runs as of 2025-03-10").ids) == [first, second])
        #expect(search("runs through 2025-03-09").ids == [second])
        #expect(search("runs before 2025-03-10").ids == [second])
        #expect(search("runs after 2025-03-09").ids == [first])
        #expect(search("runs since 2025-02-31").ids.isEmpty)
        #expect(search("runs from 2025-03-01 through 2025-03-09").ids == [second])
        #expect(search("runs through March 9").ids == [second])
        #expect(search("runs through the end of week 10").ids == [second])
    }

    @Test func fieldScopeAndCityDisambiguation() {
        #expect(search("California runs").ids == [first])
        #expect(search("runs where I mentioned California").ids == [second])
        #expect(search("runs where I mentioned my knee").ids == [first])
        #expect(search("rides over 20 miles that took less than two hours").ids == [third])
        #expect(search("runs in Long Beach").ids == [first])
        #expect(search("Portland").placeChoices == ["Portland, ME", "Portland, OR"])
        #expect(search("in Portland, ME").ids == [third])
        #expect(search("in Portland, ME but skip intervals").ids == [third])
    }

    @Test func appliedLocationAndInclusiveThresholds() {
        #expect(search("runs at or below 25 active minutes").ids == [first])
        #expect(Set(search("runs at or above 25 active minutes").ids) == [first, second])
        let state = search("runs in CA at exactly 25 minutes active")
        #expect(state.ids == [first])
        #expect(state.appliedIntent.filters.contains(.place("CA")))
        let city = search("Portland workouts under 2 active hours")
        #expect(city.placeChoices == ["Portland, ME", "Portland, OR"])
        #expect(city.appliedIntent.filters.contains(.place("Portland")))
        #expect(city.appliedIntent.terms.isEmpty)
    }

    @Test func separatesRequestLanguageFromLiteralFields() {
        #expect(search("Were there runs I tracked out of Long Beach today?").ids == [first])
        #expect(search("Was “Steady” the name of a ride?").ids == [third])
        #expect(search("Title: Sunday. Notes include: knee.").ids == [first])
        #expect(search("What workout has ‘Sunday’ as its title and ‘knee’ in its notes?").ids == [first])
        #expect(search("Did I write “California” about an interval workout?").ids == [second])
        // Neither the location nor the action verbs can fulfill this title/notes request.
        #expect(search("Title: California.").ids.isEmpty)
        #expect(search("Look for “recorded” in my notes").ids.isEmpty)
        #expect(search("Were there runs I recorded with otters?").ids.isEmpty)
    }

    @Test func conversationalFieldsKeepTheirLiteralAndRespectOtherFilters() {
        var sample = records
        sample[0].notes = "shelter in the pines"
        sample[0].title = "steady in June"
        sample[1].title = "shelter in the pines"
        sample[1].notes = "steady in June"
        func matching(_ query: String) -> [UUID] {
            WorkoutSearchEngine.search(WorkoutSearchEngine.parse(query, now: now, calendar: calendar), in: sample).ids
        }
        #expect(matching("Which runs mention shelter in the pines in March?") == [first, second])
        #expect(matching("Runs mentioning shelter in the pines in Oregon") == [second])
        #expect(matching("Search my notes for shelter in the pines, including runs through March 10") == [first])
        #expect(matching("March outings with steady in June in the title") == [first])
        #expect(matching("Which runs have shelter in the pines in their name?") == [second])
        #expect(matching("Outings mentioning “steady in June” in Portland, OR") == [second])
        #expect(matching("March runs matching shelter in the pines in title or notes in Oregon under 6 km") == [second])
        #expect(matching("Runs with shelter in the pines in notes or title in Colorado").isEmpty)
        #expect(matching("Runs that did not reach 5.5 km as of 2025-03-10") == [first])
        #expect(matching("Newest run in my log through 2025-03-09") == [second])
        #expect(matching("first outing whose notes say steady") == [second])
    }

    @Test func separatesDistanceComparatorsFromStartLocations() {
        #expect(Set(search("outings").ids) == [first, second, third])
        #expect(search("cycling outings").ids == [third])
        #expect(search("March outings that exceeded 5 km").ids == [third, second])
        #expect(search("March outings that did not exceed 5 km").ids == [first])
        #expect(search("Which runs starting in Long Beach were longer than 4 km?").ids == [first])
        #expect(search("Which runs starting in Long Beach were longer than 5 km?").ids.isEmpty)
    }

    @Test func workoutTypesLocationsAndCalendarScaffolding() {
        #expect(search("As at March 10, retrieve activities of type intervals").ids == [second])
        #expect(search("Which activities were logged as free?").ids.count == 2)
        #expect(search("Runs not of type intervals").ids == [first])
        #expect(search("Which runs originated in Long Beach?").ids == [first])
        #expect(search("Training logged near Long Beach").ids == [first])
        #expect(search("Which running activity dated 2025-03-09?").ids == [second])
        #expect(search("Interval workouts available by March 8").ids.isEmpty)
        #expect(search("Oregon runs completed by the end of March 9").ids == [second])
        #expect(search("Runs recorded no later than 2025-03-08").ids.isEmpty)
        #expect(search("Which runs in Long Beach lasted at least 25 minutes?").ids == [first])
        #expect(search("Runs covering a minimum of 5.5 kilometers").ids == [second])
        #expect(search("Runs covering 5 kilometers maximum").ids == [first])
        #expect(search("Runs mentioning “began in Oregon”").ids.isEmpty)
    }

    @Test func handlesQuantitiesExclusionsAndChronologyInConversation() {
        #expect(search("Look through my runs, leaving out the intervals").ids == [first])
        #expect(search("Which run had the best average pace past 5 km?").ids == [second])
        #expect(search("Are there runs in CA taking 25 minutes of moving time or less?").ids == [first])
        #expect(search("When did I first record a run?").ids.first == second)
        #expect(search("Runs between 25 and 26 moving minutes").ids == [first])
        #expect(search("Runs from 5 km to 5.5 km").ids == [first, second])
        #expect(search("Runs between 2 hours and 6 km").ids.isEmpty)
    }

    @Test func qualifiedPlaceReferencesAndStrictBounds() {
        let resolved = search("I meant Portland, Maine; find rides there today")
        #expect(resolved.ids == [third])
        #expect(resolved.appliedIntent.filters.contains(.place("Portland, Maine")))
        #expect(resolved.appliedIntent.terms.isEmpty)
        #expect(search("Portland, OR; list rides there").ids.isEmpty)
        let beyond = search("Have I ever recorded runs beyond 5 km?")
        #expect(beyond.ids == [second])
        #expect(beyond.appliedIntent.filters.contains(.distance(.greater, 5000, "beyond 5 km")))
        #expect(beyond.appliedIntent.terms.isEmpty)
        #expect(search("Pull up any intervals on record in Oregon").ids == [second])
        #expect(search("Any logged rides out of Maine?").ids == [third])
        let earliest = search("Which was the first run in my workout history?")
        #expect(earliest.ids == [second, first])
        #expect(earliest.appliedIntent.filters == [.sport("running")])
    }

    @Test func generatedClausesRequireGroundingAndPreserveExplicitBounds() {
        let query = "pedaled outings over 20 miles"
        let rules = WorkoutSearchEngine.parse(query, now: now, calendar: calendar)
        let generated = SearchInterpretationClause(field: .sport, source: "pedaled outings", value: "cycling")
        let interpreted = try? WorkoutIntentInterpreter.validated([generated], query: query, rules: rules, now: now, calendar: calendar)
        #expect(interpreted?.filters.contains(.sport("cycling")) == true)
        #expect(interpreted?.filters.contains(.distance(.greater, 20 * DistanceUnit.miles.meters, "over 20 miles")) == true)
        #expect(interpreted?.terms == [])
        let invented = SearchInterpretationClause(field: .place, source: "pedaled outings", value: "Portland")
        #expect((try? WorkoutIntentInterpreter.validated([invented], query: query, rules: rules, now: now, calendar: calendar)) == nil)
        #expect((try? WorkoutIntentInterpreter.validated([generated, generated], query: query, rules: rules, now: now, calendar: calendar)) == nil)
    }

    @Test func dateAndNumericEdges() {
        #expect(search("yesterday").ids == [second])
        #expect(search("2025-03-09").ids == [second])
        #expect(search("2025-02-31").ids.isEmpty)
        #expect(search("runs over 5 km").ids == [second])
        #expect(Set(search("runs at least 5 km").ids) == [first, second])
        #expect(search("runs at least 10 km under 5 km").ids.isEmpty)
        #expect(search("runs with heart rate over 140 bpm").ids.isEmpty)
    }
}
