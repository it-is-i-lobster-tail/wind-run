//
//  LoggedRun+Run.swift
//  Wind Run
//

import Foundation

extension LoggedRun {
    /// The coach's reading of a finished run: its steps and walk breaks as they were run, and its
    /// heart rate worked out now on the device. Heart rate never goes into the plan's state.
    ///
    /// - Parameters:
    ///   - track: the run's track, when it has a route.
    ///   - heartRateSettings: the runner's device-local heart-rate settings.
    @MainActor
    init(_ run: Run, track: RunTrack?, heartRateSettings: HeartRateSettings? = nil) {
        let heartRateSettings = heartRateSettings ?? CoachHeartRateStore.load()
        let moving = run.activeDuration()
        let timeline = run.intervalPlanValue?.timeline ?? []
        let recorded = run.stepLog.map { step in
            (step: step, planned: timeline.indices.contains(step.index) ? timeline[step.index] : nil)
        }
        let isWalkSession = run.coachWorkout?.kind == SessionKind.walk.rawValue

        // The steps as run, for interval and run-walk sessions. A run with no step log has none.
        let steps: [LoggedStep]? = recorded.isEmpty ? nil : recorded.map { entry in
            LoggedStep(
                isWork: entry.planned?.kind == .work && entry.planned?.isWalk != true,
                meters: entry.step.meters,
                seconds: entry.step.seconds,
                cut: entry.step.cut,
                splits: track.map { track in
                    track.splits(from: entry.step.startElapsed, to: entry.step.endElapsed)
                        .map { Split(meters: $0.meters, seconds: $0.seconds, climbMeters: $0.climb) }
                }
            )
        }

        // A walk-stage session is all walking; a run-walk session counts its walk breaks as run.
        let walking: Double? = if isWalkSession {
            moving
        } else if recorded.contains(where: { $0.planned?.isWalk == true }) {
            recorded.filter { $0.planned?.isWalk == true }.reduce(0) { $0 + $1.step.seconds }
        } else {
            nil
        }

        // Steady stretches, where an Apple Watch's heart rate can be decision-grade: the whole run, or
        // each running step that isn't a recovery or walk.
        let steady: [RunHeartRateReading.Span] = recorded.isEmpty
            ? [RunHeartRateReading.Span(start: 0, end: moving)]
            : recorded.filter { $0.planned?.isWalk != true && $0.planned?.kind != .recovery }
                .map { RunHeartRateReading.Span(start: $0.step.startElapsed, end: $0.step.endElapsed) }

        let heartRate = RunHeartRate(
            reading: RunHeartRateReading(run),
            settings: heartRateSettings,
            steps: recorded.map { ($0.step, $0.planned?.kind == .work && $0.planned?.isWalk != true) },
            track: track,
            steadyStretches: steady
        )

        self.init(
            id: run.runID,
            start: run.startDate,
            movingSeconds: moving,
            meters: run.distanceMeters,
            // A run without a route was recorded without GPS, so only its time counts.
            source: (run.routeSamplesValue?.count ?? 0) > 1 ? .gps : .manual,
            plannedSessionID: run.coachWorkout?.sessionID,
            checkIn: run.checkIn,
            track: track.map { TrackSummary($0) },
            steps: steps,
            walkingSeconds: walking,
            heartRate: heartRate
        )
    }
}

@MainActor
extension Run {
    /// The runner's after-run answers, if any.
    var checkIn: RunCheckIn? {
        guard let data = checkInData else { return nil }
        return try? JSONDecoder().decode(RunCheckIn.self, from: data)
    }

    /// Stores the runner's after-run answers.
    func saveCheckIn(_ checkIn: RunCheckIn) {
        saveCheckIn(try? JSONEncoder().encode(checkIn))
    }
}
