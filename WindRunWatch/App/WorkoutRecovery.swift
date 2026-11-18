//
//  WorkoutRecovery.swift
//  Wind Run Watch
//

import HealthKit
import Observation
import SwiftData
import WatchKit

/// Hears from watchOS when it opens Wind Run again after the app was closed during a run.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handleActiveWorkoutRecovery() {
        WorkoutRecovery.shared.recover()
    }
}

/// Carries on a run the watch app was closed in, such as by a crash.
///
/// watchOS keeps a run's workout session going when the app stops and opens the app again to pick it up.
/// The run this watch was recording is then carried on with that session instead of being finished at its
/// last fix. When there's no session to pick up, the run is finished there, as on the iPhone.
@Observable
final class WorkoutRecovery {
    static let shared = WorkoutRecovery()

    /// The session watchOS kept going, until a run carries on with it.
    private(set) var session: HKWorkoutSession?
    /// True from when watchOS asks until Health has answered.
    private(set) var isRecovering = false

    /// How long the app waits at launch for watchOS to ask, before it finishes the run it was recording.
    static let wait: Duration = .seconds(3)
    /// The longest the app ever waits at launch, even while Health is answering.
    static let longestWait: Duration = wait * 4
    /// How often the app looks again while it waits.
    static let pollInterval: Duration = .milliseconds(200)

    func recover() {
        guard !isRecovering, session == nil else { return }
        isRecovering = true
        Task {
            let session = await HeartRateMonitor.recoverSession()
            Trace.log(.run, "Recovered workout session", ["recovered": session != nil])
            self.session = session
            isRecovering = false
        }
    }

    /// The session, for the run carrying on with it. It's handed over once.
    func takeSession() -> HKWorkoutSession? {
        defer { session = nil }
        return session
    }

    /// At launch: carries on the run this watch was recording when the app was closed, if watchOS kept its
    /// workout session going, and returns the recorder for it. Otherwise finishes that run at its last fix,
    /// as `RunRecovery` does, and returns nil.
    func carryOnOrFinish(in context: ModelContext, measuresHeartRate: Bool) async -> RunRecorder? {
        guard let id = RunRecovery.recordingRunID() else { return nil }
        // watchOS asks right after launch, and Health answers quickly. Waited for a little longer while
        // Health is answering, but never long.
        let start = ContinuousClock.now
        while session == nil {
            let waited = ContinuousClock.now - start
            if (waited > Self.wait && !isRecovering) || waited > Self.longestWait { break }
            try? await Task.sleep(for: Self.pollInterval)
        }
        if let session = takeSession() {
            let runs = (try? context.fetch(FetchDescriptor<Run>(predicate: #Predicate { $0.runIDValue == id }))) ?? []
            if let run = runs.first, !run.isFinished {
                let recorder = RunRecorder(modelContext: context)
                recorder.carryOn(run, session: session, measuresHeartRate: measuresHeartRate)
                if recorder.isRecording { return recorder }
            }
            // The session outlived its run: nothing to carry on.
            Trace.log(.run, "Recovered workout session has no run to carry on")
            session.end()
        }
        RunRecovery.finishLeftoverRuns(in: context)
        return nil
    }
}
