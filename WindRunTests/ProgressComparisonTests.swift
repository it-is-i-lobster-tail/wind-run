#if DEBUG
import Foundation
import SwiftData
import Testing
@testable import WindRun

@MainActor
struct ProgressComparisonTests {
    @Test func distributionCountsTiesOnceAndIncludesTheThreshold() {
        let curve = EmpiricalDistribution([12, 10, 10, .nan, 20])
        #expect(curve.count == 4)
        #expect(curve.steps.map(\.value) == [10, 12, 20])
        #expect(curve.steps.map(\.count) == [2, 3, 4])
        #expect(curve.count(atOrBelow: 9) == 0)
        #expect(curve.count(atOrBelow: 10) == 2)
        #expect(curve.count(atOrBelow: 11) == 2)
        #expect(curve.count(atOrBelow: 20) == 4)
        #expect(EmpiricalDistribution([]).steps.isEmpty)
        #expect(EmpiricalDistribution([3, 3]).steps.count == 1)
    }

    @Test func paceThresholdsIncreaseFromFasterToSlower() {
        for unit in DistanceUnit.allCases {
            let fast = ComparisonMetric.pace.measuredValue(270, unit: unit)
            let slow = ComparisonMetric.pace.measuredValue(330, unit: unit)
            #expect(fast > 0 && slow > fast)
            #expect(EmpiricalDistribution([slow, fast]).count(atOrBelow: fast) == 1)
        }
    }

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
