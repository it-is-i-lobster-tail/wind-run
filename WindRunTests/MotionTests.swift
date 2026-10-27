//
//  MotionTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// Auto-pause deciding from GPS and footsteps together, and the pedometer's total turned into step counts.
@MainActor
struct AutoPauseTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    /// Runs `check` once a second from `from` to `to`, feeding a GPS fix and, while running, footsteps each
    /// second, and returns the first decision with its time.
    private func run(
        _ autoPause: inout AutoPause,
        from: TimeInterval,
        to: TimeInterval,
        isPaused: Bool = false,
        speed: Double?,
        footsteps: Bool
    ) -> (decision: AutoPause.Decision, at: TimeInterval)? {
        for second in stride(from: from, through: to, by: 1) {
            if let speed { autoPause.fix(speed: speed, at: at(second)) }
            if footsteps { autoPause.footsteps(at: at(second), cadence: 170) }
            if let decision = autoPause.check(at: at(second), isPaused: isPaused) {
                return (decision, second)
            }
        }
        return nil
    }

    @Test func standingStillPausesOnceMotionAndGPSAgree() {
        var autoPause = AutoPause(usesMotion: true, start: start)
        #expect(run(&autoPause, from: 0, to: 60, speed: 3, footsteps: true) == nil)
        // Footsteps stop at 60 s and GPS slows: no steps for 4 s, then 2 s more of standing.
        let stop = run(&autoPause, from: 61, to: 90, speed: 0.2, footsteps: false)
        #expect(stop?.decision == .pause)
        #expect(stop?.at == 66)
        #expect(autoPause.pausedAt == at(66))
    }

    @Test func gpsDriftAloneDoesntPauseAStridingRunner() {
        var autoPause = AutoPause(usesMotion: true, start: start)
        // Under a bridge GPS says 0.3 m/s, but the steps keep coming.
        #expect(run(&autoPause, from: 0, to: 120, speed: 0.3, footsteps: true) == nil)
    }

    @Test func noFootstepsButGPSMovingDoesntPause() {
        var autoPause = AutoPause(usesMotion: true, start: start)
        // A pedometer gap with GPS still saying 3 m/s isn't a stop.
        #expect(run(&autoPause, from: 0, to: 60, speed: 3, footsteps: false) == nil)
    }

    @Test func noGPSLeavesItToMotion() {
        var autoPause = AutoPause(usesMotion: true, start: start)
        #expect(run(&autoPause, from: 0, to: 30, speed: nil, footsteps: true) == nil)
        #expect(run(&autoPause, from: 31, to: 60, speed: nil, footsteps: false)?.decision == .pause)
    }

    @Test func footstepsStartItAgain() {
        var autoPause = AutoPause(usesMotion: true, start: start)
        _ = run(&autoPause, from: 0, to: 30, speed: 3, footsteps: true)
        #expect(run(&autoPause, from: 31, to: 60, speed: 0, footsteps: false)?.decision == .pause)
        // Standing at the light: nothing.
        #expect(run(&autoPause, from: 61, to: 120, isPaused: true, speed: 0.4, footsteps: false) == nil)
        // Off again: the first footsteps start the clock.
        #expect(run(&autoPause, from: 121, to: 130, isPaused: true, speed: 0.4, footsteps: true)?.at == 121)
        #expect(autoPause.pausedAt == nil)
    }

    @Test func shufflingAtACrossingDoesntStartIt() {
        var autoPause = AutoPause(usesMotion: true, start: start)
        _ = run(&autoPause, from: 0, to: 30, speed: 3, footsteps: true)
        #expect(run(&autoPause, from: 31, to: 60, speed: 0, footsteps: false)?.decision == .pause)
        autoPause.footsteps(at: at(70), cadence: 20)
        #expect(autoPause.check(at: at(71), isPaused: true) == nil)
    }

    @Test func theMotionSensorSayingStationaryPausesBeforeTheStepsGoQuiet() {
        var autoPause = AutoPause(usesMotion: true, start: start)
        _ = run(&autoPause, from: 0, to: 30, speed: 3, footsteps: true)
        autoPause.activity(.stationary, at: at(30.5))
        autoPause.fix(speed: 0.1, at: at(31))
        #expect(autoPause.check(at: at(31), isPaused: false) == nil)
        autoPause.fix(speed: 0.1, at: at(33))
        #expect(autoPause.check(at: at(33), isPaused: false) == .pause)
    }

    @Test func withoutMotionGPSDecidesAlone() {
        var autoPause = AutoPause(usesMotion: false, start: start)
        #expect(run(&autoPause, from: 0, to: 30, speed: 3, footsteps: false) == nil)
        #expect(run(&autoPause, from: 31, to: 60, speed: 0.2, footsteps: false)?.at == 33)
        // One fast fix could be a jump in the GPS; two in a row is moving.
        autoPause.fix(speed: 2, at: at(70))
        #expect(autoPause.check(at: at(70), isPaused: true) == nil)
        autoPause.fix(speed: 2, at: at(71))
        #expect(autoPause.check(at: at(71), isPaused: true) == .resume)
    }

    @Test func withoutMotionNoGPSNeverPauses() {
        var autoPause = AutoPause(usesMotion: false, start: start)
        #expect(run(&autoPause, from: 0, to: 120, speed: nil, footsteps: false) == nil)
    }

    @Test func theRunnerResumingGetsAHeadStart() {
        var autoPause = AutoPause(usesMotion: true, start: start)
        _ = run(&autoPause, from: 0, to: 30, speed: 0, footsteps: true)
        autoPause.runnerResumed(at: at(100))
        // Still standing after tapping Resume: pauses again, but only after the same 4 + 2 s.
        #expect(run(&autoPause, from: 100, to: 120, speed: 0, footsteps: false)?.at == 106)
    }

    @Test func aHoldStartsTheWaitOver() {
        var autoPause = AutoPause(usesMotion: true, start: start)
        _ = run(&autoPause, from: 0, to: 10, speed: 3, footsteps: true)
        autoPause.fix(speed: 0, at: at(14))
        #expect(autoPause.check(at: at(14), isPaused: false) == nil)
        #expect(autoPause.check(at: at(15), isPaused: false) == nil)
        // A rest step: without the hold, 16 s would be the 2 s that pauses.
        autoPause.hold()
        #expect(autoPause.check(at: at(16), isPaused: false) == nil)
        #expect(autoPause.check(at: at(17), isPaused: false) == nil)
        #expect(autoPause.check(at: at(18), isPaused: false) == .pause)
    }
}

@MainActor
struct FootstepLogTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test func updatesBecomeStepCountsJoinedUpToABucket() {
        var log = FootstepLog(start: start)
        // 3 steps a second, an update every 2.5 s for a minute.
        for update in 1...24 {
            let seconds = Double(update) * 2.5
            let stepped = log.record(totalSteps: seconds * 3, cadence: 180, at: at(seconds), counts: true)
            #expect(stepped)
        }
        #expect(log.total == 180)
        #expect(log.samples.count == 4)
        #expect(log.samples.allSatisfy { $0.end.timeIntervalSince($0.start) <= FootstepLog.bucket })
        #expect(log.samples.first?.start == start)
        #expect(log.samples.last?.end == at(60))
        #expect(abs((log.samples.first?.stepsPerMinute ?? 0) - 180) < 0.001)
    }

    @Test func stepsWhilePausedArentCounted() {
        var log = FootstepLog(start: start)
        log.record(totalSteps: 30, cadence: 180, at: at(10), counts: true)
        // Walking back to the start while paused.
        let steppedWhilePaused = log.record(totalSteps: 60, cadence: 120, at: at(25), counts: false)
        #expect(steppedWhilePaused)
        log.record(totalSteps: 90, cadence: 180, at: at(35), counts: true)
        #expect(log.total == 60)
    }

    @Test func aLongGapPutsTheNewStepsAtItsEnd() {
        var log = FootstepLog(start: start)
        log.record(totalSteps: 30, cadence: 180, at: at(10), counts: true)
        // Two minutes standing, then 9 steps at 180 a minute: they took 3 s, not two minutes.
        log.record(totalSteps: 39, cadence: 180, at: at(133), counts: true)
        #expect(log.samples.last?.start == at(130))
        #expect(log.samples.allSatisfy { $0.end.timeIntervalSince($0.start) <= RunCadence.finestUsable })
    }

    @Test func noNewStepsIsNoFootstep() {
        var log = FootstepLog(start: start)
        log.record(totalSteps: 30, cadence: 180, at: at(10), counts: true)
        let sameTotal = log.record(totalSteps: 30, cadence: 0, at: at(12), counts: true)
        #expect(!sameTotal)
        let outOfOrder = log.record(totalSteps: 31, cadence: 180, at: at(11), counts: true)
        #expect(!outOfOrder)
    }
}
