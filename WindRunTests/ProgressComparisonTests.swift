#if DEBUG
import Foundation
import SwiftData
import Testing
@testable import WindRun

@MainActor
struct ProgressComparisonTests {
    @Test func comparesRepeatedGoalsAndLeavesFreeRunsIndividual() throws {
        let store = WindRunStore(inMemory: true)
        let context = store.container.mainContext
        ProgressDemo.populate(context)
        let runs = try context.fetch(FetchDescriptor<Run>(sortBy: [SortDescriptor(\.startDateValue, order: .reverse)]))
        let groups = Dictionary(grouping: runs, by: { ProgressGroup($0) })
        #expect(groups.count == 4)
        #expect(groups[.free]?.count == 8)
        for (key, attempts) in groups {
            let group = try #require(key)
            if group == .free {
                #expect(attempts.allSatisfy { group.rank($0) == nil })
                continue
            }
            let ranks = try attempts.map { run in try #require(group.rank(run)) }
            #expect(ranks.count == 4)
            #expect(ranks.min() == ranks[2])
            let series = ComparisonSeries(try #require(attempts.first))
            #expect(ComparisonMetric.allCases.allSatisfy { (series.lines[$0]?.count ?? 0) > 1 })
            if group.type == .intervals {
                #expect(series.reps[.pace]?.map(\.id) == [1, 2, 3, 4])
                #expect(ranks == [480, 480, 464, 492])
            }
        }
    }
}
#endif
