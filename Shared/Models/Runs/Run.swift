//
//  Run.swift
//  Wind Run
//

import CoreLocation
import Foundation
import OSLog
import SwiftData

/// How a run was started: a plain run, one of the runner's own workouts, or a coach session. `intervals` is
/// the stored name from when those were all interval workouts.
enum RunKind: String, Codable, CaseIterable {
    case free
    case intervals
    case coached

    var name: String {
        switch self {
        case .free: "Run"
        case .intervals: "Workout"
        case .coached: "Coach"
        }
    }
}

enum RunStatus: String, Codable {
    case active
    case paused
    case complete
    case discarded
}

/// One recorded run, with its GPS route, heart rate, and the pauses taken along the way.
@Model
final class Run {
    var startDateValue: Date = Date.now
    var endDateValue: Date?
    /// Older stores have no sport and describe running workouts.
    var workoutTypeValue: String?
    var sport: WorkoutSport { WorkoutSport(stored: workoutTypeValue) }

    var kindValue: RunKind = RunKind.free
    var statusValue: RunStatus = RunStatus.active
    /// Distance covered while running, in meters. Pauses don't add to it. Measured as
    /// `distanceMethodValue` says.
    var distanceMetersValue: Double = 0
    /// How `distanceMetersValue` was measured: `DistanceEstimator.method` for runs recorded since it
    /// came in, and for runs first measured by reported speed ("speed-v1"), which are measured again. Nil
    /// for older runs, which added up the straight lines between fixes.
    var distanceMethodValue: String?
    /// The straight lines between fixes while running, the way older runs were measured, kept so the
    /// two can be compared. Nil for runs recorded before it was kept.
    var gpsTrackMetersValue: Double?
    /// The distance Apple's workout session worked out for the run, in meters. Nil when no session ran
    /// (heart rate off, or Health not allowed) or it gave no distance.
    var appleDistanceMetersValue: Double?
    /// The devices that recorded the run and measured its heart rate, with their versions, as JSON
    /// (`RunDevices`). Nil for runs recorded before it was kept.
    var devicesDataValue: Data?
    /// What was set up and what started when the run was recorded, as JSON (`RunSensorReport`): switches,
    /// permissions and kinds of connection, never readings, names or places. Nil for runs recorded before it
    /// was kept.
    var sensorReportDataValue: Data?
    var notesValue: String = ""
    /// The Apple Health workout this run was saved as. Nil when it wasn't saved there.
    var healthWorkoutIDValue: UUID?
    /// A stable id the coach refers to the run by.
    var runIDValue: UUID = UUID()
    /// The runner's answers after the run (how hard it felt and so on), as the coach's JSON.
    var checkInDataValue: Data?
    /// For a structured run, each step as it was actually run, as JSON.
    var stepLogDataValue: Data?
    /// Step counts from the run's workout session, for the coach's step-rate check, as JSON.
    var stepCountDataValue: Data?
    /// The barometer's climb and drop through the run, as JSON. Nil when it had no barometer.
    var altitudeDataValue: Data?
    /// Calories burned, in kilocalories, worked out when the run finished from its climb, pace and the
    /// runner's weight then. Nil when no weight was given.
    var activeCaloriesValue: Double?
    /// The weather during the run from Apple Weather, as JSON (`RunWeather`): readings only, no place. Nil
    /// until it's fetched, and for runs with Weather for Runs off.
    var weatherDataValue: Data?
    /// For a distance run, how far the runner set out to go, in meters. Nil for other runs.
    var goalMetersValue: Double?
    /// For a timed run, how long the runner set out to go, in seconds. Nil for other runs.
    var goalSecondsValue: Double?
    /// The time zone the run started in, as an identifier such as "America/Los_Angeles", so its start time
    /// reads the same wherever the runner is later. Nil for runs recorded before it was kept: those read the
    /// device's current time zone.
    var timeZoneIdentifierValue: String?

    /// The finished run's whole route packed into one piece of data (`PackedRoute`), so it's read and synced
    /// in one go rather than fix by fix. Nil while the run is going, and for a run not packed yet: those read
    /// `routeSamplesValue`, which is still kept for now so older versions of the app can read the route.
    /// Stored as its own file, which iCloud syncs as one asset.
    @Attribute(.externalStorage) var routeDataValue: Data?
    /// How many fixes `routeDataValue` holds, or nil when it holds none. Kept beside it so finding the runs
    /// still to pack doesn't load every packed route.
    var routePackedCountValue: Int?

    // To-many relationships are optional because iCloud sync requires it.
    @Relationship(deleteRule: .cascade, inverse: \RouteSample.runValue)
    var routeSamplesValue: [RouteSample]? = []

    @Relationship(deleteRule: .cascade, inverse: \RunPause.runValue)
    var pausesValue: [RunPause]? = []

    /// Empty unless heart rate was on for this run. Optional so iCloud sync can mirror it.
    @Relationship(deleteRule: .cascade, inverse: \HeartRateSample.runValue)
    var heartRateSamplesValue: [HeartRateSample]? = []

    /// The interval workout this run followed, if any. Deleting the plan keeps the run.
    @Relationship(deleteRule: .nullify)
    var intervalPlanValue: IntervalPlan?

    /// The coach session this run fulfilled, if any.
    @Relationship(deleteRule: .nullify)
    var coachWorkoutValue: CoachWorkout?

    /// The newest fix, cached so recording doesn't re-sort the whole route every second.
    @Transient private var lastSample: RouteSample? = nil
    @Transient private var lastHeartRateSample: HeartRateSample? = nil
    /// Measures distance as fixes arrive. Rebuilt from the newest fix if the app was closed mid-run.
    @Transient private var distanceEstimator: DistanceEstimator? = nil
    /// Fixes and heart rate readings that arrived out of order and were dropped, for the trace at the finish.
    @Transient private var droppedOutOfOrder: Int = 0

    init(kind: RunKind = .free, sport: WorkoutSport = .running, startDate: Date = .now) {
        self.kindValue = kind
        self.workoutTypeValue = sport.rawValue
        self.startDateValue = startDate
        self.statusValue = .active
        self.distanceMethodValue = DistanceEstimator.method
        self.gpsTrackMetersValue = 0
        self.timeZoneIdentifierValue = TimeZone.current.identifier
    }
}

// MARK: - Accessors

extension Run {
    var startDate: Date { startDateValue }
    /// The time zone the run started in, or the device's current one for a run recorded before it was kept.
    var timeZone: TimeZone { timeZoneIdentifierValue.flatMap(TimeZone.init(identifier:)) ?? .current }
    /// The stored time zone only, nil for a run recorded before it was kept.
    var recordedTimeZone: TimeZone? { timeZoneIdentifierValue.flatMap(TimeZone.init(identifier:)) }
    var endDate: Date? { endDateValue }
    var kind: RunKind { kindValue }
    var status: RunStatus { statusValue }
    var distanceMeters: Double { distanceMetersValue }
    var distanceMethod: String? { distanceMethodValue }
    var gpsTrackMeters: Double? { gpsTrackMetersValue }
    var appleDistanceMeters: Double? { appleDistanceMetersValue }

    /// The devices behind the run, or nil for runs recorded before they were kept.
    var devices: RunDevices? {
        Self.decodedJSON(RunDevices.self, from: devicesDataValue)
    }

    var notes: String {
        get { notesValue }
        set { notesValue = newValue }
    }

    var intervalPlan: IntervalPlan? { intervalPlanValue }

    /// The distance or time the runner set out to run, or nil when they didn't pick one.
    var goal: RunGoal? {
        get {
            if let goalMetersValue, goalMetersValue > 0 { return .distance(meters: goalMetersValue) }
            if let goalSecondsValue, goalSecondsValue > 0 { return .time(seconds: goalSecondsValue) }
            return nil
        }
        set {
            switch newValue {
            case .distance(let meters):
                goalMetersValue = meters
                goalSecondsValue = nil
            case .time(let seconds):
                goalMetersValue = nil
                goalSecondsValue = seconds
            case nil:
                goalMetersValue = nil
                goalSecondsValue = nil
            }
        }
    }
    var coachWorkout: CoachWorkout? { coachWorkoutValue }
    var healthWorkoutID: UUID? { healthWorkoutIDValue }
    var runID: UUID { runIDValue }
    var checkInData: Data? { checkInDataValue }

    /// The route in the order it was recorded.
    var route: [RouteSample] {
        (routeSamplesValue ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    /// The route in the order it was recorded, each fix read out of the store once. Much quicker than
    /// `route` for walking a long run, since every read of a stored fix goes through SwiftData.
    var routeReadings: [RouteReading] {
        if let packed = packedRoute { return packed }
        return sampleReadings
    }

    /// The packed route, or nil when the run hasn't been packed or the data can't be read.
    var packedRoute: [RouteReading]? {
        guard routePackedCountValue != nil, let routeDataValue else { return nil }
        return PackedRoute.decode(routeDataValue)
    }

    /// The fixes from their own records, in order, each read once.
    var sampleReadings: [RouteReading] {
        var readings = (routeSamplesValue ?? []).map(RouteReading.init)
        readings.sort { $0.timestamp < $1.timestamp }
        return readings
    }

    /// Whether the finished run's route has been packed into `routeDataValue`.
    var hasPackedRoute: Bool { routePackedCountValue != nil }

    /// Packs a finished run's route into one piece of data, from the fixes given or from its own records.
    /// A run still going, or without fixes, is left as it is.
    func packRoute(_ readings: [RouteReading]? = nil) {
        guard status == .complete else { return }
        let readings = readings ?? sampleReadings
        guard let data = PackedRoute.encode(readings) else { return }
        routeDataValue = data
        routePackedCountValue = readings.count
    }

    /// Where the run started: its first fix with a usable coordinate. Reads each fix's time once, and its
    /// place only when it's the earliest yet.
    var startLocation: CLLocation? {
        if let packed = packedRoute { return Self.startLocation(in: packed) }
        var first: (date: Date, sample: RouteSample)?
        for sample in routeSamplesValue ?? [] {
            let date = sample.timestampValue
            if let first, first.date <= date { continue }
            guard CLLocationCoordinate2DIsValid(sample.coordinate) else { continue }
            first = (date, sample)
        }
        return first?.sample.location
    }

    /// The same, from fixes already read in order.
    static func startLocation(in readings: [RouteReading]) -> CLLocation? {
        readings.first { CLLocationCoordinate2DIsValid($0.coordinate) }?.location
    }

    /// The pauses as plain dates, for working out running time at many moments without reading the store
    /// each time.
    var pauseClock: PauseClock {
        PauseClock(start: startDateValue, pauses: (pausesValue ?? []).map { ($0.startDateValue, $0.endDateValue) })
    }

    /// Heart rate readings in the order they were taken, each read out of the store once.
    var heartRateReadings: [(timestamp: Date, beatsPerMinute: Double)] {
        var readings = (heartRateSamplesValue ?? []).map { (timestamp: $0.timestampValue, beatsPerMinute: $0.beatsPerMinuteValue) }
        readings.sort { $0.timestamp < $1.timestamp }
        return readings
    }

    var pauses: [RunPause] {
        (pausesValue ?? []).sorted { $0.startDate < $1.startDate }
    }

    /// Heart rate readings in the order they were taken.
    var heartRateSamples: [HeartRateSample] {
        (heartRateSamplesValue ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    /// Heart rate is still climbing from near resting for the first minutes of a run, so the stats leave
    /// those out.
    static let heartRateSettlingTime: TimeInterval = 5 * 60

    /// Lowest, highest, mean and variance of the readings after the first five minutes of running, or of
    /// every reading when the run had none after that. Nil if there are none.
    var heartRateStats: HeartRateStats? {
        Self.heartRateStats(of: heartRateTimeline)
    }

    /// The same, from a timeline already worked out, so a page that charts it doesn't build it twice.
    static func heartRateStats(of timeline: [HeartRatePoint]) -> HeartRateStats? {
        let settled = timeline.filter { $0.activeTime >= heartRateSettlingTime }
        return HeartRateStats((settled.isEmpty ? timeline : settled).map(\.beatsPerMinute))
    }

    /// Each reading against time spent running, for charting the whole run.
    var heartRateTimeline: [HeartRatePoint] {
        let clock = pauseClock
        return heartRateReadings.map { HeartRatePoint(activeTime: clock.activeTime(at: $0.timestamp), beatsPerMinute: $0.beatsPerMinute) }
    }

    func heartRatePoint(_ sample: HeartRateSample) -> HeartRatePoint {
        HeartRatePoint(activeTime: activeTime(at: sample.timestamp), beatsPerMinute: sample.beatsPerMinute)
    }

    /// When the run last recorded a GPS fix or heart rate reading, or nil if it never did.
    var lastRecordedDate: Date? {
        let lastFix = routeSamplesValue?.map(\.timestamp).max()
        let lastReading = heartRateSamplesValue?.map(\.timestamp).max()
        return [lastFix, lastReading].compactMap { $0 }.max()
    }

    var isFinished: Bool {
        status == .complete || status == .discarded
    }

    /// Time spent running, leaving out pauses.
    func activeDuration(at now: Date = .now) -> TimeInterval {
        activeTime(at: endDate ?? now)
    }

    /// The moment the run's clock read 0:00, counting only running time, so a clock that ticks from it lands
    /// on the run's seconds. The iPhone, the Watch and the Lock Screen all count from it.
    func clockStart(at now: Date = .now) -> Date {
        now.addingTimeInterval(-activeDuration(at: now))
    }

    /// Time spent running from the start up to `date`, leaving out the pauses before it.
    func activeTime(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSince(startDate) - pausedTime(at: date))
    }

    /// Time spent paused, by the runner or at a stop, up to `date`.
    func pausedTime(at date: Date) -> TimeInterval {
        (pausesValue ?? []).reduce(0) { $0 + $1.duration(at: date) }
    }

    /// Time spent paused in the whole run.
    func pausedDuration(at now: Date = .now) -> TimeInterval {
        pausedTime(at: endDate ?? now)
    }

    /// Seconds per kilometer, or nil until there's enough distance to say.
    func pace(at now: Date = .now) -> TimeInterval? {
        guard distanceMeters >= 10 else { return nil }
        return activeDuration(at: now) / (distanceMeters / 1000)
    }
}

// MARK: - Stored JSON

extension Run {
    /// A value kept as JSON in one of the run's data fields, or nil when there's none or it doesn't decode.
    static func decodedJSON<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    /// A list as JSON for one of the run's data fields, or nil for an empty one, so nothing is stored for it.
    static func encodedJSONUnlessEmpty<T: Encodable & Collection>(_ value: T) -> Data? {
        value.isEmpty ? nil : try? JSONEncoder().encode(value)
    }
}

// MARK: - Lifecycle

extension Run {
    func pause(at date: Date = .now) {
        guard status == .active else {
            Logger.run.warning("Can only pause an active run.")
            Trace.log(.run, "Ignored pause", ["status": status.rawValue])
            return
        }
        statusValue = .paused
        pausesValue = (pausesValue ?? []) + [RunPause(startDate: date)]
    }

    func resume(at date: Date = .now) {
        guard status == .paused else {
            Logger.run.warning("Can only resume a paused run.")
            Trace.log(.run, "Ignored resume", ["status": status.rawValue])
            return
        }
        pausesValue?.first { $0.endDate == nil }?.end(at: date)
        statusValue = .active
    }

    func finish(at date: Date = .now) {
        guard !isFinished else {
            Logger.run.warning("Run is already finished.")
            Trace.log(.run, "Ignored finish", ["status": status.rawValue])
            return
        }
        pausesValue?.first { $0.endDate == nil }?.end(at: date)
        endDateValue = date
        statusValue = .complete
        // Every fix is in by now: recording stops at the finish.
        packRoute()
        Logger.run.debug("Finished run")
        if droppedOutOfOrder > 0 {
            Trace.log(.run, "Out-of-order readings dropped", ["count": droppedOutOfOrder])
        }
    }

    func discard(at date: Date = .now) {
        guard !isFinished else {
            Logger.run.warning("Run is already finished.")
            Trace.log(.run, "Ignored discard", ["status": status.rawValue])
            return
        }
        endDateValue = date
        statusValue = .discarded
    }

    /// Stores the runner's after-run answers for the coach.
    func saveCheckIn(_ data: Data?) {
        checkInDataValue = data
    }

    /// Each step of a structured run as it was run, in order. Empty for other runs.
    var stepLog: [RecordedStep] {
        Self.decodedJSON([RecordedStep].self, from: stepLogDataValue) ?? []
    }

    func saveStepLog(_ steps: [RecordedStep]) {
        stepLogDataValue = Self.encodedJSONUnlessEmpty(steps)
    }

    /// The step counts collected during the run, in order.
    var stepCounts: [StepCountSample] {
        Self.decodedJSON([StepCountSample].self, from: stepCountDataValue) ?? []
    }

    func saveStepCounts(_ samples: [StepCountSample]) {
        stepCountDataValue = Self.encodedJSONUnlessEmpty(samples)
    }

    /// Steps taken while running, or nil when none were counted.
    var stepTotal: Double? {
        let counts = stepCounts
        return counts.isEmpty ? nil : counts.reduce(0) { $0 + $1.count }
    }

    /// Mean steps a minute over the time spent running, or nil when no steps were counted.
    var meanCadence: Double? {
        let seconds = activeDuration()
        guard let stepTotal, seconds > 0 else { return nil }
        return stepTotal / seconds * 60
    }

    /// Remembers the Health workout a finished run was saved as.
    func markSavedToHealth(as workoutID: UUID) {
        guard status == .complete else {
            Logger.run.warning("Only a completed run can be saved to Health.")
            return
        }
        healthWorkoutIDValue = workoutID
    }

    /// Adds a GPS fix. Distance only grows while the run is active, so a paused walk
    /// back to the start doesn't count. `DistanceEstimator` says how much each fix adds.
    func record(_ sample: RouteSample) {
        guard !isFinished else {
            Logger.run.warning("Can't add route samples to a finished run.")
            return
        }
        let last = lastSample ?? routeSamplesValue?.max { $0.timestamp < $1.timestamp }
        if let last, sample.timestamp <= last.timestamp {
            Logger.run.debug("Ignoring an out-of-order route sample.")
            droppedOutOfOrder += 1
            return
        }
        var estimator = distanceEstimator ?? DistanceEstimator(previous: last.map { DistanceEstimator.Fix($0) }, sport: sport)
        let step = estimator.add(DistanceEstimator.Fix(sample), counts: status == .active)
        distanceEstimator = estimator
        if last == nil, distanceMethodValue == DistanceEstimator.appleMethod {
            // GPS found its first fix after Apple's distance stood in. GPS carries on from there.
            distanceMethodValue = DistanceEstimator.appleThenTrackMethod
        }
        if status == .active, last != nil {
            distanceMetersValue += step.meters
            gpsTrackMetersValue = (gpsTrackMetersValue ?? 0) + step.gap
        }
        attach(sample)
        lastSample = sample
    }

    /// Adds a fix to the route from its own side, so a long run doesn't copy its whole route each second.
    /// Outside a store, as in some tests, it's added to the list.
    private func attach(_ sample: RouteSample) {
        if let modelContext {
            modelContext.insert(sample)
            sample.runValue = self
        } else {
            routeSamplesValue = (routeSamplesValue ?? []) + [sample]
        }
    }

    private func attach(_ sample: HeartRateSample) {
        if let modelContext {
            modelContext.insert(sample)
            sample.runValue = self
        } else {
            heartRateSamplesValue = (heartRateSamplesValue ?? []) + [sample]
        }
    }

    /// Keeps the distance Apple's workout session has worked out so far.
    func recordAppleDistance(_ meters: Double) {
        guard !isFinished else { return }
        guard meters.isFinite, meters >= 0 else { return }
        appleDistanceMetersValue = meters
        // Until GPS has its first fix, Apple's distance stands in, so a run where GPS never comes, such as
        // with location off or under cover, still has a distance. The workout session works it out from the
        // wrist's or phone's motion as well as GPS.
        if usesAppleDistance {
            distanceMetersValue = max(distanceMetersValue, meters)
            distanceMethodValue = DistanceEstimator.appleMethod
        }
    }

    /// True while there's no GPS fix yet, and the distance is Apple's.
    private var usesAppleDistance: Bool {
        guard lastSample == nil, routeSamplesValue?.isEmpty ?? true else { return false }
        return distanceMethodValue == DistanceEstimator.method || distanceMethodValue == DistanceEstimator.appleMethod
    }

    /// Keeps which devices recorded the run.
    func saveDevices(_ devices: RunDevices) {
        devicesDataValue = try? JSONEncoder().encode(devices)
    }

    /// What was set up and started for the run, or nil for runs recorded before it was kept.
    var sensorReport: RunSensorReport? {
        Self.decodedJSON(RunSensorReport.self, from: sensorReportDataValue)
    }

    func saveSensorReport(_ report: RunSensorReport) {
        sensorReportDataValue = try? JSONEncoder().encode(report)
    }

    /// Changes the run's sensor report, when it has one.
    func updateSensorReport(_ change: (inout RunSensorReport) -> Void) {
        guard var report = sensorReport else { return }
        change(&report)
        saveSensorReport(report)
    }

    /// What the run recorded, for its Sensors section: counts and kinds only.
    var sensorFacts: RunSensorFacts {
        let samples = heartRateSamplesValue ?? []
        let devices = devices
        var sources = (devices?.heartRate ?? []).compactMap { device -> HeartRateSource? in
            switch device.kind {
            case .appleWatch: .appleWatch
            case .earbuds: .earbuds
            case .strapOrSensor: .strapOrSensor
            case .iPhone, .other: nil
            }
        }
        if sources.isEmpty {
            sources = HeartRateSource.allCases.filter { source in samples.contains { $0.sourceValue == source.rawValue } }
        }
        var unique: [HeartRateSource] = []
        for source in sources where !unique.contains(source) { unique.append(source) }
        let readings = routeReadings
        return RunSensorFacts(
            report: sensorReport,
            heartRateReadings: samples.count,
            heartRateSources: unique,
            fixes: readings.count,
            typicalAccuracy: RunSensorReport.typical(readings.map(\.horizontalAccuracyValue)),
            appleDistance: appleDistanceMeters,
            steps: stepTotal,
            hasBarometer: !barometricAltitude.isEmpty,
            countsSteps: sport != .cycling,
            recordedOnWatch: devices?.recorder.kind == .appleWatch
        )
    }

    /// Adds a device that measured the run's heart rate, the first time it's seen.
    func addHeartRateDevice(_ device: DeviceInfo) {
        guard var devices else { return }
        let before = devices.heartRate.count
        devices.addHeartRate(device)
        guard devices.heartRate.count != before else { return }
        saveDevices(devices)
    }

    /// Adds a heart rate reading and returns whether it was kept. Readings only count while the run is
    /// active and outside a pause, so standing still at a crossing doesn't pull the average down.
    @discardableResult
    func record(_ sample: HeartRateSample) -> Bool {
        guard status == .active else {
            Logger.run.debug("Ignoring a heart rate reading while the run isn't active.")
            return false
        }
        // HealthKit can hand over a reading from a pause just after the run resumes.
        guard !(pausesValue ?? []).contains(where: { $0.contains(sample.timestamp) }) else {
            Logger.run.debug("Ignoring a heart rate reading taken during a pause.")
            return false
        }
        guard sample.beatsPerMinute > 0 else { return false }
        let last = lastHeartRateSample ?? heartRateSamplesValue?.max { $0.timestamp < $1.timestamp }
        if let last, sample.timestamp <= last.timestamp {
            Logger.run.debug("Ignoring an out-of-order heart rate reading.")
            droppedOutOfOrder += 1
            return false
        }
        attach(sample)
        lastHeartRateSample = sample
        return true
    }
}
