//
//  RunRecorderLogicTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// The recorder's pure pieces: the climb threshold, the spoken steps, a coach session's target and the GPS
/// signal, each worked out without GPS, Health or a run under way.
@MainActor
struct RunRecorderLogicTests {
    // It has to outlive the coach sessions made in it.
    private let container = WindRunSchema.makeContainer(inMemory: true)

    // MARK: Climb

    @Test func theBarometerCountsFinerClimbThanGPS() {
        #expect(ClimbCounter.threshold(hasBarometer: true) == 2)
        #expect(ClimbCounter.threshold(hasBarometer: false) == 6)
        #expect(ClimbCounter.barometerThreshold == 2)
        #expect(ClimbCounter.gpsThreshold == 6)
    }

    @Test func gpsHeightNeedsSixMetersToCountAsClimb() {
        var climb = ClimbCounter(threshold: ClimbCounter.threshold(hasBarometer: false))
        for height in [0, 5, 5.9, 6, 1, 0.5, -0.5] as [Double] {
            climb.record(height)
        }
        // 0 to 6 counts as 6 up; 6 to 0.5 is only 5.5 down, then -0.5 makes 6.5 down.
        #expect(climb.ascent == 6)
        #expect(climb.descent == 6.5)
    }

    @Test func switchingToGPSKeepsTheClimbAndNeverCountsTheJump() {
        var climb = ClimbCounter(threshold: ClimbCounter.barometerThreshold)
        for height in [0, 3, 10] as [Double] {
            climb.record(height)
        }
        #expect(climb.ascent == 10)
        // The barometer stops. GPS reads 40 m from its own zero: not a climb of 30 m.
        climb.switchSource(threshold: ClimbCounter.gpsThreshold)
        #expect(climb.threshold == ClimbCounter.gpsThreshold)
        for height in [40, 44, 45.5] as [Double] {
            climb.record(height)
        }
        // 4 and 5.5 m above the new start are GPS noise at its 6 m threshold.
        #expect(climb.ascent == 10)
        #expect(climb.descent == 0)
        climb.record(46)
        #expect(climb.ascent == 16)
    }

    // MARK: Spoken steps

    @Test func aWalkBreakIsSaidTheSameWayItsReminderIs() {
        let walk = PlannedIntervalStep(kind: .recovery, goal: .open, repetition: 1, repeatCount: 1, isWalk: true)
        #expect(RunRecorder.spokenStep(walk) == RunRecorder.walkBreakText)
        #expect(RunRecorder.walkBreakText == "Walk. Tap when you're ready to run again.")
        #expect(RunRecorder.lastStepDoneText(for: .running) == "That's the last step. Run as you like, then finish when you're done.")
    }

    @Test func aDistanceStepIsSaidInTheUnitGiven() {
        let work = PlannedIntervalStep(kind: .work, goal: .distance(meters: 400), repetition: 1, repeatCount: 1)
        let metric = RunRecorder.spokenStep(work, unit: .kilometers)
        let imperial = RunRecorder.spokenStep(work, unit: .miles)
        #expect(metric == "Work, \(SpokenFormat.distance(400, unit: .kilometers)).")
        #expect(imperial == "Work, \(SpokenFormat.distance(400, unit: .miles)).")
        #expect(metric != imperial)
    }

    @Test func aTimedStepIsTheSameInEitherUnit() {
        let work = PlannedIntervalStep(kind: .work, goal: .time(60), repetition: 1, repeatCount: 1)
        #expect(RunRecorder.spokenStep(work, unit: .kilometers) == RunRecorder.spokenStep(work, unit: .miles))
        #expect(RunRecorder.spokenStep(work, unit: .kilometers) == "Work, \(SpokenFormat.duration(60)).")
    }

    @Test func anOpenStepThatIsNotAWalkSaysItsName() {
        let recover = PlannedIntervalStep(kind: .recovery, goal: .open, repetition: 1, repeatCount: 1)
        #expect(RunRecorder.spokenStep(recover) == "Recover. Tap when you're ready for the next step.")
    }

    // MARK: A coach session's target

    private func workout(meters: Double?, seconds: Double?) -> CoachWorkout {
        let workout = CoachWorkout(kind: "easy", dayOffset: 0)
        container.mainContext.insert(workout)
        workout.targetMetersValue = meters
        workout.targetSecondsValue = seconds
        return workout
    }

    @Test func aPositiveTargetIsKept() {
        let session = workout(meters: 5_000, seconds: 1_800)
        #expect(session.positiveTargetMeters == 5_000)
        #expect(session.positiveTargetSeconds == 1_800)
    }

    @Test func aZeroOrNegativeTargetMeansNone() {
        #expect(workout(meters: 0, seconds: 0).positiveTargetMeters == nil)
        #expect(workout(meters: 0, seconds: 0).positiveTargetSeconds == nil)
        #expect(workout(meters: -1, seconds: -1).positiveTargetMeters == nil)
        #expect(workout(meters: -1, seconds: -1).positiveTargetSeconds == nil)
        #expect(workout(meters: nil, seconds: nil).positiveTargetMeters == nil)
        #expect(workout(meters: nil, seconds: nil).positiveTargetSeconds == nil)
    }

    // MARK: GPS signal

    private let now = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func noCountedFixIsStillSearching() {
        #expect(RunRecorder.gpsSignal(lastCountedFix: nil, locationUnavailable: false, at: now) == .searching)
        #expect(RunRecorder.gpsSignal(lastCountedFix: nil, locationUnavailable: true, at: now) == .searching)
    }

    @Test func aRecentFixIsGood() {
        #expect(RunRecorder.gpsSignal(lastCountedFix: now.addingTimeInterval(-5), locationUnavailable: false, at: now) == .good)
        // Exactly the limit is not past it.
        let atTheLimit = now.addingTimeInterval(-RunRecorder.signalLostAfter)
        #expect(RunRecorder.gpsSignal(lastCountedFix: atTheLimit, locationUnavailable: false, at: now) == .good)
    }

    @Test func anOldFixIsWeak() {
        let old = now.addingTimeInterval(-(RunRecorder.signalLostAfter + 1))
        #expect(RunRecorder.gpsSignal(lastCountedFix: old, locationUnavailable: false, at: now) == .weak)
    }

    @Test func aFreshFixWithLocationUnavailableIsWeak() {
        #expect(RunRecorder.gpsSignal(lastCountedFix: now, locationUnavailable: true, at: now) == .weak)
    }
}
