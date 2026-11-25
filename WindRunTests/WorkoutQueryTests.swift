import Foundation
import SwiftData
import Testing
@testable import WindRun

@MainActor
struct WorkoutQueryTests {
    @Test func combinesDatesTypesPlacesAndMeasuredEffort() throws {
        let store = WindRunStore(inMemory: true)
        let context = store.container.mainContext
        let day = Calendar.current.startOfDay(for: .now)
        func record(_ daysAgo: Int, _ meters: Double, _ seconds: Double) -> Run {
            let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: day)!
            let run = Run(startDate: start)
            context.insert(run)
            run.distanceMetersValue = meters
            run.finish(at: start.addingTimeInterval(seconds))
            return run
        }
        let quick = record(1, 3000, 750)
        let long = record(1, 8000, 2600)
        let ride = record(0, 9000, 1400)
        ride.workoutTypeValue = "cycling"
        let runs = [ride, long, quick]
        let places = [quick.runIDValue: "Golden Gate Park", long.runIDValue: "Golden Gate Park"]
        func ids(_ text: String) -> [UUID] {
            WorkoutQuery(text).results(runs, places: places).map(\.runIDValue)
        }
        #expect(ids("fast pace runs in Golden Gate Park yesterday") == [quick.runIDValue, long.runIDValue])
        #expect(ids("long distance runs") == [long.runIDValue, quick.runIDValue])
        #expect(ids("bike rides today") == [ride.runIDValue])
        #expect(ids("intervals in Boston").isEmpty)
        let through = [ride.runIDValue: "Golden Gate Park"]
        #expect(WorkoutQuery("through Golden Gate Park").results(runs, places: places, routePlaces: through).map(\.runIDValue) == [ride.runIDValue])
        #expect(WorkoutQuery("from Golden Gate Park").results(runs, places: places, routePlaces: through).count == 2)
    }
}
