//
//  RunSensorReport.swift
//  Wind Run
//

import Foundation

/// What was set up and what started when a run was recorded, so its page can say why something is missing.
///
/// Only switches, permissions and kinds of connection are kept: no readings, no device names, no places.
/// Saved as the run starts, and updated when heart rate is blocked, its session ends early, or the run
/// finishes. Older runs have none, and only show what they recorded.
nonisolated struct RunSensorReport: Codable, Hashable, Sendable {
    /// How heart rate's workout session went.
    enum HeartRateSession: String, Codable, Sendable {
        /// Heart rate was off, so no session read it.
        case off
        case started
        /// Health doesn't let Wind Run record workouts.
        case blockedByHealth
        case couldNotStart
    }

    var heartRateOn: Bool
    var health: HealthWorkoutAccess
    var heartRateSession: HeartRateSession
    /// The system ended heart rate's session part way, such as when another workout app started.
    var heartRateEndedEarly = false
    /// Whether any workout session ran, which is where Apple's distance comes from.
    var workoutSessionStarted = false
    var stepsOn: Bool
    var motionAllowed: Bool
    var barometerUsed: Bool
    var locationAllowed: Bool
    var preciseLocation: Bool
    /// Bluetooth or wired headphones were the audio route at the start: the port kind only.
    var earbudsConnected: Bool
}

/// What a finished run recorded, gathered once for its Sensors section. Counts and kinds only.
nonisolated struct RunSensorFacts: Equatable, Sendable {
    var report: RunSensorReport?
    var heartRateReadings = 0
    /// The kinds of device that measured heart rate, from the run's devices or its readings.
    var heartRateSources: [HeartRateSource] = []
    var fixes = 0
    /// The middle accuracy of the run's fixes, in meters.
    var typicalAccuracy: Double?
    var appleDistance: Double?
    var steps: Double?
    var hasBarometer = false
    var countsSteps = true
    var recordedOnWatch = false
}

/// The Sensors section's rules, worked out from a run's facts and today's switches so they can be tested.
nonisolated enum RunSensorRules {
    /// One row per sensor. `now` hides fixes that are already done, such as heart rate turned on since.
    static func rows(_ facts: RunSensorFacts, now: SensorSetup) -> [SensorRow] {
        var rows = [heartRate(facts, now: now), gps(facts), appleDistance(facts, now: now)]
        if facts.countsSteps { rows.append(steps(facts, now: now)) }
        rows.append(climb(facts, now: now))
        return rows
    }

    static func heartRate(_ facts: RunSensorFacts, now: SensorSetup) -> SensorRow {
        let device = facts.recordedOnWatch ? "watch" : "iPhone"
        if facts.heartRateReadings > 0 {
            let from = facts.heartRateSources.isEmpty
                ? ""
                : " from " + facts.heartRateSources.map(SensorRules.sourceName).joined(separator: " and ")
            let count = facts.heartRateReadings == 1 ? "1 reading" : "\(facts.heartRateReadings) readings"
            if facts.report?.heartRateEndedEarly == true {
                return SensorRow(id: .heartRate, state: .warning, title: "Heart rate stopped early", detail: "\(count)\(from), then another workout app may have taken over.")
            }
            return SensorRow(id: .heartRate, state: .ok, title: "Heart rate", detail: "\(count)\(from).")
        }
        guard let report = facts.report else {
            return SensorRow(id: .heartRate, state: .notUsed, title: "No heart rate", detail: "This run recorded none. Runs this old don't say why.")
        }
        let healthFix: SensorFix? = now.health == .allowed ? nil : .healthSettings
        switch report.heartRateSession {
        case .off:
            let earbuds = report.earbudsConnected ? " Headphones were connected." : ""
            let fix: SensorFix? = now.heartRateOn ? nil : .turnOnHeartRate
            let onNow = now.heartRateOn ? " It's on now." : ""
            return SensorRow(id: .heartRate, state: .problem, title: "No heart rate", detail: "Heart rate was off in Settings, so none was read.\(earbuds)\(onNow)", fix: fix)
        case .blockedByHealth:
            return SensorRow(id: .heartRate, state: .problem, title: "No heart rate", detail: "Health didn't allow workouts, so heart rate couldn't start.", fix: healthFix)
        case .couldNotStart:
            return SensorRow(id: .heartRate, state: .problem, title: "Heart rate couldn't start", detail: "Health didn't start the workout session. Try the live test in Check Sensors.")
        case .started:
            if report.heartRateEndedEarly {
                return SensorRow(id: .heartRate, state: .problem, title: "Heart rate stopped", detail: "Another workout app may have taken over before any reading came in.")
            }
            let tip: String = if facts.recordedOnWatch {
                "Wear the watch snugly, and check Heart Rate is allowed for Wind Run in Health."
            } else if report.earbudsConnected {
                "Headphones were connected: check both AirPods are in and Heart Rate is on in their settings."
            } else {
                "No headphones were connected to the \(device). Put AirPods in or pair a strap before the run."
            }
            return SensorRow(id: .heartRate, state: .problem, title: "No heart rate came in", detail: tip, fix: healthFix)
        }
    }

    static func gps(_ facts: RunSensorFacts) -> SensorRow {
        if facts.fixes > 0 {
            let count = facts.fixes == 1 ? "1 fix" : "\(facts.fixes) fixes"
            guard let accuracy = facts.typicalAccuracy, accuracy >= 0 else {
                return SensorRow(id: .gps, state: .ok, title: "GPS", detail: "\(count).")
            }
            let meters = Int(accuracy.rounded())
            if accuracy > SensorRules.goodAccuracy {
                return SensorRow(id: .gps, state: .warning, title: "GPS was rough", detail: "\(count), typical accuracy ±\(meters) m. Distance may be short.")
            }
            return SensorRow(id: .gps, state: .ok, title: "GPS", detail: "\(count), typical accuracy ±\(meters) m.")
        }
        if facts.report?.locationAllowed == false {
            return SensorRow(id: .gps, state: .problem, title: "No GPS", detail: "Location was off for Wind Run, so no distance was measured.", fix: .openSettings)
        }
        if facts.report?.preciseLocation == false {
            return SensorRow(id: .gps, state: .problem, title: "No GPS", detail: "Precise Location was off, so no fix was sharp enough to count.", fix: .openSettings)
        }
        return SensorRow(id: .gps, state: .warning, title: "No GPS", detail: "No fix was good enough to count. Indoors, or under cover?")
    }

    static func appleDistance(_ facts: RunSensorFacts, now: SensorSetup) -> SensorRow {
        if let meters = facts.appleDistance, meters > 0 {
            return SensorRow(id: .appleDistance, state: .ok, title: "Apple's distance", detail: "Apple's workout measured its own distance to compare.")
        }
        guard let report = facts.report else {
            return SensorRow(id: .appleDistance, state: .notUsed, title: "No Apple distance", detail: "None was recorded for this run.")
        }
        if !report.workoutSessionStarted {
            let fix: SensorFix? = now.health == .allowed ? nil : (now.health == .notAsked ? .turnOnHeartRate : .healthSettings)
            return SensorRow(id: .appleDistance, state: .warning, title: "No Apple distance to compare", detail: "It comes from a workout session, which needs Workouts allowed in Health.", fix: fix)
        }
        return SensorRow(id: .appleDistance, state: .notUsed, title: "No Apple distance", detail: "The workout session gave none.")
    }

    static func steps(_ facts: RunSensorFacts, now: SensorSetup) -> SensorRow {
        let device = facts.recordedOnWatch ? "watch's" : "iPhone's"
        if let steps = facts.steps, steps > 0 {
            return SensorRow(id: .steps, state: .ok, title: "Steps and cadence", detail: "\(Int(steps.rounded())) steps from the \(device) motion sensor.")
        }
        guard let report = facts.report else {
            return SensorRow(id: .steps, state: .notUsed, title: "No steps", detail: "This run counted none.")
        }
        if !report.stepsOn {
            return SensorRow(id: .steps, state: .notUsed, title: "Steps were off", detail: "Turn on Steps and cadence to count them.", fix: now.stepsOn ? nil : .turnOnSteps)
        }
        if !report.motionAllowed {
            return SensorRow(id: .steps, state: .problem, title: "No steps", detail: "Motion & Fitness wasn't allowed for Wind Run.", fix: now.motionAllowed ? nil : .openSettings)
        }
        return SensorRow(id: .steps, state: .warning, title: "No steps came in", detail: "The motion sensor sent none. Was the \(facts.recordedOnWatch ? "watch" : "iPhone") carried?")
    }

    static func climb(_ facts: RunSensorFacts, now: SensorSetup) -> SensorRow {
        if facts.hasBarometer {
            return SensorRow(id: .barometer, state: .ok, title: "Climb", detail: "From the barometer.")
        }
        if let report = facts.report, !report.motionAllowed, now.barometerAvailable {
            return SensorRow(id: .barometer, state: .warning, title: "Climb from GPS", detail: "The barometer needs Motion & Fitness, so climb came from GPS heights.", fix: now.motionAllowed ? nil : .openSettings)
        }
        return SensorRow(id: .barometer, state: .notUsed, title: "Climb from GPS", detail: "No barometer readings, so climb came from GPS heights.")
    }
}

extension RunSensorReport {
    /// The middle of some accuracies, leaving out the unknown ones.
    static func typical(_ accuracies: [Double]) -> Double? {
        let known = accuracies.filter { $0 >= 0 }.sorted()
        guard !known.isEmpty else { return nil }
        return known[known.count / 2]
    }
}
