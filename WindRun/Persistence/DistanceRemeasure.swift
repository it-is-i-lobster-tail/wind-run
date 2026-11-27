//
//  DistanceRemeasure.swift
//  Wind Run
//

import Foundation
import SwiftData

/// Measures again every finished run whose distance came from the fixes' reported speed ("speed-v1"),
/// which read 5 to 18% short on iPhone, with the smoothed GPS line (`DistanceEstimator`). Runs that came in
/// from a device still on an older version are caught the next time the app comes to the front.
///
/// One run at a time on the main context with a rest between, like `RouteMigration`, and never while a run is
/// being recorded. Runs that finished in the last hour wait, since their fixes may still be arriving.
@MainActor
enum DistanceRemeasure {
    static let pause: Duration = .milliseconds(100)
    static let saveEvery = 5

    private static var isRunning = false

    /// Measures runs again until none are left, the task is cancelled, or a run is being recorded. Returns
    /// how many it measured.
    @discardableResult
    static func remeasureOldRuns(in context: ModelContext, now: Date = .now, pause: Duration = Self.pause) async -> Int {
        guard !isRunning else { return 0 }
        isRunning = true
        defer { isRunning = false }
        let settled = now.addingTimeInterval(-RouteMigration.settlingTime)
        let speedMethod: String? = DistanceEstimator.speedMethod
        var descriptor = FetchDescriptor<Run>(
            predicate: #Predicate { $0.distanceMethodValue == speedMethod && $0.endDateValue != nil },
            sortBy: [SortDescriptor(\.startDateValue, order: .reverse)]
        )
        descriptor.includePendingChanges = false
        guard let ids = try? context.fetchIdentifiers(descriptor), !ids.isEmpty else { return 0 }
        let started = ContinuousClock.now
        var measured = 0
        var metersBefore = 0.0
        var metersAfter = 0.0
        var sinceSave = 0
        for id in ids {
            if Task.isCancelled || isRecording(in: context) { break }
            guard let run = context.model(for: id) as? Run, let end = run.endDate, end < settled else { continue }
            let before = run.distanceMeters
            guard run.remeasureDistance() else { continue }
            measured += 1
            metersBefore += before
            metersAfter += run.distanceMeters
            sinceSave += 1
            if sinceSave >= saveEvery {
                context.saveQuietly()
                sinceSave = 0
            }
            try? await Task.sleep(for: pause)
        }
        if sinceSave > 0 { context.saveQuietly() }
        // Counts and totals only.
        Trace.log(.app, "Distances measured again", [
            "runs": measured,
            "change": metersBefore > 0 ? (metersAfter / metersBefore * 1000).rounded() / 1000 : 1,
            "ms": Int((ContinuousClock.now - started) / .milliseconds(1)),
        ])
        return measured
    }

    private static func isRecording(in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.endDateValue == nil })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }
}
