//
//  WatchHomeTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The watch's home list: which of today's sessions show, when it says nothing came for today, and what
/// each row says.
@MainActor
struct WatchHomeTests {
    /// 08:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func session(
        on date: Date,
        blocks: [WatchCoachSession.Block] = [],
        meters: Double? = nil,
        seconds: TimeInterval? = nil,
        pace: ClosedRange<TimeInterval>? = nil
    ) -> WatchCoachSession {
        WatchCoachSession(
            sessionID: UUID(),
            kind: "easy",
            title: "Easy run",
            detail: "",
            date: date,
            targetMeters: meters,
            targetSeconds: seconds,
            paceFast: pace?.lowerBound,
            paceSlow: pace?.upperBound,
            effortLow: nil,
            effortHigh: nil,
            runWalk: nil,
            isKeySession: false,
            isQuality: false,
            stepsSignature: "",
            blocks: blocks
        )
    }

    @Test func toDoDropsOtherDaysAndOnesRunHere() {
        let yesterday = session(on: now.addingTimeInterval(-24 * 60 * 60))
        let early = session(on: now.addingTimeInterval(-60 * 60))
        let later = session(on: now.addingTimeInterval(60 * 60))
        let all = [yesterday, early, later]

        #expect(WatchCoachSession.toDo(all, doneSessionIDs: [], now: now, calendar: calendar) == [early, later])
        #expect(WatchCoachSession.toDo(all, doneSessionIDs: [later.sessionID], now: now, calendar: calendar) == [early])
        #expect(WatchCoachSession.toDo(all, doneSessionIDs: [early.sessionID, later.sessionID], now: now, calendar: calendar).isEmpty)
    }

    @Test func anyPlannedCountsSessionsAlreadyRun() {
        let yesterday = session(on: now.addingTimeInterval(-24 * 60 * 60))
        let today = session(on: now.addingTimeInterval(60 * 60))
        #expect(!WatchCoachSession.anyPlanned([], on: now, calendar: calendar))
        #expect(!WatchCoachSession.anyPlanned([yesterday], on: now, calendar: calendar))
        #expect(WatchCoachSession.anyPlanned([yesterday, today], on: now, calendar: calendar))
    }

    @Test func sessionSummaryPrefersStepsThenDistanceThenTime() {
        let steps = [WatchCoachSession.Block(repeatCount: 4, steps: [
            WatchCoachSession.Step(kind: .work, goalKind: .time, goalAmount: 180, isWalk: false),
            WatchCoachSession.Step(kind: .recovery, goalKind: .time, goalAmount: 120, isWalk: false),
        ])]
        let withSteps = session(on: now, blocks: steps, meters: 8_000, seconds: 2_400)
        #expect(withSteps.summary(unit: .kilometers) == RunFormat.intervalLength(withSteps.timeline, unit: .kilometers))

        let distance = session(on: now, meters: 8_000, seconds: 2_400)
        #expect(distance.summary(unit: .kilometers) == RunFormat.distance(8_000, unit: .kilometers, rounding: .toNearestOrAwayFromZero))

        #expect(session(on: now, meters: 0, seconds: 2_400).summary(unit: .kilometers) == "40 min")
        // Hours from an hour, as the iPhone's coach writes it.
        #expect(session(on: now, seconds: 4_800).summary(unit: .kilometers) == "1 h 20 min")
        #expect(session(on: now, seconds: 5_400).summary(unit: .kilometers) == CoachFormat.targetSummary(session(on: now, seconds: 5_400).target, unit: .kilometers))
        #expect(session(on: now).summary(unit: .kilometers) == nil)
        #expect(session(on: now, meters: 0, seconds: 0).summary(unit: .kilometers) == nil)
    }

    @Test func aSinglePaceHasNoDash() {
        let unit = DistanceUnit.kilometers
        let fast = RunFormat.pace(290, unit: unit, withUnit: false)
        let slow = RunFormat.pace(305, unit: unit, withUnit: false)

        #expect(session(on: now, pace: 290...290).summary(unit: unit) == "\(fast) /\(unit.symbol)")
        #expect(session(on: now, pace: 290...290).summary(unit: unit) == RunFormat.pace(290, unit: unit))
        #expect(session(on: now, seconds: 2_400, pace: 290...305).summary(unit: unit) == "40 min · \(fast)–\(slow) /\(unit.symbol)")
    }

    @Test func aSavedWorkoutReadsInItsOwnUnit() {
        let blocks = [WatchCoachSession.Block(repeatCount: 1, steps: [
            WatchCoachSession.Step(kind: .work, goalKind: .distance, goalAmount: 1_609.344, isWalk: false),
        ])]
        func workout(_ distanceUnit: String?) -> WatchSavedWorkout {
            WatchSavedWorkout(name: "Mile", createdDate: now, blocks: blocks, distanceUnit: distanceUnit)
        }
        func expected(in unit: DistanceUnit) -> String {
            RunFormat.intervalLength(workout(nil).timeline, unit: unit) { WorkoutDistance.text($0, in: unit) }
        }

        #expect(workout("miles").summary(defaultUnit: .kilometers) == expected(in: .miles))
        #expect(workout(nil).summary(defaultUnit: .kilometers) == expected(in: .kilometers))
        #expect(workout(nil).summary(defaultUnit: .miles) == expected(in: .miles))
        // A unit this app doesn't know reads in the runner's.
        #expect(workout("furlongs").summary(defaultUnit: .kilometers) == expected(in: .kilometers))
    }
}
