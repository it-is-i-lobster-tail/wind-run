import Foundation
import Testing
@testable import WindRun

@MainActor
struct WorkoutToolSearchTests {
    private func request(_ text: String) -> WorkoutToolRequest {
        let row = WorkoutSearchRecord(id: UUID(), date: .now, sport: "running", type: "free", title: "Mesa",
                                      notes: "private note", distance: 6000, duration: 1800, place: nil)
        return WorkoutToolRequest(query: text, records: [row], now: .now, calendar: .current)
    }

    @Test func emptyToolResponseCannotBeBroadenedByRetry() async throws {
        let call = request("steep climbs in Colorado")
        let tool = SearchWorkoutsTool(request: call)
        let response = try await tool.call(arguments: .init(slopes: [.init(direction: .uphill, source: "steep climbs")], filters: []))
        #expect(response == "Search complete. Match count: 0.")
        let intent = try #require(call.accepted)
        #expect(intent.filters.contains(.place("Colorado")))
        #expect(intent.filters.contains(.terrain(.uphill)))
        #expect(try await tool.call(arguments: .init(slopes: [], filters: [])) == response)
        #expect(call.accepted == intent)
    }

    @Test func wrongFieldAndUnsupportedRequirementsKeepRulesFallback() {
        let query = "steep climbs in Colorado"
        for field in [SearchInterpretationField.sport, .unsupported] {
            let call = request(query)
            let invalid = SearchInterpretationClause(field: field, source: "in Colorado", value: "running")
            _ = call.execute(.init(slopes: [], filters: [invalid]))
            #expect(call.accepted == nil)
        }
    }

    @Test func rejectsInventedSlopeAndPreservesUnknownWords() {
        let opposite = request("show me steep ascents")
        _ = opposite.execute(.init(slopes: [.init(direction: .downhill, source: "steep ascents")], filters: []))
        #expect(opposite.accepted == nil)
        let literal = request("copper ascents")
        _ = literal.execute(.init(slopes: [.init(direction: .uphill, source: "ascents")], filters: []))
        #expect(literal.accepted?.terms == ["copper"])
        let invalid = request("copper ascents")
        _ = invalid.execute(.init(slopes: [.init(direction: .uphill, source: "copper ascents")], filters: []))
        #expect(invalid.accepted == nil)
    }
}
