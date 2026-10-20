//
//  LoggedRun+Run.swift
//  Wind Run
//

import Foundation

extension LoggedRun {
    /// The coach's reading of a finished run.
    ///
    /// - Parameter track: the run's track summary, when it's already been worked out.
    init(_ run: Run, track: TrackSummary?) {
        self.init(
            id: run.runID,
            start: run.startDate,
            movingSeconds: run.activeDuration(),
            meters: run.distanceMeters,
            // A run without a route was recorded without GPS, so only its time counts.
            source: (run.routeSamplesValue?.count ?? 0) > 1 ? .gps : .manual,
            plannedSessionID: run.coachWorkout?.sessionID,
            checkIn: run.checkIn,
            track: track
        )
    }
}

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
