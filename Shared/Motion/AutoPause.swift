//
//  AutoPause.swift
//  Wind Run
//

import CoreLocation
import Foundation

/// What the motion sensor last said the runner was doing.
enum MotionActivity: Equatable {
    case stationary
    /// Walking or running.
    case onFoot
    /// Driving, cycling, or nothing the sensor is sure of.
    case other
}

/// Decides when a run has stopped and when it's going again, from GPS speed and, when Motion & Fitness
/// is allowed, footsteps and the motion sensor.
///
/// With motion, both have to agree the runner is standing still before the run pauses, so GPS drift at
/// a crossing can't keep the clock going and a slow GPS fix can't pause a runner who's still striding.
/// Only footsteps start it again. Without motion, GPS speed decides alone, with steadier thresholds.
///
/// Feed it each GPS fix, footstep update and activity change, then call `check` about once a second.
struct AutoPause {
    /// Whether the runner turned auto-pause on. Off until they do.
    static let storageKey = "autoPauseEnabled"

    /// No footsteps for this long means motion thinks the runner has stopped.
    static let quietSteps: TimeInterval = 4
    /// GPS slower than this counts as standing. An easy walk is about 1.3 m/s.
    static let stoppedSpeed: CLLocationSpeed = 0.5
    /// Without motion, GPS at least this fast on two fixes in a row counts as moving again.
    static let movingSpeed: CLLocationSpeed = 1.2
    /// A GPS fix older than this says nothing about now.
    static let fixFreshness: TimeInterval = 5
    /// Standing still for this long, after the signs above, pauses the run.
    static let holdStill: TimeInterval = 2
    /// Footsteps this recent mean the runner is going again.
    static let freshSteps: TimeInterval = 3
    /// Shuffling at a crossing is slower than this many steps a minute and doesn't start the run again.
    static let movingCadence: Double = 70

    enum Decision: Equatable {
        case pause
        case resume
    }

    /// Whether footsteps and the motion sensor take part. Falls back to GPS alone if motion stops.
    var usesMotion: Bool

    private var lastStep: Date
    private var lastActivity: (activity: MotionActivity, date: Date)?
    private var lastFix: (speed: CLLocationSpeed, date: Date)?
    private var fixBefore: (speed: CLLocationSpeed, date: Date)?
    private var stillSince: Date?
    /// When this auto-pause started, or nil while the run is going.
    private(set) var pausedAt: Date?

    init(usesMotion: Bool, start: Date) {
        self.usesMotion = usesMotion
        // The run's first seconds count as moving, so a runner waiting for GPS isn't paused at once.
        self.lastStep = start
    }

    /// Footsteps were counted, at the given steps a minute when the sensor knows it.
    mutating func footsteps(at date: Date, cadence: Double?) {
        if let cadence, cadence < Self.movingCadence { return }
        lastStep = max(lastStep, date)
    }

    mutating func activity(_ activity: MotionActivity, at date: Date) {
        lastActivity = (activity, date)
    }

    /// A GPS fix's speed in meters a second, negative when GPS doesn't know.
    mutating func fix(speed: CLLocationSpeed, at date: Date) {
        fixBefore = lastFix
        lastFix = (speed, date)
    }

    /// The runner started or resumed the run themselves. They get the same head start as at the start.
    mutating func runnerResumed(at date: Date) {
        pausedAt = nil
        stillSince = nil
        lastStep = max(lastStep, date)
    }

    /// Skips a check, such as during a rest step, so stillness before it doesn't count after it.
    mutating func hold() {
        stillSince = nil
    }

    /// Whether the run should pause, or start again after this pausing it. `isPaused` is true only for
    /// an auto-pause; a pause the runner chose is theirs to end.
    mutating func check(at now: Date, isPaused: Bool) -> Decision? {
        if isPaused {
            guard isMoving(at: now) else { return nil }
            runnerResumed(at: now)
            return .resume
        }
        guard isStill(at: now) else {
            stillSince = nil
            return nil
        }
        let since = stillSince ?? now
        stillSince = since
        guard now.timeIntervalSince(since) >= Self.holdStill else { return nil }
        stillSince = nil
        pausedAt = now
        return .pause
    }

    private func freshSpeed(at now: Date) -> CLLocationSpeed? {
        guard let lastFix, lastFix.speed >= 0, now.timeIntervalSince(lastFix.date) <= Self.fixFreshness else { return nil }
        return lastFix.speed
    }

    private func isStill(at now: Date) -> Bool {
        let speed = freshSpeed(at: now)
        guard usesMotion else {
            return speed.map { $0 < Self.stoppedSpeed } ?? false
        }
        let stepsQuiet = now.timeIntervalSince(lastStep) >= Self.quietSteps
        let sensorStill = lastActivity.map { $0.activity == .stationary && $0.date > lastStep } ?? false
        // No GPS, say indoors or in a tunnel, leaves it to motion.
        let gpsStill = speed.map { $0 < Self.stoppedSpeed } ?? true
        return (stepsQuiet || sensorStill) && gpsStill
    }

    private func isMoving(at now: Date) -> Bool {
        guard let pausedAt else { return false }
        if usesMotion {
            return lastStep > pausedAt && now.timeIntervalSince(lastStep) <= Self.freshSteps
        }
        guard let lastFix, let fixBefore, fixBefore.date > pausedAt,
              now.timeIntervalSince(lastFix.date) <= Self.fixFreshness
        else { return false }
        return lastFix.speed >= Self.movingSpeed && fixBefore.speed >= Self.movingSpeed
    }
}
