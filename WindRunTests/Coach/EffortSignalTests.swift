//
//  EffortSignalTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// Family E's pace comparisons (AD-4): like-for-like easy runs slower at the same RPE, and Q sessions slower
/// than their target pace twice in a row.
@MainActor
struct EffortSignalTests {
    let weekStart = CoachFixtures.day(28, hour: 0)
    let easy = PlannedSession(dayOffset: 1, kind: .easy, target: Load(meters: 5_000, seconds: 1_800))
    let threshold = PlannedSession(dayOffset: 3, kind: .threshold, effort: .threshold, target: Load(meters: 7_000, seconds: 2_400), paceBand: PaceBand(fast: 294, slow: 306))

    func easyRun(day: Int, pace: Double, rpe: Int = 3, climb: Double = 0, source: RunSource = .gps) -> LoggedRun {
        LoggedRun(
            start: CoachFixtures.day(day),
            movingSeconds: 5 * pace,
            meters: 5_000,
            source: source,
            checkIn: RunCheckIn(answeredAt: CoachFixtures.day(day, hour: 9), rpe: rpe),
            track: TrackSummary(climbFirstHalf: climb / 2, climbSecondHalf: climb / 2)
        )
    }

    func qualityRun(day: Int, workPace: Double) -> LoggedRun {
        let steps = (0 ..< 3).map { _ in LoggedStep(isWork: true, meters: 1_000, seconds: workPace) }
        return LoggedRun(start: CoachFixtures.day(day), movingSeconds: 2_400, meters: 7_000, checkIn: RunCheckIn(rpe: 7), track: TrackSummary(), steps: steps)
    }

    @Test func slowerEasyRunsAtTheSameEffort() {
        let earlier = [1, 3, 8, 10, 15, 17].map { easyRun(day: $0, pace: 360) }
        let thisWeek = [
            easyRun(day: 29, pace: 380), easyRun(day: 31, pace: 381), easyRun(day: 33, pace: 379),
            easyRun(day: 34, pace: 400, rpe: 4),
            easyRun(day: 34, pace: 400, climb: 120),
        ]
        let runs = earlier + thisWeek
        let sessions = Dictionary(uniqueKeysWithValues: runs.map { ($0.id, easy) })
        #expect(WeeklyReviewer.slowEasyRuns(thisWeek, runs: runs, sessions: sessions, weekStart: weekStart) == 3)

        // Treadmill runs compare only with treadmill runs.
        let treadmill = [easyRun(day: 30, pace: 400, source: .treadmill)]
        let mixed = earlier + treadmill
        let mixedSessions = Dictionary(uniqueKeysWithValues: mixed.map { ($0.id, easy) })
        #expect(WeeklyReviewer.slowEasyRuns(treadmill, runs: mixed, sessions: mixedSessions, weekStart: weekStart) == 0)
    }

    @Test func qualitySlowTwiceInARow() {
        let slow = [qualityRun(day: 24, workPace: 312), qualityRun(day: 31, workPace: 313)]
        let sessions = Dictionary(uniqueKeysWithValues: slow.map { ($0.id, threshold) })
        #expect(WeeklyReviewer.qualitySlowTwice(runs: slow, sessions: sessions, weekStart: weekStart, weekEnd: CoachFixtures.day(35, hour: 0)))

        let recovered = [slow[0], qualityRun(day: 31, workPace: 301)]
        let recoveredSessions = Dictionary(uniqueKeysWithValues: recovered.map { ($0.id, threshold) })
        #expect(!WeeklyReviewer.qualitySlowTwice(runs: recovered, sessions: recoveredSessions, weekStart: weekStart, weekEnd: CoachFixtures.day(35, hour: 0)))
    }
}
