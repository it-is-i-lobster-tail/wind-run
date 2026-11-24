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
///
/// With iCloud Sync on, a run another device is recording syncs here unfinished too. So only the run
/// this device was recording is finished at once; another device's run is left to that device, unless it
/// has had nothing new for a day.
enum RunRecovery {
    /// The run this device is recording, as its run id. Kept on this device only, never in iCloud or on the
    /// watch, so each device only finishes its own runs.
    static let recordingRunKey = "recordingRunID"
    /// A run left unfinished with nothing recorded for this long was cut off wherever it was recorded, such
    /// as by a version of the app from before runs were marked, and is finished here.
    static let abandonedAfter: TimeInterval = 24 * 60 * 60

    /// Marks `run` as the one this device is recording, or clears the mark with nil.
    static func markRecording(_ run: Run?, in defaults: UserDefaults = .standard) {
        if let run {
            defaults.set(run.runIDValue.uuidString, forKey: recordingRunKey)
        } else {
            defaults.removeObject(forKey: recordingRunKey)
        }
    }

    /// The run this device was recording when the app was closed, if any.
    static func recordingRunID(in defaults: UserDefaults = .standard) -> UUID? {
        defaults.string(forKey: recordingRunKey).flatMap(UUID.init(uuidString:))
    }

    /// Finishes each cut-off run at the last thing it recorded, and deletes any that recorded
    /// nothing. Finished runs go to Apple Health like any other, if that's on. Call when the
    /// app opens, before a new run can start.
    ///
    /// With `sparingRecording`, the run this device was recording is left as it is, mark and all, for the
    /// watch to carry on with the workout session watchOS kept going. It's finished by a later call.
    ///
    /// Returns the runs it finished, so the watch can send them to the iPhone.
    @discardableResult
    static func finishLeftoverRuns(
        in context: ModelContext,
        savingTo health: HealthSync? = .shared,
        defaults: UserDefaults = .standard,
        now: Date = .now,
        sparingRecording: Bool = false
    ) -> [Run] {
        let unfinished: [Run]
        do {
            unfinished = try context.fetch(FetchDescriptor<Run>(predicate: #Predicate { $0.endDateValue == nil }))
                .filter { !$0.isFinished }
        } catch {
            Logger.recording.error("Couldn't look for unfinished runs: \(error)")
            return []
        }
        let recordingID = recordingRunID(in: defaults)
        if !sparingRecording {
            // Whatever happens below, no run is being recorded here any more.
            markRecording(nil, in: defaults)
        }
        guard !unfinished.isEmpty else { return [] }

        let leftover = unfinished.filter { run in
            if run.runIDValue == recordingID { return !sparingRecording }
            return now.timeIntervalSince(run.lastRecordedDate ?? run.startDate) > abandonedAfter
        }
        let spared = sparingRecording && unfinished.contains { $0.runIDValue == recordingID } ? 1 : 0
        let elsewhere = unfinished.count - leftover.count - spared
        if elsewhere > 0 {
            // Most likely a run another device is recording right now.
            Trace.log(.run, "Unfinished runs from another device left alone", ["count": elsewhere])
        }
        guard !leftover.isEmpty else { return [] }

        var finished: [Run] = []
        var wasPaused = 0
        for run in leftover {
            if run.status == .paused { wasPaused += 1 }
            if let end = run.lastRecordedDate {
                run.finish(at: end)
                closeSteps(of: run)
                // As finishing in the app does, so a hard run cut off in the background still counts.
                HeartRateMax.record(run.heartRateSamples.map(\.beatsPerMinute), in: defaults)
                run.settleCalories(bodyMass: BodyWeight.kilograms())
                finished.append(run)
            } else {
                context.delete(run)
            }
        }
        context.saveQuietly()
        Logger.recording.info("Finished \(finished.count) cut-off runs and deleted \(leftover.count - finished.count) empty ones.")
        Trace.log(.run, "Recovered cut-off runs", [
            "finished": finished.count,
            "deleted": leftover.count - finished.count,
            "wasPaused": wasPaused,
        ])

        for run in finished {
            health?.saveIfEnabled(run, in: context)
        }
        return finished
    }

    /// Closes a structured run's steps the way finishing it in the app does: the step under way is cut short
    /// where the run stopped, and the steps after it count as skipped, so the coach reads them as not done
    /// rather than missing.
    private static func closeSteps(of run: Run) {
        guard let timeline = run.intervalPlanValue?.timeline, !timeline.isEmpty else { return }
        var tracker = StepTracker(timeline: timeline, resumingFrom: run.stepLog)
        guard !tracker.isFinished else { return }
        tracker.finish(elapsed: run.activeDuration(), meters: run.distanceMeters)
        run.saveStepLog(tracker.recorded)
    }
}
