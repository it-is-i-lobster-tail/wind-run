//
//  SensorCheck.swift
//  Wind Run
//

import AVFAudio
import CoreLocation
import CoreMotion
import Foundation
import Observation
#if os(iOS)
import WatchConnectivity
#endif

/// The sensor and Health checkup: what's set up, and a short live test that shows readings as they come in.
///
/// Setup is read from switches and the system's permissions, straight away. The live test is the only way
/// to know heart rate really works, since Health never says whether reading it is allowed: it starts a
/// throwaway workout session and watches for readings, along with GPS accuracy and steps.
///
/// Nothing the test sees is kept. Its workout session's workout is always discarded, so it never reaches
/// Health, and it makes no run. GPS gives its accuracy only, never where the runner is. Trace lines say that
/// a reading came and from what kind of device, never its value.
///
/// Only one workout session can run at a time, so a run's start stops every check first
/// (`stopAll()`, or `stopAllAndWait()` where there's time to wait).
@Observable
final class SensorCheck {
    /// The full test on the Check Sensors page, or the lighter one behind the Run tab's chips.
    enum Mode {
        /// Everything that can be tested: heart rate when it's on, GPS, and steps when allowed.
        case test
        /// Only what the chips show, and no permission questions: opening the tab shouldn't ask anything.
        case ready

        var duration: TimeInterval {
            switch self {
            case .test: 60
            case .ready: 120
            }
        }

        var traceName: String {
            switch self {
            case .test: "test"
            case .ready: "ready"
            }
        }
    }

    private(set) var setup: SensorSetup
    private(set) var live = SensorLiveReadings()
    private(set) var mode = Mode.test
    /// When the live test started, or nil when it isn't running.
    private(set) var startedAt: Date?
    /// When the last live test ended on its own, so a page can say it finished.
    private(set) var finishedAt: Date?

    var isRunning: Bool { startedAt != nil }
    var duration: TimeInterval { mode.duration }

    @ObservationIgnored private let reads: () -> SensorSetup
    @ObservationIgnored private var heartRate: HeartRateMonitor?
    @ObservationIgnored private var locationSession: CLServiceSession?
    @ObservationIgnored private var locationTask: Task<Void, Never>?
    @ObservationIgnored private var pedometer: CMPedometer?
    @ObservationIgnored private var timer: Task<Void, Never>?
    /// For demo screenshots, which have no sensors: readings are set, and starting does nothing.
    @ObservationIgnored private var isFrozen = false
    /// Counts starts, so a second tap while the first start is still waiting wins alone.
    @ObservationIgnored private var starts = 0

    /// Every check that's running, so a run's start can stop them all.
    @ObservationIgnored private static var running: [ObjectIdentifier: SensorCheck] = [:]

    init(reads: @escaping () -> SensorSetup = { SensorSetup.current() }) {
        self.reads = reads
        setup = reads()
    }

    /// A check frozen at these readings, for screenshots.
    init(demo setup: SensorSetup, live: SensorLiveReadings = SensorLiveReadings(), mode: Mode = .test, elapsed: TimeInterval? = nil) {
        reads = { setup }
        self.setup = setup
        self.live = live
        self.mode = mode
        startedAt = elapsed.map { Date.now.addingTimeInterval(-$0) }
        isFrozen = true
    }

    var setupRows: [SensorRow] { SensorRules.setupRows(setup) }

    func liveRows(at date: Date = .now) -> [SensorRow] {
        SensorRules.liveRows(setup, live, elapsed: elapsed(at: date))
    }

    func chips(at date: Date = .now) -> [SensorChip] {
        SensorRules.chips(setup, live, elapsed: elapsed(at: date))
    }

    func readyProblem(at date: Date = .now) -> SensorRow? {
        SensorRules.readyProblem(setup, live, elapsed: elapsed(at: date))
    }

    /// Seconds into the running test, or how far the last one got.
    func elapsed(at date: Date = .now) -> TimeInterval {
        guard let startedAt else { return finishedAt == nil ? 0 : duration }
        return min(duration, max(0, date.timeIntervalSince(startedAt)))
    }

    /// Reads the switches and permissions again, such as when the app comes back from the Settings app.
    func refresh() {
        guard !isFrozen else { return }
        let old = setup
        setup = reads()
        if setup != old {
            Trace.log(.health, "Sensor check setup changed", Self.traceDetails(setup))
        }
    }

    // MARK: Live test

    /// Starts the live test, stopping any other check first, since only one workout session can run.
    func start(_ mode: Mode) {
        guard !isFrozen else { return }
        starts += 1
        let start = starts
        Task { await begin(mode, start: start) }
    }

    private func begin(_ mode: Mode, start: Int) async {
        await Self.stopAllAndWait()
        guard start == starts else { return }
        refresh()
        self.mode = mode
        live = SensorLiveReadings()
        finishedAt = nil
        let started = Date.now
        startedAt = started
        Self.running[ObjectIdentifier(self)] = self
        startHeartRate(at: started)
        startLocation(asking: mode == .test)
        if mode == .test || setup.stepsOn {
            startSteps(from: started)
        }
        Trace.log(.health, "Sensor check started", [
            "mode": mode.traceName,
            "heartRate": live.heartRate == .listening,
            "gps": live.gpsStarted,
            "steps": live.stepsStarted,
        ])
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(mode.duration))
            guard let self, !Task.isCancelled, self.startedAt == started else { return }
            self.finishedAt = .now
            self.stop()
        }
    }

    /// Stops everything the test started. The workout session ends straight away, though Health takes a
    /// moment to finish ending it: see `stopAndWait()`.
    func stop() {
        guard !isFrozen, startedAt != nil else { return }
        Trace.log(.health, "Sensor check stopped", ["mode": mode.traceName, "seconds": Int(elapsed()), "readings": live.readingCount > 0])
        startedAt = nil
        timer?.cancel()
        timer = nil
        heartRate?.stop()
        heartRate = nil
        locationTask?.cancel()
        locationTask = nil
        locationSession?.invalidate()
        locationSession = nil
        pedometer?.stopUpdates()
        pedometer = nil
        Self.running[ObjectIdentifier(self)] = nil
    }

    /// Stops the test and waits until Health has ended its workout session, so another can start.
    func stopAndWait() async {
        guard !isFrozen, startedAt != nil else { return }
        let monitor = heartRate
        heartRate = nil
        stop()
        await monitor?.stopAndWait()
    }

    /// Stops every running check. A run calls this as it starts.
    static func stopAll() {
        for check in running.values { check.stop() }
    }

    /// Stops every running check and waits until their workout sessions have ended.
    static func stopAllAndWait() async {
        for check in Array(running.values) { await check.stopAndWait() }
    }

    private func startHeartRate(at date: Date) {
        guard setup.heartRateOn, setup.health == .allowed else { return }
        let monitor = HeartRateMonitor()
        monitor.onReading = { [weak self, weak monitor] beatsPerMinute, _, source in
            guard let self, self.isRunning else { return }
            // That a reading came and what kind of device sent it, never the reading.
            let source = source ?? monitor?.source
            if self.live.readingCount == 0 || source != self.live.source {
                Trace.log(.heart, "Sensor check reading", ["source": source?.rawValue ?? "unknown"])
            }
            self.live.beatsPerMinute = beatsPerMinute
            self.live.source = source
            self.live.readingCount += 1
        }
        monitor.onEnded = { [weak self] in
            guard let self, self.isRunning else { return }
            Trace.log(.heart, "Sensor check session ended early")
            self.live.heartRate = .endedEarly
            self.heartRate = nil
        }
        // The session's workout is always discarded: nothing goes to Health, and no run is made.
        guard monitor.start(at: date, readsHeartRate: true) else {
            live.heartRate = .couldNotStart
            return
        }
        heartRate = monitor
        live.heartRate = .listening
    }

    private func startLocation(asking: Bool) {
        // Opening the Run tab never asks; the live test asks the way a first run does.
        guard setup.location == .allowed || (asking && setup.location == .notAsked) else { return }
        locationSession = CLServiceSession(authorization: .whenInUse)
        live.gpsStarted = true
        locationTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self, !Task.isCancelled, self.isRunning else { return }
                    if update.authorizationDenied || update.accuracyLimited || (update.location != nil && self.setup.location == .notAsked) {
                        self.refresh()
                    }
                    // Accuracy only. Where the fix is never leaves this line.
                    if let accuracy = update.location?.horizontalAccuracy {
                        self.live.gpsAccuracy = accuracy
                    }
                }
            } catch {
                Trace.error("Sensor check location", error)
            }
        }
    }

    private func startSteps(from date: Date) {
        guard setup.motionAvailable, setup.motionAllowed else { return }
        let pedometer = CMPedometer()
        pedometer.startUpdates(from: date) { @Sendable [weak self] data, _ in
            guard let steps = data?.numberOfSteps.intValue else { return }
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.live.steps = steps
            }
        }
        self.pedometer = pedometer
        live.stepsStarted = true
    }

    /// Switches and permissions for a trace line: no readings.
    static func traceDetails(_ setup: SensorSetup) -> KeyValuePairs<String, Any> {
        [
            "heartRate": setup.heartRateOn,
            "health": setup.health.rawValue,
            "location": setup.location.rawValue,
            "precise": setup.preciseLocation,
            "steps": setup.stepsOn,
            "motion": setup.motionAllowed ? "allowed" : (setup.motionDenied ? "denied" : "notAsked"),
            "barometer": setup.barometerAvailable,
            "watch": setup.watch?.rawValue ?? "unknown",
            "earbuds": setup.earbudsConnected,
        ]
    }
}

// MARK: - Reading the device

extension SensorSetup {
    /// The switches and permissions as they are now.
    static func current(defaults: UserDefaults = .standard) -> SensorSetup {
        let health = HealthSync.shared
        let healthAccess: HealthWorkoutAccess = if !health.isAvailable {
            .unavailable
        } else {
            switch health.access {
            case .allowed: .allowed
            case .denied: .denied
            case .notDetermined: .notAsked
            }
        }
        let manager = CLLocationManager()
        let location: LocationAccess = switch manager.authorizationStatus {
        case .notDetermined: .notAsked
        case .denied, .restricted: .denied
        default: .allowed
        }
        var setup = SensorSetup(
            heartRateOn: defaults.bool(forKey: HeartRateMonitor.storageKey),
            health: healthAccess,
            location: location,
            preciseLocation: manager.accuracyAuthorization == .fullAccuracy,
            stepsOn: defaults.bool(forKey: MotionMonitor.stepsKey),
            motionAvailable: MotionMonitor.isAvailable,
            motionAllowed: MotionMonitor.isAllowed,
            motionDenied: MotionMonitor.isDenied,
            barometerAvailable: AltimeterMonitor.isAvailable,
            earbudsConnected: Self.headphonesConnected
        )
        #if os(watchOS)
        setup.isWatch = true
        #else
        setup.watch = Self.watchState
        #endif
        return setup
    }

    /// Whether the audio goes to Bluetooth or wired headphones now, from the route's port kinds only. Device
    /// names are never read.
    static var headphonesConnected: Bool {
        let headphones: Set<AVAudioSession.Port> = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { headphones.contains($0.portType) }
    }

    #if os(iOS)
    /// The watch as WatchConnectivity last said, or nil before it has.
    static var watchState: WatchAppState? {
        guard WCSession.isSupported() else { return nil }
        let session = WCSession.default
        guard session.activationState == .activated else { return nil }
        if !session.isPaired { return .notPaired }
        return session.isWatchAppInstalled ? .installed : .appNotInstalled
    }
    #endif
}
