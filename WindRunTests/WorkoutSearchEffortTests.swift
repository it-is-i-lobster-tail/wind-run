import Foundation
import SwiftData
import Testing
@testable import WindRun

/// Everyday searches: race distances, rough amounts, and the effort each workout recorded.
@MainActor
struct WorkoutSearchEffortTests {
    private func record(_ meters: Double, seconds: Double = 1800, climb: Double? = nil, heartRate: Double? = nil,
                        calories: Double? = nil, title: String = "") -> WorkoutSearchRecord {
        WorkoutSearchRecord(id: UUID(), date: Date(timeIntervalSince1970: 0), sport: "running", type: "free",
                            title: title, notes: "", distance: meters, duration: seconds, place: nil, terrain: [],
                            climb: climb, heartRate: heartRate, calories: calories)
    }

    private func found(_ query: String, in records: [WorkoutSearchRecord], feet: Bool = false) -> [UUID] {
        WorkoutSearchEngine.search(WorkoutSearchEngine.parse(query, climbInFeet: feet), in: records).ids
    }

    @Test func bareDistancesAndRaceNamesAllowForGPS() {
        let fiveK = record(5_120), sixK = record(6_000), tenK = record(9_960), half = record(21_340), full = record(42_600)
        let all = [fiveK, sixK, tenK, half, full]
        #expect(found("5k", in: all) == [fiveK.id])
        #expect(found("5 km runs", in: all) == [fiveK.id])
        #expect(found("10K", in: all) == [tenK.id])
        #expect(found("half marathon", in: all) == [half.id])
        #expect(found("marathons", in: all) == [full.id])
        #expect(found("1 hour", in: [record(5_000, seconds: 3_700), record(5_000, seconds: 5_400)]).count == 1)
        // Saying "exactly" keeps the exact amount.
        let exact = record(5_000)
        #expect(found("exactly 5 km", in: [exact, fiveK]) == [exact.id])
    }

    @Test func heartRateCaloriesAndClimbAreSearchable() {
        let easy = record(8_000, climb: 120, heartRate: 148, calories: 420)
        let hard = record(8_000, climb: 400, heartRate: 166, calories: 610)
        let bare = record(8_000)
        let all = [easy, hard, bare]
        #expect(found("heart rate over 160", in: all) == [hard.id])
        #expect(found("runs over 160 bpm", in: all) == [hard.id])
        #expect(Set(found("runs with heart rate", in: all)) == [easy.id, hard.id])
        #expect(found("more than 500 calories", in: all) == [hard.id])
        #expect(found("climb over 300 m", in: all) == [hard.id])
        #expect(found("over 1000 ft of climbing", in: all) == [hard.id])
        #expect(found("climb over 500", in: all, feet: true) == [hard.id])
        #expect(found("most climb", in: all) == [hard.id, easy.id])
        #expect(found("hilliest runs", in: all) == [hard.id, easy.id])
    }

    @Test func aDistanceAfterAClimbWordStaysADistance() {
        let intent = WorkoutSearchEngine.parse("climbing over 5 km")
        #expect(intent.filters.contains(.distance(.greater, 5_000, "over 5 km")))
        #expect(intent.sort == .mostClimb)
        #expect(intent.terms.isEmpty)
    }

    @Test func superlativesRank() {
        #expect(WorkoutSearchEngine.parse("fastest runs").sort.ranks)
        #expect(WorkoutSearchEngine.parse("longest rides").sort.ranks)
        #expect(!WorkoutSearchEngine.parse("runs last week").sort.ranks)
    }

    @Test func findsUSStartsByStateNameOrPostalCode() {
        let address = "1 Apple Park Way, Cupertino, CA 95014"
        for city in ["Cupertino, CA", nil] {
            let terms = WorkoutSearchLocations.searchAddress(address, city: city, region: "US")
            var row = record(5_000)
            row.place = WorkoutSearchPlace(address: terms, city: "Cupertino", state: "CA", country: "US")
            for query in ["CA", "California", "Cupertino California"] {
                #expect(found(query, in: [row]) == [row.id], "\(query)")
            }
        }
        #expect(WorkoutSearchLocations.searchAddress("Cagliari, CA", city: "Cagliari, CA", region: "IT") == "Cagliari, CA")
    }

    @Test func combinesDatesTypesPlacesAndPace() throws {
        let store = WindRunStore(inMemory: true)
        let context = store.container.mainContext
        let day = Calendar.current.startOfDay(for: .now)
        func run(_ daysAgo: Int, _ meters: Double, _ seconds: Double) -> Run {
            let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: day)!
            let run = Run(startDate: start)
            context.insert(run)
            run.distanceMetersValue = meters
            run.finish(at: start.addingTimeInterval(seconds))
            return run
        }
        let quick = run(1, 3000, 750)
        let long = run(1, 8000, 2600)
        let ride = run(0, 9000, 1400)
        ride.workoutTypeValue = "cycling"
        let park = WorkoutSearchPlace(address: "Golden Gate Park", city: "San Francisco", state: "CA", country: "US")
        let records = [ride, long, quick].map { WorkoutSearchRecord(run: $0, place: $0 === ride ? nil : park) }
        #expect(found("fast pace runs in Golden Gate Park yesterday", in: records) == [quick.runIDValue, long.runIDValue])
        #expect(found("long distance runs", in: records) == [long.runIDValue, quick.runIDValue])
        #expect(found("bike rides today", in: records) == [ride.runIDValue])
        #expect(found("intervals in Boston", in: records).isEmpty)
    }

    @Test func indexWorksOutEachRunOnceAndForgetsDeletedOnes() async {
        let store = WindRunStore(inMemory: true)
        let context = store.container.mainContext
        let run = Run(startDate: .now)
        context.insert(run)
        run.distanceMetersValue = 5_000
        run.activeCaloriesValue = 350
        run.finish(at: run.startDate.addingTimeInterval(1_500))
        let index = WorkoutSearchIndex(persists: false)
        await index.update(for: [run], pruning: true)
        await index.placesSettled()
        let first = index.facts[run.runID]
        #expect(first?.calories == 350)
        // No route, so there is no start to look up.
        #expect(first?.placeChecked == true)

        run.activeCaloriesValue = 400
        await index.update(for: [run])
        #expect(index.facts[run.runID]?.calories == 400)

        index.forget(run.runID)
        #expect(index.facts[run.runID] == nil)
        await index.update(for: [run])
        await index.update(for: [], pruning: true)
        #expect(index.facts.isEmpty)
    }
}
