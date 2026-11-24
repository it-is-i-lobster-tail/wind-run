//
//  WatchRunHistoryTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

@MainActor
struct WatchRunHistoryTests {
    @Test func olderRunsStayVisibleUntilThePhoneConfirmsTheyWereSaved() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let runs = (0..<8).map { index in
            let start = now.addingTimeInterval(-Double(index) * 1_000)
            let run = Run(startDate: start)
            run.finish(at: start.addingTimeInterval(60))
            return run
        }
        let active = Run(startDate: now.addingTimeInterval(60))
        let oldestPending = runs[7].runID
        let defaults = try #require(UserDefaults(suiteName: "WatchRunHistoryTests.\(UUID().uuidString)"))

        let newestFirst = [active] + runs
        #expect(WatchRunHistory.visibleRuns(newestFirst, confirmed: []).map(\.runID) == runs.map(\.runID))
        for run in runs.dropLast() {
            WatchRunHistory.recordReceipt(for: run.runID, in: defaults)
        }

        let confirmed = WatchRunHistory.receipts(from: defaults.data(forKey: WatchRunHistory.receiptsKey))
        #expect(WatchRunHistory.visibleRuns(newestFirst, confirmed: confirmed).map(\.runID)
            == runs.prefix(5).map(\.runID) + [oldestPending])

        WatchRunHistory.recordReceipt(for: oldestPending, in: defaults)
        WatchRunHistory.recordReceipt(for: oldestPending, in: defaults)
        let allConfirmed = WatchRunHistory.receipts(from: defaults.data(forKey: WatchRunHistory.receiptsKey))
        #expect(allConfirmed.count == runs.count)
        #expect(WatchRunHistory.visibleRuns(newestFirst, confirmed: allConfirmed).map(\.runID) == runs.prefix(5).map(\.runID))
    }
}
