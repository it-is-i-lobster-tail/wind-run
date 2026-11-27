//
//  RouteMigration.swift
//  Wind Run
//

import Foundation
import SwiftData

/// Packs the route of every finished run recorded before routes were packed (`Run.routeDataValue`), so
/// older runs open as quickly as new ones. It also catches runs that come in through iCloud from a device
/// still on an older version.
///
/// One run at a time on the main context, with a pause between, so the app stays smooth while it works
/// through a long history; it picks up where it left off the next time the app comes to the front. The
/// fixes' own records stay for now, for older versions of the app; a later update drops them.
@MainActor
enum RouteMigration {
    /// A run that finished this recently may still be arriving through iCloud, fix by fix, so it waits.
    static let settlingTime: TimeInterval = 60 * 60
    /// Rest between runs, so scrolling and taps aren't held up.
    static let pause: Duration = .milliseconds(150)
    /// Runs packed between saves.
    static let saveEvery = 5

    private static var isRunning = false

    /// Packs runs until none are left, the task is cancelled, or a run is being recorded. Returns how many
    /// it packed.
    @discardableResult
    static func packOldRuns(in context: ModelContext, now: Date = .now, pause: Duration = Self.pause) async -> Int {
        guard !isRunning else { return 0 }
        isRunning = true
        defer { isRunning = false }
        let settled = now.addingTimeInterval(-settlingTime)
        var descriptor = FetchDescriptor<Run>(
            predicate: #Predicate { $0.routePackedCountValue == nil && $0.endDateValue != nil },
            sortBy: [SortDescriptor(\.startDateValue, order: .reverse)]
        )
        guard let ids = try? context.fetchIdentifiers(descriptor), !ids.isEmpty else { return 0 }
        let started = ContinuousClock.now
        var packed = 0
        var skipped = 0
        var sinceSave = 0
        for id in ids {
            if Task.isCancelled || isRecording(in: context) { break }
            guard let run = context.model(for: id) as? Run, run.status == .complete, !run.hasPackedRoute,
                  let end = run.endDate, end < settled else {
                skipped += 1
                continue
            }
            if run.routeSamplesValue?.isEmpty ?? true {
                // Nothing to pack. Marked so it isn't looked at again.
                run.routePackedCountValue = 0
            } else {
                run.packRoute()
                packed += 1
            }
            sinceSave += 1
            if sinceSave >= saveEvery {
                context.saveQuietly()
                sinceSave = 0
            }
            try? await Task.sleep(for: pause)
        }
        if sinceSave > 0 { context.saveQuietly() }
        // Counts and time only.
        Trace.log(.app, "Routes packed", [
            "packed": packed,
            "skipped": skipped,
            "waiting": ids.count - packed - skipped,
            "ms": Int((ContinuousClock.now - started) / .milliseconds(1)),
        ])
        return packed
    }

    /// Whether a run is being recorded, when packing waits so recording has the phone to itself.
    private static func isRecording(in context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<Run>(predicate: #Predicate { $0.endDateValue == nil })
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }
}
