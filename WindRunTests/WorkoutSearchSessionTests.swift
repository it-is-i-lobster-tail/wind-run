import Foundation
import Testing
@testable import WindRun

@MainActor
struct WorkoutSearchSessionTests {
    @Test func unavailableAndFailedInterpretationsKeepImmediateResults() async throws {
        for status in ["unavailable", "failed", "unsupported"] {
            let search = WorkoutSearchSession()
            search.edit("rides over 20 miles")
            let filters = search.intent.filters
            search.submit()
            let submission = try #require(search.pending)
            await search.interpret(submission) { _ in
                WorkoutInterpretation(intent: WorkoutSearchEngine.parse("hikes"), status: status, usedModel: false)
            }
            #expect(search.intent.filters == filters)
            #expect(search.notice != nil)
            #expect(search.pending == nil)
        }
    }

    @Test func editingEvenBackToSameTextInvalidatesOldSubmission() async throws {
        let search = WorkoutSearchSession()
        search.edit("rides")
        search.submit()
        let oldSubmission = try #require(search.pending)
        await search.interpret(oldSubmission) { _ in
            search.edit("hikes")
            search.edit("rides")
            search.submit()
            return WorkoutInterpretation(intent: WorkoutSearchEngine.parse("hikes"), status: "model", usedModel: true)
        }
        #expect(search.intent.filters == WorkoutSearchEngine.parse("rides").filters)
        #expect(search.pending != nil)
        #expect(search.pending != oldSubmission)
    }

    @Test func approvedInterpretationCanBeEdited() async throws {
        let search = WorkoutSearchSession()
        search.edit("which ride took me the furthest")
        search.submit()
        let submission = try #require(search.pending)
        let interpreted = WorkoutSearchEngine.parse("longest rides")
        await search.interpret(submission) { _ in
            WorkoutInterpretation(intent: interpreted, status: "model", usedModel: true)
        }
        #expect(search.intent.sort == .longest)
        let sport = try #require(search.intent.filters.first)
        search.remove(sport)
        search.resetSorting()
        #expect(search.intent.filters.isEmpty)
        #expect(search.intent.sort == .newest)
    }
}
