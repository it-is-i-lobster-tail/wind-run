//
//  SensorRules.swift
//  Wind Run
//

import Foundation

/// One thing Wind Run reads from, as the sensor checkup lists it.
nonisolated enum SensorKind: String, Codable, CaseIterable, Sendable {
    case heartRate
    case healthWorkouts
    case location
    case preciseLocation
    case gps
    case motion
    case steps
    case barometer
    case watchApp
    case appleDistance
}

/// How one check came out. Problems stop a run from recording something; warnings mean it records less
/// than it could.
nonisolated enum SensorState: String, Sendable {
    case ok
    case problem
    case warning
    /// Still finding out, such as waiting for the first heart rate reading.
    case waiting
    /// Turned off or not on this device, which is fine.
    case notUsed
}

/// What a check's button does.
nonisolated enum SensorFix: String, Sendable {
    /// Turns on the Heart rate switch, which asks Health.
    case turnOnHeartRate
    /// Turns on Steps and cadence, which asks for Motion & Fitness.
    case turnOnSteps
    /// Opens Wind Run's page in the Settings app.
    case openSettings
    /// Explains where Health's switches for Wind Run are, since no app can open them.
    case healthSettings

    var title: String {
        switch self {
        case .turnOnHeartRate, .turnOnSteps: "Turn On"
        case .openSettings: "Settings"
        case .healthSettings: "How to Fix"
        }
    }
}

/// One line of the checkup: a status dot, a short title, one sentence, and maybe a button.
nonisolated struct SensorRow: Identifiable, Equatable, Sendable {
    let id: SensorKind
    let state: SensorState
    let title: String
    let detail: String
    var fix: SensorFix?
    /// A heart rate reading to show beside the title, in red.
    var beatsPerMinute: Int?
}

/// Whether Health lets Wind Run record workouts, which every workout session needs.
nonisolated enum HealthWorkoutAccess: String, Codable, Sendable {
    case allowed
    case denied
    case notAsked
    /// Health isn't on this device, such as some iPads.
    case unavailable
}

/// Whether Wind Run may use location, as the system says.
nonisolated enum LocationAccess: String, Codable, Sendable {
    case notAsked
    case denied
    case allowed
}

/// What the iPhone knows about an Apple Watch and Wind Run on it.
nonisolated enum WatchAppState: String, Sendable {
    case notPaired
    case appNotInstalled
    case installed
}

/// Everything the setup checks read, gathered once so the rules can be worked out without the device.
nonisolated struct SensorSetup: Equatable, Sendable {
    var heartRateOn = false
    var health = HealthWorkoutAccess.notAsked
    var location = LocationAccess.notAsked
    /// Precise Location, which only means something once location is allowed.
    var preciseLocation = true
    var stepsOn = false
    var motionAvailable = true
    var motionAllowed = false
    var motionDenied = false
    var barometerAvailable = true
    /// Nil on the watch, or when the iPhone hasn't heard from WatchConnectivity yet.
    var watch: WatchAppState?
    /// Whether Bluetooth or wired headphones are the audio route now: the port kind only, never a name.
    var earbudsConnected = false
    /// On the watch, wording speaks of the watch rather than the iPhone.
    var isWatch = false
}

/// What the live test has seen so far. Values are shown on screen only and never saved or traced.
nonisolated struct SensorLiveReadings: Equatable, Sendable {
    /// How heart rate is being tested.
    enum HeartRate: Equatable, Sendable {
        /// Not part of this test: heart rate is off, or Health blocks workouts.
        case notTested
        case listening
        case couldNotStart
        case endedEarly
    }

    var heartRate = HeartRate.notTested
    var beatsPerMinute: Double?
    var source: HeartRateSource?
    var readingCount = 0
    /// Whether location updates are running for this test.
    var gpsStarted = false
    /// The newest fix's horizontal accuracy in meters. Never its place.
    var gpsAccuracy: Double?
    var stepsStarted = false
    var steps: Int?
}

/// A chip under the start buttons on the Run tab.
nonisolated struct SensorChip: Identifiable, Equatable, Sendable {
    let id: SensorKind
    let state: SensorState
    let text: String
    /// Shown as a red heart before the text.
    var showsHeart = false
}

/// The checkup's rules, worked out from what was read so they can be tested without a device.
nonisolated enum SensorRules {
    /// With heart rate listening and no reading for this long, the test says what to try.
    static let heartRateWait: TimeInterval = 30
    /// GPS this accurate or better is good for distance.
    static let goodAccuracy: Double = 15
    /// Fixes worse than this don't count toward distance, as `RunRecorder.maximumHorizontalAccuracy`.
    static let usableAccuracy: Double = 30

    // MARK: Setup

    /// The setup checks, in the order the page lists them.
    static func setupRows(_ setup: SensorSetup) -> [SensorRow] {
        var rows = [heartRate(setup), health(setup), location(setup), preciseLocation(setup), motion(setup), barometer(setup)]
        if let watch = watchApp(setup) { rows.append(watch) }
        return rows
    }

    static func heartRate(_ setup: SensorSetup) -> SensorRow {
        if setup.health == .unavailable {
            return SensorRow(id: .heartRate, state: .notUsed, title: "No heart rate here", detail: "Health isn't on this device, and heart rate comes through it.")
        }
        guard setup.heartRateOn else {
            return SensorRow(id: .heartRate, state: .warning, title: "Heart rate is off", detail: "Runs record no heart rate until this is on.", fix: .turnOnHeartRate)
        }
        let from = setup.isWatch ? "Read from the watch, or a strap paired with it." : "Read from AirPods Pro 3, Powerbeats Pro 2 or a strap during runs."
        return SensorRow(id: .heartRate, state: .ok, title: "Heart rate is on", detail: from)
    }

    static func health(_ setup: SensorSetup) -> SensorRow {
        switch setup.health {
        case .allowed:
            return SensorRow(id: .healthWorkouts, state: .ok, title: "Health allows workouts", detail: "Needed for heart rate and Apple's distance.")
        case .denied:
            return SensorRow(
                id: .healthWorkouts,
                state: setup.heartRateOn ? .problem : .warning,
                title: "Health blocks workouts",
                detail: setup.heartRateOn ? "Heart rate can't start until Workouts is allowed for Wind Run." : "No heart rate or Apple's distance until Workouts is allowed for Wind Run.",
                fix: .healthSettings
            )
        case .notAsked:
            if setup.heartRateOn {
                return SensorRow(id: .healthWorkouts, state: .warning, title: "Health hasn't been asked", detail: "Heart rate needs Workouts allowed. Turning it on asks.", fix: .turnOnHeartRate)
            }
            return SensorRow(id: .healthWorkouts, state: .notUsed, title: "Health not asked yet", detail: "Asked when you turn on heart rate or Save runs to Health.")
        case .unavailable:
            return SensorRow(id: .healthWorkouts, state: .notUsed, title: "Health isn't on this device", detail: "Runs are kept in Wind Run only.")
        }
    }

    static func location(_ setup: SensorSetup) -> SensorRow {
        switch setup.location {
        case .allowed:
            return SensorRow(id: .location, state: .ok, title: "Location allowed", detail: "Allowed while you use Wind Run.")
        case .denied:
            return SensorRow(id: .location, state: .problem, title: "Location is off", detail: "Runs can't measure distance without it.", fix: .openSettings)
        case .notAsked:
            return SensorRow(id: .location, state: .waiting, title: "Location not asked yet", detail: "Asked when your first run or the live test starts.")
        }
    }

    static func preciseLocation(_ setup: SensorSetup) -> SensorRow {
        guard setup.location == .allowed else {
            return SensorRow(id: .preciseLocation, state: .notUsed, title: "Precise Location", detail: "Checked once Location is allowed.")
        }
        if setup.preciseLocation {
            return SensorRow(id: .preciseLocation, state: .ok, title: "Precise Location on", detail: "GPS is sharp enough to measure distance.")
        }
        return SensorRow(id: .preciseLocation, state: .problem, title: "Precise Location is off", detail: "Approximate location is too rough to measure distance.", fix: .openSettings)
    }

    static func motion(_ setup: SensorSetup) -> SensorRow {
        guard setup.motionAvailable else {
            return SensorRow(id: .motion, state: .notUsed, title: "No step counter", detail: "This device can't count steps. Auto-pause uses GPS.")
        }
        if setup.motionDenied {
            return SensorRow(
                id: .motion,
                state: setup.stepsOn ? .problem : .warning,
                title: "Motion & Fitness off",
                detail: "No steps or cadence. Auto-pause and climb use GPS.",
                fix: .openSettings
            )
        }
        guard setup.stepsOn else {
            return SensorRow(id: .motion, state: .notUsed, title: "Steps are off", detail: "Turn on to count steps and cadence.", fix: .turnOnSteps)
        }
        if !setup.motionAllowed {
            return SensorRow(id: .motion, state: .waiting, title: "Motion & Fitness not asked yet", detail: "Asked when your first run starts.", fix: .turnOnSteps)
        }
        return SensorRow(id: .motion, state: .ok, title: "Steps and cadence on", detail: "Counted by the \(setup.isWatch ? "watch's" : "iPhone's") motion sensor.")
    }

    static func barometer(_ setup: SensorSetup) -> SensorRow {
        guard setup.barometerAvailable else {
            return SensorRow(id: .barometer, state: .notUsed, title: "No barometer", detail: "Climb comes from GPS heights.")
        }
        if setup.motionDenied {
            return SensorRow(id: .barometer, state: .warning, title: "Barometer can't be used", detail: "It needs Motion & Fitness. Climb comes from GPS for now.", fix: .openSettings)
        }
        return SensorRow(id: .barometer, state: .ok, title: "Barometer", detail: "Climb comes from air pressure.")
    }

    static func watchApp(_ setup: SensorSetup) -> SensorRow? {
        switch setup.watch {
        case nil:
            return nil
        case .notPaired:
            return SensorRow(id: .watchApp, state: .notUsed, title: "No Apple Watch paired", detail: "Heart rate can come from AirPods or a strap instead.")
        case .appNotInstalled:
            return SensorRow(id: .watchApp, state: .warning, title: "Wind Run isn't on your watch", detail: "Install it from the Watch app to run with the watch's heart rate.")
        case .installed:
            return SensorRow(id: .watchApp, state: .ok, title: "Wind Run is on your watch", detail: "Start a run on the watch for its heart rate.")
        }
    }

    // MARK: Live test

    /// What the live test shows, `elapsed` seconds in.
    static func liveRows(_ setup: SensorSetup, _ live: SensorLiveReadings, elapsed: TimeInterval) -> [SensorRow] {
        var rows = [liveHeartRate(setup, live, elapsed: elapsed), liveGPS(setup, live)]
        if let steps = liveSteps(setup, live) { rows.append(steps) }
        return rows
    }

    static func liveHeartRate(_ setup: SensorSetup, _ live: SensorLiveReadings, elapsed: TimeInterval) -> SensorRow {
        if setup.health == .unavailable {
            return heartRate(setup)
        }
        guard setup.heartRateOn else {
            return SensorRow(id: .heartRate, state: .problem, title: "Heart rate is off", detail: "Turn it on to test it.", fix: .turnOnHeartRate)
        }
        guard setup.health == .allowed else {
            return SensorRow(id: .heartRate, state: .problem, title: "Health blocks heart rate", detail: "Allow Workouts for Wind Run in Health, then test again.", fix: setup.health == .notAsked ? .turnOnHeartRate : .healthSettings)
        }
        if let bpm = live.beatsPerMinute, live.readingCount > 0 {
            let from = live.source.map { "From \(sourceName($0))." } ?? "Finding what measured it."
            let count = live.readingCount == 1 ? "1 reading so far." : "\(live.readingCount) readings so far."
            return SensorRow(id: .heartRate, state: .ok, title: "Heart rate", detail: "\(from) \(count)", beatsPerMinute: Int(bpm.rounded()))
        }
        switch live.heartRate {
        case .couldNotStart:
            return SensorRow(id: .heartRate, state: .problem, title: "Heart rate couldn't start", detail: "Health didn't start the workout session. Close other workout apps and test again.")
        case .endedEarly:
            return SensorRow(id: .heartRate, state: .problem, title: "Heart rate stopped", detail: "Another workout app may have taken over. Close it and test again.")
        case .notTested:
            return SensorRow(id: .heartRate, state: .notUsed, title: "Heart rate", detail: "Not part of this check.")
        case .listening:
            if elapsed >= heartRateWait {
                return SensorRow(id: .heartRate, state: .problem, title: "No heart rate yet", detail: heartRateTips(setup))
            }
            return SensorRow(id: .heartRate, state: .waiting, title: "Waiting for heart rate", detail: setup.isWatch ? "Wear the watch snugly." : "Put your AirPods in, or put on your strap.")
        }
    }

    /// What to try when no heart rate comes in, starting with what's connected.
    static func heartRateTips(_ setup: SensorSetup) -> String {
        if setup.isWatch {
            return "Wear the watch snugly, a finger's width above the wrist bone. A strap needs to be paired with the watch and on."
        }
        var tips: [String] = []
        if setup.earbudsConnected {
            tips.append("Put both AirPods in and check Heart Rate is on in your AirPods settings.")
        } else {
            tips.append("Put both AirPods in, or check your strap is paired in Bluetooth and on.")
        }
        if setup.watch == .installed {
            tips.append("For the watch's heart rate, start the run on the watch.")
        }
        return tips.joined(separator: " ")
    }

    static func liveGPS(_ setup: SensorSetup, _ live: SensorLiveReadings) -> SensorRow {
        if setup.location == .denied {
            return location(setup)
        }
        if setup.location == .allowed, !setup.preciseLocation {
            return preciseLocation(setup)
        }
        guard let accuracy = live.gpsAccuracy, accuracy >= 0 else {
            if !live.gpsStarted {
                return SensorRow(id: .gps, state: .notUsed, title: "GPS", detail: "Not part of this check.")
            }
            return SensorRow(id: .gps, state: .waiting, title: "Finding GPS…", detail: "Open sky finds it quickest.")
        }
        let meters = Int(accuracy.rounded())
        if accuracy <= goodAccuracy {
            return SensorRow(id: .gps, state: .ok, title: "GPS ±\(meters) m", detail: "Good enough for distance.")
        }
        if accuracy <= usableAccuracy {
            return SensorRow(id: .gps, state: .warning, title: "GPS ±\(meters) m", detail: "Usable, but distance may come up short. Open sky helps.")
        }
        return SensorRow(id: .gps, state: .problem, title: "GPS ±\(meters) m", detail: "Too rough to count. Step outside, away from tall buildings.")
    }

    /// Steps, unless this device can't count them.
    static func liveSteps(_ setup: SensorSetup, _ live: SensorLiveReadings) -> SensorRow? {
        guard setup.motionAvailable else { return nil }
        if setup.motionDenied {
            return SensorRow(id: .steps, state: .problem, title: "Steps", detail: "Motion & Fitness is off for Wind Run.", fix: .openSettings)
        }
        guard setup.motionAllowed else {
            return SensorRow(id: .steps, state: .notUsed, title: "Steps", detail: "Motion & Fitness hasn't been asked yet.", fix: setup.stepsOn ? nil : .turnOnSteps)
        }
        guard live.stepsStarted else {
            return SensorRow(id: .steps, state: .notUsed, title: "Steps", detail: "Not part of this check.")
        }
        if let steps = live.steps, steps > 0 {
            return SensorRow(id: .steps, state: .ok, title: "Steps \(steps)", detail: "From the \(setup.isWatch ? "watch's" : "iPhone's") motion sensor.")
        }
        return SensorRow(id: .steps, state: .waiting, title: "Steps", detail: "Walk a few steps to check.")
    }

    // MARK: Run tab

    /// The chips under the start buttons: GPS always, heart rate only with it on, steps only with them on.
    static func chips(_ setup: SensorSetup, _ live: SensorLiveReadings, elapsed: TimeInterval) -> [SensorChip] {
        var chips: [SensorChip] = []
        let gps = liveGPS(setup, live)
        let gpsText: String = switch (setup.location, gps.state) {
        case (.denied, _): "GPS off"
        case (.allowed, _) where !setup.preciseLocation: "GPS rough"
        case (.notAsked, _) where live.gpsAccuracy == nil: "GPS"
        case (_, .waiting), (_, .notUsed): "GPS…"
        default: gps.title
        }
        chips.append(SensorChip(id: .gps, state: setup.location == .notAsked && live.gpsAccuracy == nil ? .waiting : gps.state, text: gpsText))

        if setup.heartRateOn, setup.health != .unavailable {
            let row = liveHeartRate(setup, live, elapsed: elapsed)
            let text: String = if let bpm = row.beatsPerMinute {
                live.source.map { "\(bpm) \(shortSourceName($0))" } ?? "\(bpm)"
            } else {
                switch row.state {
                case .waiting: "…"
                case .notUsed: "Ready"
                default: setup.health == .allowed ? "No reading" : "Off in Health"
                }
            }
            chips.append(SensorChip(id: .heartRate, state: row.state == .notUsed ? .waiting : row.state, text: text, showsHeart: true))
        }

        if setup.stepsOn, setup.motionAvailable {
            let row = liveSteps(setup, live)
            let state: SensorState = switch row?.state {
            case .problem?: .problem
            case .ok?: .ok
            default: setup.motionAllowed ? .ok : .waiting
            }
            chips.append(SensorChip(id: .steps, state: state, text: state == .problem ? "Steps off" : "Steps"))
        }
        return chips
    }

    /// The one line under the chips: the first setup problem, or else heart rate that isn't coming in.
    static func readyProblem(_ setup: SensorSetup, _ live: SensorLiveReadings, elapsed: TimeInterval) -> SensorRow? {
        if let problem = setupRows(setup).first(where: { $0.state == .problem }) {
            return problem
        }
        if setup.heartRateOn {
            let row = liveHeartRate(setup, live, elapsed: elapsed)
            if row.state == .problem { return row }
        }
        return nil
    }

    // MARK: Names

    /// "AirPods or Powerbeats", "Apple Watch" or "a strap or sensor", as a reading's source.
    static func sourceName(_ source: HeartRateSource) -> String {
        switch source {
        case .earbuds: "AirPods or Powerbeats"
        case .appleWatch: "Apple Watch"
        case .strapOrSensor: "a strap or sensor"
        }
    }

    /// One short word for a chip.
    static func shortSourceName(_ source: HeartRateSource) -> String {
        switch source {
        case .earbuds: "Earbuds"
        case .appleWatch: "Watch"
        case .strapOrSensor: "Strap"
        }
    }
}
