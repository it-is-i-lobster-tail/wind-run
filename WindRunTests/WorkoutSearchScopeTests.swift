import Foundation
import SwiftData
import Testing
@testable import WindRun

@MainActor
struct WorkoutSearchScopeTests {
    private let city = WorkoutSearchPlace(address: "Summit Road", city: "Tacoma", state: "WA", country: "US")
    private let elsewhere = WorkoutSearchPlace(address: "Bay Road", city: "Salem", state: "OR", country: "US")

    @Test func terrainQueriesUseSustainedRecordedGrades() {
        let store = WindRunStore(inMemory: true)
        var records = [WorkoutSearchRecord]()
        var ids = [SyntheticSearchRoute: UUID]()
        for profile in SyntheticSearchRoute.allCases {
            let run = Run(startDate: Date(timeIntervalSince1970: 0))
            store.container.mainContext.insert(run)
            profile.record(on: run, meters: 1000, seconds: 330)
            run.notesValue = profile == .flat ? "hills" : ""
            run.finish(at: run.startDate.addingTimeInterval(330))
            records.append(WorkoutSearchRecord(run: run, place: city))
            ids[profile] = run.runIDValue
        }
        func found(_ query: String) -> Set<UUID> {
            Set(WorkoutSearchEngine.search(WorkoutSearchEngine.parse(query), in: records).ids)
        }
        #expect(found("hills") == Set([.climb, .descent, .outBack].compactMap { ids[$0] }))
        #expect(found("uphill runs in Tacoma") == Set([.climb, .outBack].compactMap { ids[$0] }))
        #expect(found("downhill") == Set([.descent, .outBack].compactMap { ids[$0] }))
        #expect(found("notes: hills") == Set([.flat].compactMap { ids[$0] }))
    }

    @Test func findingMoreWorkoutsPreservesPlaceTextAndBoundaryConstraints() {
        func record(_ meters: Double, _ start: WorkoutSearchPlace?, _ note: String) -> WorkoutSearchRecord {
            WorkoutSearchRecord(id: UUID(), date: Date(timeIntervalSince1970: 0), sport: "running", type: "free",
                                title: "Lunch loop", notes: note, distance: meters, duration: 1800, place: start)
        }
        let exact = record(5000, city, "Boardwalk")
        let over = record(5001, city, "Boardwalk")
        let differentNote = record(5001, city, "Gravel road")
        let wrongStart = record(5100, elsewhere, "Boardwalk near Tacoma yesterday")
        let missingStart = record(5200, nil, "Tacoma boardwalk")
        let history = [over, differentNote, exact, wrongStart, missingStart]

        func results(_ text: String) -> Set<UUID> {
            Set(WorkoutSearchEngine.search(WorkoutSearchEngine.parse(text), in: history).ids)
        }
        #expect(results("runs in Tacoma over 5 km") == [over.id, differentNote.id])
        #expect(results("runs in Tacoma at least 5 km") == [exact.id, over.id, differentNote.id])
        #expect(results("runs in Tacoma over 5 km with notes containing “boardwalk”") == [over.id])
        #expect(results("runs in Tacoma over 5 km with notes containing “beach”").isEmpty)
        #expect(results("runs lighthouse in Tacoma").isEmpty)
    }
}
