//
//  HeartRateMonitor.swift
//  Wind Run
//

import Foundation
import HealthKit
import Observation
import OSLog

/// Live heart rate for one run, from a HealthKit workout session.
///
/// While the session runs, HealthKit passes along heart rate from whatever the runner wears:
/// Apple Watch, AirPods Pro 3, Powerbeats Pro 2, or a Bluetooth strap paired in Settings.
/// On the watch, the session also keeps the app running when the wrist goes down.
///
/// Each reading is tagged with what measured it, found from Health's own records of the run's
/// readings, so the runner never picks a source. See `HeartRateSource`.
///
/// The session's own workout is always discarded. Readings go to the run in the local store,
/// and only "Save runs to Health" puts a run in Apple Health, so a run is never saved twice.
///
/// On the watch a run without heart rate still has a session, started with `readsHeartRate` off: only a
/// workout session keeps a watch app running with the wrist down. It passes on no readings.
@Observable
final class HeartRateMonitor {
    /// Whether the runner turned heart rate on. Off until they do.
    static let storageKey = "heartRateEnabled"

    private static let store = HKHealthStore()

    /// A reading older than this is no reading: the strap was taken off, the earbuds came out, or the
    /// watch lost touch with the skin.
    static let readingFreshness: TimeInterval = 15

    /// The newest reading in beats per minute, or nil until one arrives. It isn't cleared when readings
    /// stop, so screens use `beatsPerMinute(at:)`.
    private(set) var beatsPerMinute: Double?
    /// When the newest reading was taken.
    private(set) var readingDate: Date?
    /// Whether this session passes on heart rate, or only keeps the watch app running.
    private(set) var readsHeartRate = true
    /// True once the system ended the session before the run did, such as when another workout app
    /// started: heart rate has stopped for the rest of the run.
    private(set) var endedEarly = false
    /// The newest running power, in watts. Only Apple Watch measures it, so it stays nil on iPhone.
    private(set) var runningPower: Double?

    /// What's measuring heart rate now: the best source with a reading in the last minute of readings,
    /// or nil until one is found. On the watch it's the watch until a strap's readings turn up.
    private(set) var source: HeartRateSource?

    /// Called on the main actor with each new reading and what measured it, if that's known yet.
    @ObservationIgnored var onReading: ((_ beatsPerMinute: Double, _ date: Date, _ source: HeartRateSource?) -> Void)?
    /// Called on the main actor with each new step count and the time it covers.
    @ObservationIgnored var onSteps: ((_ count: Double, _ interval: DateInterval) -> Void)?
    /// Called on the main actor with the distance the session has worked out so far, in meters.
    @ObservationIgnored var onDistance: ((_ meters: Double) -> Void)?
    /// Called on the main actor the first time each device measuring heart rate is seen.
    @ObservationIgnored var onDevice: ((_ device: DeviceInfo) -> Void)?
    /// Called on the main actor when the system ends the session while the run is still going.
    @ObservationIgnored var onEnded: (() -> Void)?

    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    // The session and builder hold their delegate weakly.
    @ObservationIgnored private var delegate: WorkoutSessionDelegate?
    /// Watches Health for the run's readings, to see what measured them.
    @ObservationIgnored private var sourceQuery: HKAnchoredObjectQuery?
    /// The newest reading seen from each source.
    @ObservationIgnored private var lastSeen: [HeartRateSource: Date] = [:]
    /// Health's records of the last couple of minutes of readings, to match each live reading to what
    /// measured it.
    @ObservationIgnored private var recentSamples: [HeartRateSourceSample] = []
    /// The last couple of minutes of live readings, to match Health's records to as they come in.
    @ObservationIgnored private var recentReadings: [(date: Date, beatsPerMinute: Double)] = []
    /// The source whose records last matched a live reading, and when.
    @ObservationIgnored private var matched: (source: HeartRateSource, date: Date)?
    /// A live reading and Health's record of it are this close in time when they're the same reading.
    static let matchWindow: TimeInterval = 3
    /// How far back readings and records are kept for matching.
    private static let matchHistory: TimeInterval = 120
    /// The devices already passed to `onDevice`.
    @ObservationIgnored private var devicesSeen: Set<DeviceInfo> = []
    /// A source with no reading for this long before the newest one has dropped out.
    static let sourceWindow: TimeInterval = 60

    /// Asks Health for what a workout session needs: sharing workouts and reading heart rate, and for
    /// the coach: step count, to check heart rate isn't locked to step rate, and resting heart rate for
    /// the morning check. Walking and running distance lets the run keep Apple's own distance beside
    /// Wind Run's. All are read on the device only.
    ///
    /// A session can run once workouts are allowed. Health never says whether reading was
    /// allowed, so heart rate can still come up empty.
    static func requestAccess() async -> HealthSync.Access {
        guard HKHealthStore.isHealthDataAvailable() else { return .denied }
        do {
            try await store.requestAuthorization(
                toShare: [HKObjectType.workoutType()],
                read: Set<HKObjectType>([
                    HKQuantityType(.heartRate),
                    HKQuantityType(.stepCount),
                    HKQuantityType(.restingHeartRate),
                    HKQuantityType(.distanceWalkingRunning),
                    HKQuantityType(.runningPower),
                ])
                    .union(HealthSync.readTypes)
            )
        } catch {
            Logger.health.error("Heart rate permission request failed: \(error)")
        }
        return HealthSync.shared.access
    }

    /// Asks Health only for what a workout session needs, sharing workouts, for a watch run without heart
    /// rate. Health shows its sheet only if it hasn't asked about workouts yet.
    static func requestSessionAccess() async -> HealthSync.Access {
        guard HKHealthStore.isHealthDataAvailable() else { return .denied }
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
        } catch {
            Logger.health.error("Workout permission request failed: \(error)")
        }
        return HealthSync.shared.access
    }

    /// With heart rate on, asks Health about anything Wind Run has started reading since heart rate was
    /// turned on, such as walking and running distance. Health shows its sheet only for what it hasn't
    /// asked about yet, so most launches show nothing.
    static func askForNewAccessIfOn(defaults: UserDefaults = .standard) async {
        guard defaults.bool(forKey: storageKey) else { return }
        _ = await requestAccess()
    }

    /// Turns the Heart rate setting on and asks Health for access, turning it back off
    /// if Health doesn't allow workouts.
    @discardableResult
    static func turnOn(defaults: UserDefaults = .standard) async -> HealthSync.Access {
        defaults.set(true, forKey: storageKey)
        let access = await requestAccess()
        if access == .denied {
            defaults.set(false, forKey: storageKey)
        }
        return access
    }

    /// The newest reading, or nil when there's none from the last `readingFreshness` seconds, so a sensor
    /// that drops out shows as no reading instead of its last number.
    func beatsPerMinute(at date: Date) -> Double? {
        guard let beatsPerMinute, let readingDate, date.timeIntervalSince(readingDate) <= Self.readingFreshness else { return nil }
        return beatsPerMinute
    }

    /// Starts the workout session. With `readsHeartRate` off it passes on no readings, and only keeps the
    /// watch app running with the wrist down. Returns false if it couldn't start.
    @discardableResult
    func start(at date: Date, readsHeartRate: Bool = true) -> Bool {
        guard session == nil else {
            Logger.health.warning("A workout session is already running.")
            return false
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            Logger.health.info("Health isn't available on this device.")
            return false
        }

        let session: HKWorkoutSession
        do {
            session = try HKWorkoutSession(healthStore: Self.store, configuration: Self.configuration)
        } catch {
            Logger.health.error("Couldn't create a workout session: \(error)")
            return false
        }
        attach(session, readsHeartRate: readsHeartRate, from: date)

        session.startActivity(with: date)
        let builder = session.associatedWorkoutBuilder()
        Task {
            do {
                try await builder.beginCollection(at: date)
            } catch {
                Logger.health.error("Couldn't start collecting heart rate: \(error)")
            }
        }
        return true
    }

    #if os(watchOS)
    /// Takes over the session watchOS kept going after the app was closed mid-run, so the run carries on
    /// with it. The session is already running and collecting.
    func recover(_ session: HKWorkoutSession, readsHeartRate: Bool) {
        guard self.session == nil else { return }
        attach(session, readsHeartRate: readsHeartRate, from: session.startDate ?? .now)
        Trace.log(.heart, "Recovered workout session", ["state": session.state.traceName, "readsHeartRate": readsHeartRate])
    }

    /// Asks Health for the session watchOS kept going after the app was closed mid-run. Nil when there's none.
    static func recoverSession() async -> HKWorkoutSession? {
        do {
            return try await store.recoverActiveWorkoutSession()
        } catch {
            Logger.health.error("Couldn't recover the workout session: \(error)")
            return nil
        }
    }
    #endif

    private static var configuration: HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = .outdoor
        return configuration
    }

    /// Hooks a new or recovered session up to its builder and to this monitor.
    private func attach(_ session: HKWorkoutSession, readsHeartRate: Bool, from date: Date) {
        let builder = session.associatedWorkoutBuilder()
        let dataSource = HKLiveWorkoutDataSource(healthStore: Self.store, workoutConfiguration: session.workoutConfiguration)
        // Step count isn't always collected for a run by default; the coach compares it with heart rate.
        dataSource.enableCollection(for: HKQuantityType(.stepCount), predicate: nil)
        // Collected for a run by default; asked for anyway, since the run keeps it beside its own distance.
        dataSource.enableCollection(for: HKQuantityType(.distanceWalkingRunning), predicate: nil)
        builder.dataSource = dataSource

        let delegate = WorkoutSessionDelegate(
            onReading: { [weak self] beatsPerMinute, date in
                self?.receive(beatsPerMinute, at: date)
            },
            onSteps: { [weak self] count, interval in
                self?.onSteps?(count, interval)
            },
            onDistance: { [weak self] meters in
                self?.onDistance?(meters)
            },
            onPower: { [weak self] watts in
                guard self?.readsHeartRate == true else { return }
                self?.runningPower = watts
            },
            onStateChange: { [weak self] state, old in
                self?.stateChanged(to: state, from: old)
            },
            onFailure: { [weak self] in
                Logger.health.error("Workout session failed")
                self?.tearDown()
            }
        )
        session.delegate = delegate
        builder.delegate = delegate
        self.session = session
        self.builder = builder
        self.delegate = delegate
        self.readsHeartRate = readsHeartRate
        endedEarly = false

        guard readsHeartRate else { return }
        #if os(watchOS)
        source = .appleWatch
        #endif
        startSourceQuery(from: date)
    }

    /// The system ended the session before the run did, such as when the runner started another workout
    /// app: heart rate stops, and on the watch the app can no longer run with the wrist down.
    private func stateChanged(to state: HKWorkoutSessionState, from old: HKWorkoutSessionState) {
        Trace.log(.heart, "Session state", ["from": old.traceName, "to": state.traceName])
        guard session != nil, state == .ended || state == .stopped else { return }
        Logger.health.info("The workout session ended before the run did.")
        builder?.discardWorkout()
        if state == .stopped {
            session?.end()
        }
        tearDown()
        endedEarly = true
        onEnded?()
    }

    func pause() {
        session?.pause()
    }

    func resume() {
        session?.resume()
    }

    /// Ends the session and throws its workout away, passing on its distance one last time first.
    func stop() {
        guard let session, let builder else { return }
        if let meters = builder.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()) {
            onDistance?(meters)
        }
        builder.discardWorkout()
        session.end()
        tearDown()
    }

    private func receive(_ beatsPerMinute: Double, at date: Date) {
        guard readsHeartRate else { return }
        self.beatsPerMinute = beatsPerMinute
        readingDate = date
        recentReadings.append((date, beatsPerMinute))
        recentReadings.removeAll { date.timeIntervalSince($0.date) > Self.matchHistory }
        // Tagged with what Health says measured this very reading when its record is in already, otherwise
        // with what's measuring now.
        let measuredBy = Self.match(beatsPerMinute, at: date, in: recentSamples) ?? source
        onReading?(beatsPerMinute, date, measuredBy)
    }

    /// The source of Health's record of a reading of `beatsPerMinute` at `date`. When two sources match,
    /// the better-ranked one.
    static func match(_ beatsPerMinute: Double, at date: Date, in samples: [HeartRateSourceSample]) -> HeartRateSource? {
        let matches = samples.filter {
            abs($0.date.timeIntervalSince(date)) <= matchWindow && abs($0.beatsPerMinute - beatsPerMinute) < 0.5
        }
        return HeartRateSource.best(matches.map(\.source))
    }

    /// Reads the run's heart rate from Health as it's saved, only for what measured it. The live
    /// readings themselves still come from the workout builder, which is quicker.
    private func startSourceQuery(from date: Date) {
        let handler = Self.sourceHandler { [weak self] found in
            self?.saw(found)
        }
        let query = HKAnchoredObjectQuery(
            type: HKQuantityType(.heartRate),
            predicate: HKQuery.predicateForSamples(withStart: date, end: nil, options: .strictStartDate),
            anchor: nil,
            limit: HKObjectQueryNoLimit,
            resultsHandler: handler
        )
        query.updateHandler = handler
        Self.store.execute(query)
        sourceQuery = query
    }

    /// HealthKit calls the query's handlers on its own queue; `deliver` runs on the main actor.
    private nonisolated static func sourceHandler(
        _ deliver: @escaping @MainActor ([HeartRateSourceSample]) -> Void
    ) -> @Sendable (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, (any Error)?) -> Void {
        { _, samples, _, _, error in
            if let error {
                // Such as heart rate reading not allowed: the source then stays unknown.
                Trace.error("Heart rate source query", error)
            }
            let unit = HKUnit.count().unitDivided(by: .minute())
            let found = (samples ?? []).compactMap { sample -> HeartRateSourceSample? in
                guard let source = HeartRateSource(sample) else { return nil }
                return HeartRateSourceSample(
                    source: source,
                    date: sample.endDate,
                    beatsPerMinute: (sample as? HKQuantitySample)?.quantity.doubleValue(for: unit) ?? 0,
                    device: DeviceInfo(heartRateSample: sample)
                )
            }
            guard !found.isEmpty else { return }
            Task { @MainActor in deliver(found) }
        }
    }

    /// What's measuring now: the source whose records match the live readings, so a watch's readings synced
    /// to the iPhone don't take over from the earbuds actually measuring. Until records match, the best
    /// source among those with a reading within `sourceWindow` of the newest one, so a strap that drops out
    /// hands over to the watch or earbuds.
    private func saw(_ found: [HeartRateSourceSample]) {
        guard sourceQuery != nil else { return }
        for reading in found {
            lastSeen[reading.source] = max(lastSeen[reading.source] ?? reading.date, reading.date)
            if let device = reading.device, devicesSeen.insert(device).inserted {
                onDevice?(device)
            }
            let live = recentReadings.filter {
                abs($0.date.timeIntervalSince(reading.date)) <= Self.matchWindow && abs($0.beatsPerMinute - reading.beatsPerMinute) < 0.5
            }
            if let date = live.map(\.date).max(), date >= (matched?.date ?? .distantPast) {
                // Two sources matching the same reading: the better-ranked one.
                if date == matched?.date, let current = matched?.source {
                    matched = (HeartRateSource.best([current, reading.source]) ?? reading.source, date)
                } else {
                    matched = (reading.source, date)
                }
            }
        }
        recentSamples.append(contentsOf: found)
        if let newest = recentSamples.map(\.date).max() {
            recentSamples.removeAll { newest.timeIntervalSince($0.date) > Self.matchHistory }
        }
        guard let newest = lastSeen.values.max() else { return }
        let old = source
        if let matched, newest.timeIntervalSince(matched.date) <= Self.sourceWindow {
            source = matched.source
        } else {
            let current = lastSeen.filter { newest.timeIntervalSince($0.value) <= Self.sourceWindow }.keys
            source = HeartRateSource.best(current) ?? source
        }
        if source != old {
            Trace.log(.heart, "Source changed", ["from": old?.rawValue ?? "none", "to": source?.rawValue ?? "none", "sourcesSeen": lastSeen.count])
        }
    }

    private func tearDown() {
        if let sourceQuery {
            Self.store.stop(sourceQuery)
        }
        sourceQuery = nil
        lastSeen = [:]
        devicesSeen = []
        recentSamples = []
        recentReadings = []
        matched = nil
        source = nil
        session = nil
        builder = nil
        delegate = nil
        beatsPerMinute = nil
        readingDate = nil
        runningPower = nil
    }
}

/// Health's record of one heart-rate reading: what measured it, when, and its value.
nonisolated struct HeartRateSourceSample: Sendable {
    let source: HeartRateSource
    let date: Date
    let beatsPerMinute: Double
    let device: DeviceInfo?
}

extension HKWorkoutSessionState {
    /// The state's name, for trace lines.
    nonisolated var traceName: String {
        switch self {
        case .notStarted: "notStarted"
        case .prepared: "prepared"
        case .running: "running"
        case .paused: "paused"
        case .stopped: "stopped"
        case .ended: "ended"
        @unknown default: "\(rawValue)"
        }
    }
}

/// Hears from HealthKit on its own queues and hands what matters to the main actor.
private nonisolated final class WorkoutSessionDelegate: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    private let onReading: @MainActor (Double, Date) -> Void
    private let onSteps: @MainActor (Double, DateInterval) -> Void
    private let onDistance: @MainActor (Double) -> Void
    private let onPower: @MainActor (Double) -> Void
    private let onStateChange: @MainActor (HKWorkoutSessionState, HKWorkoutSessionState) -> Void
    private let onFailure: @MainActor () -> Void

    init(
        onReading: @escaping @MainActor (Double, Date) -> Void,
        onSteps: @escaping @MainActor (Double, DateInterval) -> Void,
        onDistance: @escaping @MainActor (Double) -> Void,
        onPower: @escaping @MainActor (Double) -> Void,
        onStateChange: @escaping @MainActor (HKWorkoutSessionState, HKWorkoutSessionState) -> Void,
        onFailure: @escaping @MainActor () -> Void
    ) {
        self.onReading = onReading
        self.onSteps = onSteps
        self.onDistance = onDistance
        self.onPower = onPower
        self.onStateChange = onStateChange
        self.onFailure = onFailure
        super.init()
    }

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let stepCount = HKQuantityType(.stepCount)
        if collectedTypes.contains(stepCount),
           let statistics = workoutBuilder.statistics(for: stepCount),
           let quantity = statistics.mostRecentQuantity(),
           let interval = statistics.mostRecentQuantityDateInterval() {
            let count = quantity.doubleValue(for: .count())
            let onSteps = onSteps
            Task { @MainActor in onSteps(count, interval) }
        }
        let distance = HKQuantityType(.distanceWalkingRunning)
        if collectedTypes.contains(distance),
           let meters = workoutBuilder.statistics(for: distance)?.sumQuantity()?.doubleValue(for: .meter()) {
            let onDistance = onDistance
            Task { @MainActor in onDistance(meters) }
        }
        let power = HKQuantityType(.runningPower)
        if collectedTypes.contains(power),
           let watts = workoutBuilder.statistics(for: power)?.mostRecentQuantity()?.doubleValue(for: .watt()) {
            let onPower = onPower
            Task { @MainActor in onPower(watts) }
        }
        let heartRate = HKQuantityType(.heartRate)
        guard collectedTypes.contains(heartRate),
              let statistics = workoutBuilder.statistics(for: heartRate),
              let quantity = statistics.mostRecentQuantity(),
              let interval = statistics.mostRecentQuantityDateInterval()
        else { return }
        let beatsPerMinute = quantity.doubleValue(for: .count().unitDivided(by: .minute()))
        let date = interval.end
        let onReading = onReading
        Task { @MainActor in onReading(beatsPerMinute, date) }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        let onStateChange = onStateChange
        Task { @MainActor in onStateChange(toState, fromState) }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {
        // Domain and code only, here where the error is, since it can't be passed to the main actor.
        Trace.error("Workout session failed", error)
        let onFailure = onFailure
        Task { @MainActor in onFailure() }
    }
}
