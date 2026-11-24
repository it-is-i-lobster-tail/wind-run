//
//  WatchRunHistory.swift
//  Wind Run
//

import Foundation

enum WatchRunHistory {
    static let receiptsKey = "watchSavedRunReceipts"
    static let recentLimit = 5

    static func receipts(from data: Data?) -> Set<UUID> {
        guard let data else { return [] }
        return (try? JSONDecoder().decode(Set<UUID>.self, from: data)) ?? []
    }

    /// Records a receipt before cleaning up the file staged for transfer.
    static func recordReceipt(for runID: UUID, in defaults: UserDefaults) {
        var confirmed = receipts(from: defaults.data(forKey: receiptsKey))
        guard confirmed.insert(runID).inserted, let data = try? JSONEncoder().encode(confirmed) else { return }
        defaults.set(data, forKey: receiptsKey)
    }

    /// The five newest finished runs and any older runs still waiting for the iPhone.
    static func visibleRuns(_ newestFirst: [Run], confirmed: Set<UUID>) -> [Run] {
        newestFirst.filter { $0.status == .complete }.enumerated().compactMap { index, run in
            index < recentLimit || !confirmed.contains(run.runID) ? run : nil
        }
    }
}
