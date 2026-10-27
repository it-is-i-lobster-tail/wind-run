//
//  RunRecovery.swift
//  Wind Run
//

import Foundation
import OSLog
import SwiftData

/// Tidies up runs the app was closed in the middle of.
///
/// A run only records while the app is running, so a run still active or paused when the app
/// opens was cut off, for example when the system ended the app in the background. Left alone,
/// it would stay unfinished and never show in the run list.
enum RunRecovery {
    /// Finishes each cut-off run at the last thing it recorded, and deletes any that recorded
    /// nothing. Finished runs go to Apple Health like any other, if that's on. Call when the
    /// app opens, before a new run can start.
    static func finishLeftoverRuns(in context: ModelContext, savingTo health: HealthSync? = .shared) {
        let unfinished: [Run]
        do {
            unfinished = try context.fetch(FetchDescriptor<Run>(predicate: #Predicate { $0.endDateValue == nil }))
                .filter { !$0.isFinished }
        } catch {
            Logger.recording.error("Couldn't look for unfinished runs: \(error.localizedDescription)")
            return
        }
        guard !unfinished.isEmpty else { return }

        var finished: [Run] = []
        for run in unfinished {
            if let end = run.lastRecordedDate {
                run.finish(at: end)
                run.settleCalories(bodyMass: BodyWeight.kilograms())
                finished.append(run)
            } else {
                context.delete(run)
            }
        }
        context.saveQuietly()
        Logger.recording.info("Finished \(finished.count) cut-off runs and deleted \(unfinished.count - finished.count) empty ones.")

        for run in finished {
            health?.saveIfEnabled(run, in: context)
        }
    }
}
