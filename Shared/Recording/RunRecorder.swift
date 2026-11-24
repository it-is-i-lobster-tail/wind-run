//
//  RunRecorder.swift
//  Wind Run
//

import CoreLocation
import Foundation
import HealthKit
import Observation
import OSLog
import SwiftData

/// Drives one run from start to finish: listens for GPS fixes, and heart rate and footsteps when
/// they're on, and feeds them to the `Run`. With auto-pause on, it pauses the run when the runner
/// stands still and starts it again when they move off.
///
/// Location stays on the device. Fixes go into the local store, and into Apple Health
/// only if the runner has turned that on.
@Observable
final class RunRecorder {
    /// Fixes less accurate than this are dropped so GPS drift doesn't inflate distance.
    static let maximumHorizontalAccuracy: CLLocationAccuracy = 30

    private(set) var run: Run?
    private(set) var locationDenied = false
    /// True when Precise Location is off for Wind Run: fixes are then kilometers wide, too rough to count,
    /// so the run can't measure distance until it's turned back on.
    private(set) var locationApproximate = false
    /// True while the system says it can't get a location right now, such as indoors or in a tunnel.
    private(set) var locationUnavailable = false
    /// When the last fix good enough to count arrived, or nil before the first. The run screen reads it to
    /// show whether GPS is still being found or has been lost.
    private(set) var lastCountedFix: Date?
    /// No counted fix for this long means the signal has gone weak or been lost.
    static let signalLostAfter: TimeInterval = 10
    /// A fix more than this old when the first one comes in is a cached one from before the run.
    static let staleFixAge: TimeInterval = 10
    /// The run's workout session: live heart rate when heart rate is on for this run, and on the watch what
    /// keeps the app running with the wrist down even when it's off.
    private var workoutSession: HeartRateMonitor?
    /// Live heart rate, or nil when heart rate is off for this run.
    var heartRate: HeartRateMonitor? {
        workoutSession?.readsHeartRate == true ? workoutSession : nil
    }
    /// True once heart rate stopped part way, because the system ended the workout session, such as when
    /// another workout app started. The run screen says so.
    private(set) var heartRateStopped = false

    private let modelContext: ModelContext
    private var updatesTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var session: CLServiceSession?
    #if os(iOS)
    /// Keeps GPS and call-outs going with the phone locked in a pocket.
    private var backgroundSession: CLBackgroundActivitySession?
    #endif
    /// Reads out each split as it ends, or nil when call-outs are off.
    private var paceCallouts: PaceCalloutTracker?
    private let speaker = CalloutSpeaker()
    /// True once the runner mutes the voice from the run screen. It lasts for this run only, and the
    /// buzzes carry on as before.
    private(set) var isVoiceMuted = false
    /// A cue to speak, checked about once a second with the run's active time, distance and recent
    /// heart rate, such as the coach's heart-rate cue. Set it before `start`. When it and a split
    /// read-out land together, only the cue plays.
    var spokenCue: ((_ elapsed: TimeInterval, _ meters: Double, _ beatsPerMinute: Double?) -> String?)?
    /// The newest heart-rate reading, for `spokenCue`.
    private var latestHeartRate: (beatsPerMinute: Double, date: Date)?
    /// For a structured run, where the runner is in its steps. The steps as run are kept with the run.
    private(set) var steps: StepTracker?
    /// True once a distance or timed run has reached its goal, so it buzzes only the once. The run screen
    /// shows it too.
    private(set) var goalReached = false
    /// Running time when the goal was reached, for the finish time on the display screen. Nil for a run
    /// carried on after the app was closed past its goal.
    private var goalReachedElapsed: TimeInterval?
    /// The active time last checked for steps and call-outs. A fix can arrive stamped a moment before the
    /// clock's last tick, and without this the steps and countdown would step back and buzz twice.
    private var lastCheckedElapsed: TimeInterval = 0
    /// When footsteps and the barometer were last written to the run, so a run the app is closed in keeps them.
    private var sensorsSavedAt: Date?
    private static let sensorSaveInterval: TimeInterval = 60
    /// Times the location stream has been started again this run after it ended on its own.
    private var locationRestarts = 0
    private static let maximumLocationRestarts = 5
    /// The location states last traced, so the trace gets a line only when one changes.
    private var lastLocationState: LocationState?
    /// The GPS signal last traced.
    private var lastTracedSignal: GPSSignal?
    /// The countdown second last tapped, so each of a step's last seconds taps once.
    private var lastCountdown: Int?
    /// Step counts from the workout session, kept with the run when it ends or pauses.
    private var stepCounts: [StepCountSample] = []
    /// The step counts a run carried on after the app was closed already had, kept ahead of the new ones.
    private var earlierStepCounts: [StepCountSample] = []
    /// Footsteps and cadence from the motion sensor, or nil when motion isn't in use for this run.
    private(set) var motion: MotionMonitor?
    /// The motion sensor's footsteps, which auto-pause reads too.
    private var footsteps: FootstepLog?
    /// Whether the runner turned step counting on, so the footsteps are shown and kept with the run.
    private var savesFootsteps = false
    /// Climb and drop from the barometer, for elevation and calories, or nil without one or without
    /// Motion & Fitness allowed.
    private var altimeter: AltimeterMonitor?
    /// Stops and starts the run on its own, or nil when auto-pause is off.
    private var autoPause: AutoPause?
    /// True while the run is paused because the runner stood still, not because they tapped Pause.
    private(set) var isAutoPaused = false
    /// The last 30 seconds of running, for the pace the run screen shows.
    private var recentPace = RecentPace()
    /// Height from GPS, for how far above or below the start the runner is when there's no barometer.
    private var gpsHeight = GPSHeightFromStart()
    /// The kilometer and mile under way, for split pace and the last split in either unit.
    private var kilometerSplits = SplitClock(length: DistanceUnit.kilometers.meters)
    private var mileSplits = SplitClock(length: DistanceUnit.miles.meters)
    /// The last half kilometer or half mile, for rolling pace.
    private var rollingPace = RollingPace()
    /// Grade and vertical speed.
    private var slope = SlopeTracker()
    /// Total climb and drop, once there's a height to count from.
    private var climb: ClimbCounter?
    /// Calories so far, per kilogram.
    private var liveCalories = LiveCalories()
    /// The running time and distance at the last fix taken while running, for the next calorie leg.
    private var lastLeg: (time: TimeInterval, meters: Double)?
    /// Heart rate readings so far, for the average.
    private var heartRateTotal: (sum: Double, count: Int) = (0, 0)
    /// The first and newest kept fixes, for distance to start and daylight. Kept in memory only.
    private var firstLocation: CLLocation?
    private var latestLocation: CLLocation?
    /// The next sunrise or sunset where the run started, worked out once and again after it passes.
    private var sunEvent: SunTimes.Event?
    private var sunWorkedOut = false
    /// Read once when the run starts: the highest heart rate, for zones, and the weight, for calories.
    private var heartRateMax: Double?
    private var bodyMass: Double?
    /// Readings older than this count as no reading: the same limit the heart-rate monitor uses.
    private static let heartRateFreshness = HeartRateMonitor.readingFreshness
    #if os(iOS)
    /// Heart rate and the step under way on the Lock Screen and in the Dynamic Island, while this run
    /// measures heart rate or has steps.
    private var liveActivity: HeartRateActivityController?
    #endif

    /// The saved display this run shows, picked when it starts, or nil for the default. Looked up each time
    /// it's read, so a change made to that display mid-run shows straight away.
    private(set) var displayScreenID: UUID?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// The display screen this run shows on the run screen, the Watch and the Lock Screen.
    var displayScreen: DisplayScreen { DisplayLibrary.current.screen(id: displayScreenID) }

    /// The display a run picks when it starts: a coach session's from the settings, a saved workout's own,
    /// and a distance, timed or free run's from the settings. Nil for the default.
    static func pickedDisplayScreenID(
        coached: Bool,
        intervalPlan: IntervalPlan?,
        goal: RunGoal?,
        sport: WorkoutSport = .running,
        defaults: UserDefaults = .standard
    ) -> UUID? {
        if coached { return DisplayRunKind.coach.pick(in: defaults) }
        if let intervalPlan { return intervalPlan.displayScreenID }
        switch goal {
        case .distance: return DisplayRunKind.distance.pick(in: defaults)
        case .time: return DisplayRunKind.timed.pick(in: defaults)
        case nil: return (sport == .cycling ? DisplayRunKind.cycling : .free).pick(in: defaults)
        }
    }

    var isRecording: Bool {
        guard let run else { return false }
        return !run.isFinished
    }

    func start(
        kind: RunKind = .free,
        sport: WorkoutSport = .running,
        intervalPlan: IntervalPlan? = nil,
        coachWorkout: CoachWorkout? = nil,
        goal: RunGoal? = nil,
        measuresHeartRate: Bool = false,
        countsSteps: Bool = UserDefaults.standard.bool(forKey: MotionMonitor.stepsKey),
        autoPauses: Bool = UserDefaults.standard.bool(forKey: AutoPause.storageKey)
    ) {
        guard !isRecording else {
            Logger.recording.warning("A run is already being recorded.")
            return
        }
        let sport = coachWorkout == nil ? (intervalPlan?.sport ?? sport) : .running
        let run = Run(kind: coachWorkout == nil ? kind : .coached, sport: sport)
        displayScreenID = Self.pickedDisplayScreenID(coached: coachWorkout != nil, intervalPlan: intervalPlan, goal: goal, sport: sport)
        Trace.log(.run, "Started", [
            "kind": run.kind.rawValue,
            "sport": sport.rawValue,
            "steps": (intervalPlan ?? coachWorkout?.intervalPlan)?.timeline.count ?? 0,
            "goal": goal.map { "\($0)" } ?? "none",
            "heartRate": measuresHeartRate,
            "countsSteps": countsSteps,
            "autoPause": autoPauses,
            "display": displayScreenID == nil ? "default" : (DisplayLibrary.current.contains(displayScreenID) ? "own" : "deleted"),
        ])
        run.intervalPlanValue = intervalPlan ?? coachWorkout?.intervalPlan
        run.coachWorkoutValue = coachWorkout
        // A coach session brings its own target.
        run.goal = coachWorkout == nil ? goal : nil
        goalReached = false
        goalReachedElapsed = nil
        // Which device recorded it and its versions, so a run can always be traced back.
        run.saveDevices(RunDevices(recorder: .current))
        modelContext.insert(run)
        modelContext.saveQuietly()
        self.run = run
        // So a launch after the app was closed mid-run finishes this run, and only this device's own.
        RunRecovery.markRecording(run)
        resetPerRunState(lastCheckedElapsed: 0, earlierStepCounts: [], sensorsSavedAt: run.startDate)
        // Only start clears these here; carryOn leaves them as they are.
        locationApproximate = false
        locationUnavailable = false
        if let timeline = run.intervalPlanValue?.timeline, !timeline.isEmpty {
            steps = StepTracker(timeline: timeline)
        }
        paceCallouts = PaceCalloutTracker(settings: .current(for: run.sport))
        startLocationUpdates()
        let usesFootMotion = run.sport == .running && (countsSteps || autoPauses)
        let asksForMotion = usesFootMotion && MotionMonitor.needsAsking
        if usesFootMotion, !asksForMotion {
            startMotion(at: run.startDate, savesFootsteps: countsSteps)
        }
        if autoPauses {
            autoPause = AutoPause(usesMotion: motion != nil, start: run.startDate)
        }
        if asksForMotion {
            askForMotion(at: run.startDate, savesFootsteps: countsSteps)
        }
        startAltimeterAndClimb()
        readRunnerProfile()
        startClock()
        if let tracker = steps, let first = tracker.current {
            speaker.speak(Self.spokenStep(first, runsUntilFinish: tracker.runsUntilFinish, sport: run.sport))
            feel(StepHaptic.starting(first))
        }
        heartRateStopped = false
        if measuresHeartRate {
            startHeartRate(at: run.startDate)
        }
        #if os(watchOS)
        // Only a workout session keeps a watch app running with the wrist down, so a run without heart rate
        // still has one. It reads nothing.
        if workoutSession == nil {
            startWorkoutSession(at: run.startDate, readsHeartRate: false)
        }
        #endif
        // What actually started, which can differ from what was asked for: no motion without Motion &
        // Fitness, no barometer on some devices, no heart rate without Health workouts allowed.
        Trace.log(.run, "Sensors", [
            "motion": motion != nil,
            "barometer": altimeter != nil,
            "heartRate": heartRate != nil,
            "workoutSession": workoutSession != nil,
            "autoPauseUsesMotion": autoPause?.usesMotion ?? false,
            "hasWeight": bodyMass != nil,
        ])
        #if os(iOS)
        startLiveActivity(for: run)
        #endif
    }

    /// The runner paused. Only they can start it again.
    func pause() {
        Trace.log(.run, "Paused by the runner", runTotals)
        let wasGoing = run?.status == .active
        isAutoPaused = false
        pauseRun()
        // The same buzz as auto-pause, so a tap mid-stride is felt without looking down.
        if wasGoing { feel(.paused) }
    }

    func resume() {
        Trace.log(.run, "Resumed by the runner", runTotals)
        let wasPaused = run?.status == .paused
        isAutoPaused = false
        autoPause?.runnerResumed(at: .now)
        resumeRun()
        if wasPaused { feel(.resumed) }
    }

    private func pauseRun() {
        lastLeg = nil
        run?.saveStepCounts(keptStepCounts)
        // Kept now too, so a run the app is closed in still has its climb.
        if let altimeter { run?.saveBarometricAltitude(altimeter.samples) }
        run?.pause()
        workoutSession?.pause()
        modelContext.saveQuietly()
        showStep()
    }

    private func resumeRun() {
        run?.resume()
        workoutSession?.resume()
        modelContext.saveQuietly()
        showStep()
    }

    /// The step counts kept with the run: the motion sensor's when step counting is on and it counted,
    /// otherwise the workout session's.
    private var keptStepCounts: [StepCountSample] {
        if savesFootsteps, let samples = footsteps?.samples, !samples.isEmpty {
            return earlierStepCounts + samples
        }
        return earlierStepCounts + stepCounts
    }

    /// Seconds per kilometer over the last 30 seconds of running, for the run screen. Nil while paused,
    /// until there's enough running to say, or when GPS has gone quiet.
    func currentPace(at date: Date = .now) -> TimeInterval? {
        guard let run, run.status == .active else { return nil }
        return recentPace.pace(at: run.activeTime(at: date))
    }

    /// Meters above where the run started, negative below, for the run screen: from the barometer when
    /// there is one, otherwise from GPS. Nil until either has a reading.
    var heightFromStart: Double? {
        altimeter?.latest?.relativeMeters ?? gpsHeight.change
    }

    /// A saved workout's target pace while `step` runs: its main part's, so the work, and nil for a warm-up,
    /// recovery, walk or cooldown.
    static func paceTarget(during step: PlannedIntervalStep, of plan: IntervalPlan?) -> ClosedRange<TimeInterval>? {
        guard step.kind == .work, !step.isWalk else { return nil }
        return plan?.targetPace
    }

    /// The run's numbers at `date`, for a display screen, or nil with no run.
    func snapshot(at date: Date = .now, unit: DistanceUnit) -> RunSnapshot? {
        guard let run else { return nil }
        let coach = steps == nil ? run.coachWorkout : nil
        let goal = run.goal
        var snapshot = RunSnapshot(
            isPaused: run.status == .paused,
            elapsed: run.activeDuration(at: date),
            meters: run.distanceMeters,
            unit: unit,
            currentPace: currentPace(at: date),
            averagePace: run.pace(at: date),
            beatsPerMinute: heartRate?.beatsPerMinute(at: date),
            heightFromStart: heightFromStart,
            cadence: motion?.cadence,
            goalMeters: coach?.positiveTargetMeters.map(unit.plannedMeters) ?? goal?.meters,
            goalSeconds: coach?.positiveTargetSeconds.map(CoachFormat.plannedSeconds) ?? goal?.seconds,
            paceTarget: coach?.paceRange
        )
        let time = run.activeTime(at: date)
        let splits = unit == .miles ? mileSplits : kilometerSplits
        snapshot.sport = run.sport
        snapshot.date = date
        snapshot.startDate = run.startDate
        snapshot.goalReachedElapsed = goalReachedElapsed
        snapshot.splitPace = splits.pace(time: time, meters: run.distanceMeters)
        snapshot.lastSplit = splits.lastSplit
        snapshot.rollingPace = rollingPace.pace(over: unit.meters / 2)
        if let tracker = steps {
            if let step = tracker.current {
                if let target = Self.paceTarget(during: step, of: run.intervalPlanValue) {
                    snapshot.paceTarget = target
                }
                let elapsed = run.activeDuration(at: date)
                snapshot.step = RunSnapshot.StepReading(
                    name: step.name,
                    remaining: tracker.remaining(elapsed: elapsed, meters: run.distanceMeters),
                    inStep: tracker.elapsedInStep(elapsed)
                )
            } else {
                snapshot.step = RunSnapshot.StepReading(name: "", remaining: nil, inStep: 0, isFinished: true)
            }
        }
        snapshot.heartRateMax = heartRateMax
        if heartRateTotal.count > 0 {
            snapshot.averageHeartRate = heartRateTotal.sum / Double(heartRateTotal.count)
        }
        if heightFromStart != nil, let climb {
            snapshot.totalAscent = climb.ascent
            snapshot.totalDescent = climb.descent
        }
        snapshot.altitude = altitude
        snapshot.grade = slope.grade
        snapshot.verticalSpeed = slope.metersPerHour
        snapshot.calories = bodyMass.map { liveCalories.perKilogram * $0 }
        snapshot.sunEvent = nextSunEvent(after: date)
        if let firstLocation, let latestLocation {
            snapshot.metersToStart = latestLocation.distance(from: firstLocation)
        }
        snapshot.runningPower = heartRate?.runningPower
        return snapshot
    }

    /// Meters above sea level: where GPS put the start, plus the barometer's climb since, or GPS alone
    /// without a barometer. Nil until GPS gives a usable height.
    private var altitude: Double? {
        guard let start = gpsHeight.startAltitude else { return nil }
        if let climbed = altimeter?.latest?.relativeMeters { return start + climbed }
        return gpsHeight.latestAltitude
    }

    /// The next sunrise or sunset where the run started, worked out on the device.
    private func nextSunEvent(after date: Date) -> SunTimes.Event? {
        guard let firstLocation else { return nil }
        if !sunWorkedOut || (sunEvent.map { $0.date <= date } ?? false) {
            sunWorkedOut = true
            let coordinate = firstLocation.coordinate
            sunEvent = SunTimes.next(after: date, latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        return sunEvent
    }

    /// Steps taken while running, for the run screen, or nil when step counting is off.
    var footstepCount: Double? {
        savesFootsteps && motion != nil ? footsteps?.total : nil
    }

    /// Steps a minute right now, for the run screen, or nil when step counting is off or the sensor hasn't said.
    var cadence: Double? {
        savesFootsteps ? motion?.cadence : nil
    }

    func finish() {
        Trace.log(.run, "Finishing", runTotals)
        // While the readings are all still there.
        stopLiveActivity(finished: true)
        stopLocationUpdates()
        stopHeartRate()
        stopMotion()
        stopClock()
        let barometer = stopAltimeter()
        guard let run else { return }
        run.saveStepCounts(keptStepCounts)
        if let barometer { run.saveBarometricAltitude(barometer) }
        if var tracker = steps {
            tracker.finish(elapsed: run.activeDuration(), meters: run.distanceMeters)
            run.saveStepLog(tracker.recorded)
            steps = tracker
        }
        run.finish()
        RunRecovery.markRecording(nil)
        HeartRateMax.record(run.heartRateSamples.map(\.beatsPerMinute))
        // The watch has no weight, so its runs get their calories on the iPhone.
        run.settleCalories(bodyMass: BodyWeight.kilograms())
        modelContext.saveQuietly()
        Trace.log(.run, "Finished", runTotals)
        HealthSync.shared.saveIfEnabled(run, in: modelContext)
    }

    /// The run so far for a trace line: no route, times of day or heart rate.
    private var runTotals: KeyValuePairs<String, Any> {
        guard let run else { return ["run": "none"] }
        return [
            "status": run.status.rawValue,
            "meters": run.distanceMeters,
            "activeSeconds": run.activeDuration(),
            "fixes": run.route.count,
            "pauses": run.pauses.count,
        ]
    }

    /// Throws the run away, along with its route and heart rate.
    func discard() {
        Trace.log(.run, "Discarded", runTotals)
        stopLocationUpdates()
        stopHeartRate()
        stopMotion()
        stopLiveActivity()
        stopClock()
        stopAltimeter()
        speaker.stop()
        RunRecovery.markRecording(nil)
        if let run {
            run.discard()
            modelContext.delete(run)
            modelContext.saveQuietly()
        }
        run = nil
    }

    #if os(watchOS)
    /// Carries on a run the app was closed in, with the workout session watchOS kept going for it. GPS, the
    /// clock, the steps and the call-outs pick up from where the run had got to; the barometer carries on
    /// from the height kept. Splits, the recent pace and the climb so far on the run screen start again from
    /// here, and the finished run works its climb out from all of it.
    func carryOn(_ run: Run, session: HKWorkoutSession, measuresHeartRate: Bool) {
        guard !isRecording, !run.isFinished else { return }
        self.run = run
        RunRecovery.markRecording(run)
        let elapsed = run.activeDuration()
        resetPerRunState(lastCheckedElapsed: elapsed, earlierStepCounts: run.stepCounts, sensorsSavedAt: .now)
        liveCalories = LiveCalories(perKilogram: run.calorieEstimate?.perKilogram ?? 0)
        // Only carryOn clears these here. Start clears heartRateStopped further down, and leaves stepCounts
        // as a new recorder has them, empty.
        stepCounts = []
        heartRateStopped = false
        if let timeline = run.intervalPlanValue?.timeline, !timeline.isEmpty {
            steps = StepTracker(timeline: timeline, resumingFrom: run.stepLog)
        }
        paceCallouts = PaceCalloutTracker(settings: .current(for: run.sport))
        paceCallouts?.resume(elapsed: elapsed, meters: run.distanceMeters)
        startLocationUpdates()
        let countsSteps = UserDefaults.standard.bool(forKey: MotionMonitor.stepsKey)
        let autoPauses = UserDefaults.standard.bool(forKey: AutoPause.storageKey)
        if run.sport == .running && (countsSteps || autoPauses) {
            startMotion(at: .now, savesFootsteps: countsSteps)
        }
        if autoPauses {
            autoPause = AutoPause(usesMotion: motion != nil, start: .now)
        }
        startAltimeterAndClimb(continuing: run.barometricAltitude)
        readRunnerProfile()
        let monitor = makeWorkoutSession()
        monitor.recover(session, readsHeartRate: measuresHeartRate && HealthSync.shared.access == .allowed)
        workoutSession = monitor
        goalReached = effectiveGoal?.isReached(elapsed: elapsed, meters: run.distanceMeters) ?? false
        startClock()
        Trace.log(.run, "Carried on after the app was closed", [
            "status": run.status.rawValue,
            "activeSeconds": elapsed,
            "fixes": run.route.count,
            "step": steps.map { $0.index + 1 } ?? 0,
            "heartRate": heartRate != nil,
        ])
    }
    #endif

    /// Clears what a run before left behind, for `start` and `carryOn`. A new run starts from nothing; a
    /// carried-on one from where it had got to.
    private func resetPerRunState(lastCheckedElapsed: TimeInterval, earlierStepCounts: [StepCountSample], sensorsSavedAt: Date) {
        liveCalories = LiveCalories()
        lastLeg = nil
        self.lastCheckedElapsed = lastCheckedElapsed
        self.earlierStepCounts = earlierStepCounts
        self.sensorsSavedAt = sensorsSavedAt
        locationRestarts = 0
        lastCountedFix = nil
        lastLocationState = nil
        lastTracedSignal = nil
    }

    /// Starts the barometer, carrying on from `earlier`, then the climb, which counts finer with a barometer.
    private func startAltimeterAndClimb(continuing earlier: [AltitudeSample] = []) {
        startAltimeter(continuing: earlier)
        climb = ClimbCounter(threshold: ClimbCounter.threshold(hasBarometer: altimeter != nil))
    }

    /// Reads the highest heart rate and the weight.
    private func readRunnerProfile() {
        heartRateMax = HeartRateMax.value()
        bodyMass = BodyWeight.kilograms()
    }

    private func startLocationUpdates() {
        session = CLServiceSession(authorization: .whenInUse)
        #if os(iOS)
        backgroundSession = CLBackgroundActivitySession()
        #endif
        listenForLocation()
    }

    private func listenForLocation() {
        updatesTask = Task { [weak self] in
            var failure: (any Error)?
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self, !Task.isCancelled else { return }
                    self.noteLocationState(update)
                    if let location = update.location {
                        self.receive(location)
                    }
                }
            } catch {
                failure = error
            }
            guard let self, !Task.isCancelled else { return }
            self.locationUpdatesEnded(failure)
        }
    }

    /// Keeps what the system says about location, tracing only the changes so it isn't a line a second.
    private func noteLocationState(_ update: CLLocationUpdate) {
        let state = LocationState(
            denied: update.authorizationDenied || update.authorizationDeniedGlobally,
            approximate: update.accuracyLimited,
            unavailable: update.locationUnavailable,
            insufficientlyInUse: update.insufficientlyInUse
        )
        Logger.recording.debug("Location update: fix \(update.location != nil), denied \(state.denied), approximate \(state.approximate), unavailable \(state.unavailable), insufficient \(state.insufficientlyInUse)")
        guard state != lastLocationState else { return }
        lastLocationState = state
        locationDenied = state.denied
        locationApproximate = state.approximate
        locationUnavailable = state.unavailable
        Trace.log(.gps, "Location state", [
            "denied": state.denied,
            "approximate": state.approximate,
            "unavailable": state.unavailable,
            "insufficientlyInUse": state.insufficientlyInUse,
        ])
        noteSignal(at: .now)
    }

    /// The location stream ended while the run was still going, which leaves distance stuck. It's started
    /// again after a moment, a few times at most.
    private func locationUpdatesEnded(_ error: (any Error)?) {
        if let error {
            Logger.recording.error("Location updates ended: \(error)")
        } else {
            Trace.log(.gps, "Location updates ended")
        }
        guard isRecording, locationRestarts < Self.maximumLocationRestarts else { return }
        locationRestarts += 1
        Trace.log(.gps, "Restarting location updates", ["restarts": locationRestarts])
        updatesTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled, self.isRecording else { return }
            self.listenForLocation()
        }
    }

    /// How GPS is doing at `date`, for the run screen.
    func gpsSignal(at date: Date = .now) -> GPSSignal {
        Self.gpsSignal(lastCountedFix: lastCountedFix, locationUnavailable: locationUnavailable, at: date)
    }

    /// Searching until a fix has counted, then weak while the system says location is unavailable or no fix
    /// has counted for `signalLostAfter`, otherwise good.
    static func gpsSignal(lastCountedFix: Date?, locationUnavailable: Bool, at date: Date) -> GPSSignal {
        guard let lastCountedFix else { return .searching }
        if locationUnavailable || date.timeIntervalSince(lastCountedFix) > signalLostAfter {
            return .weak
        }
        return .good
    }

    /// Traces the GPS signal when it changes, with how long since the last counted fix.
    private func noteSignal(at date: Date) {
        let signal = gpsSignal(at: date)
        guard signal != lastTracedSignal else { return }
        lastTracedSignal = signal
        Trace.log(.gps, "Signal", [
            "signal": signal.rawValue,
            "secondsSinceCountedFix": lastCountedFix.map { max(0, date.timeIntervalSince($0)) } as Any,
        ])
    }

    /// Writes the footsteps and barometer readings so far to the run about once a minute. They're otherwise
    /// only kept at a pause or the finish, and a run the app is closed in would lose them.
    private func saveSensorsIfDue(at date: Date) {
        guard let run, !run.isFinished, savesFootsteps || altimeter != nil || !stepCounts.isEmpty else { return }
        if let sensorsSavedAt, date.timeIntervalSince(sensorsSavedAt) < Self.sensorSaveInterval { return }
        sensorsSavedAt = date
        run.saveStepCounts(keptStepCounts)
        if let altimeter { run.saveBarometricAltitude(altimeter.samples) }
        modelContext.saveQuietly()
    }

    private func stopLocationUpdates() {
        updatesTask?.cancel()
        updatesTask = nil
        session?.invalidate()
        session = nil
        #if os(iOS)
        backgroundSession?.invalidate()
        backgroundSession = nil
        #endif
    }

    /// Time splits end and stops last whether or not a GPS fix arrives, so the clock is checked every second too.
    private func startClock() {
        #if os(watchOS)
        guard paceCallouts != nil || spokenCue != nil || steps != nil || autoPause != nil || motion != nil || effectiveGoal != nil else { return }
        #endif
        // On the iPhone it always runs: the Lock Screen's display screen follows it.
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                let now = Date.now
                self.motion?.tick(at: now)
                self.checkAutoPause(at: now)
                self.advanceStepsAndSpeak(at: now)
                self.checkGoal(at: now)
                self.noteSignal(at: now)
                self.saveSensorsIfDue(at: now)
                self.showDisplay(at: now)
            }
        }
    }

    private func stopClock() {
        clockTask?.cancel()
        clockTask = nil
    }

    private func startHeartRate(at date: Date) {
        // With workouts no longer allowed, HealthKit runs the session but never collects.
        guard HealthSync.shared.access == .allowed else {
            Logger.health.info("Heart rate is on, but Health doesn't allow workouts, so this run has none.")
            Trace.log(.heart, "Heart rate on, but workouts aren't allowed in Health")
            return
        }
        startWorkoutSession(at: date, readsHeartRate: true)
    }

    /// Starts the workout session, reading heart rate or, on the watch, only keeping the app running.
    private func startWorkoutSession(at date: Date, readsHeartRate: Bool) {
        guard HealthSync.shared.access == .allowed else {
            Trace.log(.heart, "No workout session: workouts aren't allowed in Health")
            return
        }
        let monitor = makeWorkoutSession()
        guard monitor.start(at: date, readsHeartRate: readsHeartRate, sport: run?.sport ?? .running) else {
            Trace.log(.heart, readsHeartRate ? "Couldn't start heart rate" : "Couldn't start the workout session")
            return
        }
        Trace.log(.heart, readsHeartRate ? "Started" : "Started the workout session without heart rate")
        workoutSession = monitor
    }

    /// A workout session hooked up to this run.
    private func makeWorkoutSession() -> HeartRateMonitor {
        let monitor = HeartRateMonitor()
        monitor.onSteps = { [weak self] count, interval in
            Trace.log(.motion, "Workout step count", ["steps": count, "seconds": interval.duration])
            self?.stepCounts.append(StepCountSample(start: interval.start, end: interval.end, count: count))
        }
        monitor.onDistance = { [weak self] meters in
            self?.run?.recordAppleDistance(meters)
        }
        monitor.onDevice = { [weak self] device in
            self?.run?.addHeartRateDevice(device)
        }
        monitor.onReading = { [weak self] beatsPerMinute, date, source in
            // That a reading came and from what kind of device, never the reading itself.
            Trace.log(.heart, "Reading", ["source": source?.rawValue ?? "unknown"])
            self?.latestHeartRate = (beatsPerMinute, date)
            // Only readings the run keeps count toward the average, so readings from a pause don't pull it
            // down and the run screen matches the finished run.
            if self?.run?.record(HeartRateSample(timestamp: date, beatsPerMinute: beatsPerMinute, source: source)) == true {
                self?.heartRateTotal.sum += beatsPerMinute
                self?.heartRateTotal.count += 1
            }
            #if os(iOS)
            self?.liveActivity?.record(beatsPerMinute, at: date)
            #endif
        }
        monitor.onEnded = { [weak self, weak monitor] in
            guard let self, self.isRecording else { return }
            let readsHeartRate = monitor?.readsHeartRate ?? false
            Trace.log(.heart, "Workout session ended before the run", ["readsHeartRate": readsHeartRate])
            if readsHeartRate {
                self.heartRateStopped = true
            }
            self.workoutSession = nil
        }
        return monitor
    }

    private func stopHeartRate() {
        workoutSession?.stop()
        workoutSession = nil
    }

    private func startMotion(at date: Date, savesFootsteps: Bool) {
        let monitor = MotionMonitor()
        monitor.onSteps = { [weak self] totalSteps, cadence, date in
            self?.receiveFootsteps(totalSteps, cadence: cadence, at: date)
        }
        monitor.onActivity = { [weak self] activity, date in
            Trace.log(.motion, "Activity", ["activity": "\(activity)"])
            self?.autoPause?.activity(activity, at: date)
        }
        monitor.onFailure = { [weak self] in
            Trace.log(.motion, "Motion sensor failed")
            // Auto-pause carries on with GPS alone. The steps counted so far are kept.
            self?.stopMotion()
            self?.autoPause?.usesMotion = false
        }
        guard monitor.start(at: date) else {
            Logger.recording.info("Motion & Fitness isn't allowed, so this run counts no steps.")
            return
        }
        motion = monitor
        footsteps = FootstepLog(start: date)
        self.savesFootsteps = savesFootsteps
    }

    /// First open asks Apple only about Health, so Motion & Fitness is asked when the first run starts, next to
    /// location (the owner, 2026-11-17). Steps are counted from the start once it's allowed, since the sensor
    /// keeps them; until then auto-pause uses GPS. Said no, step counting goes off like it does in Settings.
    private func askForMotion(at date: Date, savesFootsteps: Bool) {
        Task { [weak self] in
            let allowed = await MotionMonitor.requestAccess()
            Trace.log(.motion, "Asked on first run", ["allowed": allowed])
            guard let self else { return }
            guard allowed else {
                if savesFootsteps { UserDefaults.standard.set(false, forKey: MotionMonitor.stepsKey) }
                return
            }
            guard isRecording, run?.startDate == date, motion == nil else { return }
            startMotion(at: date, savesFootsteps: savesFootsteps)
            if motion != nil { autoPause?.usesMotion = true }
        }
    }

    private func stopMotion() {
        motion?.stop()
        motion = nil
    }

    private func startAltimeter(continuing earlier: [AltitudeSample] = []) {
        let monitor = AltimeterMonitor(continuing: earlier)
        monitor.onFailure = { [weak self] _ in
            // Its readings so far stay with the run; heights from now on come from GPS.
            guard let self, let altimeter = self.altimeter else { return }
            Trace.log(.motion, "Barometer stopped, heights now from GPS", ["readings": altimeter.samples.count])
            self.run?.saveBarometricAltitude(altimeter.samples)
            altimeter.stop()
            self.altimeter = nil
            // GPS heights count from another zero and wander more, so the climb carries on from the next
            // fix at GPS's threshold, and the grade and vertical speed start again, rather than jumping.
            self.climb?.switchSource(threshold: ClimbCounter.gpsThreshold)
            self.slope = SlopeTracker()
        }
        guard monitor.start() else {
            Logger.recording.info("No barometer, or Motion & Fitness isn't allowed, so this run's climb comes from GPS.")
            return
        }
        altimeter = monitor
    }

    /// Stops the barometer and returns its readings, or nil when it wasn't on.
    @discardableResult
    private func stopAltimeter() -> [AltitudeSample]? {
        guard let altimeter else { return nil }
        altimeter.stop()
        self.altimeter = nil
        return altimeter.samples
    }

    private func receiveFootsteps(_ totalSteps: Double, cadence: Double?, at date: Date) {
        guard let run, !run.isFinished, var log = footsteps else { return }
        Trace.log(.motion, "Footsteps", ["total": totalSteps, "cadence": cadence as Any])
        let stepped = log.record(totalSteps: totalSteps, cadence: cadence, at: date, counts: run.status == .active)
        footsteps = log
        if stepped {
            autoPause?.footsteps(at: date, cadence: cadence)
        }
    }

    /// Pauses the run when the runner has stood still a moment, and starts it again when they move off.
    /// A pause the runner chose stays until they end it.
    private func checkAutoPause(at date: Date) {
        guard var autoPause, let run, !run.isFinished else { return }
        defer { self.autoPause = autoPause }
        if run.status == .paused, !isAutoPaused { return }
        // Rests and walk breaks are often stood or walked through, and their clocks have to keep going.
        if run.status == .active, let step = steps?.current, step.kind == .recovery || step.isWalk {
            autoPause.hold()
            return
        }
        let decision = autoPause.check(at: date, isPaused: run.status == .paused)
        if decision != nil {
            // What each sign said, so a pause mid-stride can be traced to its cause.
            let signs = autoPause.signs(at: date)
            Trace.log(.motion, "Auto-pause signs", [
                "usesMotion": signs.usesMotion,
                "stepsQuiet": signs.stepsQuiet,
                "sensorStill": signs.sensorStill,
                "gpsSpeed": signs.gpsSpeed as Any,
                "secondsSinceStep": signs.secondsSinceStep,
            ])
        }
        switch decision {
        case .pause:
            Trace.log(.run, "Auto-paused", runTotals)
            isAutoPaused = true
            pauseRun()
            if speaksAutoPause { speaker.speak("Paused.") }
            feel(.paused)
        case .resume:
            Trace.log(.run, "Auto-resumed", runTotals)
            isAutoPaused = false
            resumeRun()
            if speaksAutoPause { speaker.speak("Resumed.") }
            feel(.resumed)
        case nil:
            break
        }
    }

    /// Auto-pause is said out loud only when the runner hears the run already: voice call-outs are on, or
    /// it's a structured run that speaks its steps. Otherwise the buzz alone tells them, and music isn't
    /// ducked at every crossing. `speaksGoal` asks something different: a coach session's cue, not its steps.
    private var speaksAutoPause: Bool {
        paceCallouts != nil || steps != nil
    }

    /// True when something in this run can be said out loud: split call-outs, steps, or a coach cue. The run
    /// screen only offers the mute button then.
    var speaksAloud: Bool {
        paceCallouts != nil || steps != nil || spokenCue != nil
    }

    /// Mutes or unmutes the voice for the rest of this run. Muting cuts off the line being read.
    func setVoiceMuted(_ muted: Bool) {
        guard muted != isVoiceMuted else { return }
        isVoiceMuted = muted
        speaker.isMuted = muted
        Trace.log(.callout, muted ? "Voice muted" : "Voice unmuted")
    }

    /// The goal is said when voice call-outs are on or a coach session speaks cues. Unlike `speaksAutoPause`,
    /// steps alone don't count. Whether the two should be one is still open.
    private var speaksGoal: Bool {
        paceCallouts != nil || spokenCue != nil
    }

    /// Puts the run on the Lock Screen, and lets the Live Activity's Next button reach this run.
    private func startLiveActivity(for run: Run) {
        #if os(iOS)
        let date = run.startDate
        let activity = HeartRateActivityController(run: run)
        activity.start(at: date, showsHeartRate: heartRate != nil, step: stepState(at: date))
        liveActivity = activity
        showDisplay(at: date, force: true)
        if steps != nil {
            ActiveRunControl.nextStep = { [weak self] in self?.nextStep() }
        }
        ActiveRunControl.pause = { [weak self] in self?.pause() }
        ActiveRunControl.resume = { [weak self] in self?.resume() }
        #endif
    }

    /// Takes the run off the Lock Screen. A finished run leaves its final numbers there for a while.
    private func stopLiveActivity(finished: Bool = false) {
        #if os(iOS)
        var finalDisplay: DisplayScreenReadings?
        if finished, liveActivity != nil, let snapshot = snapshot(at: .now, unit: displayUnit) {
            finalDisplay = displayScreen.readings(snapshot)
        }
        liveActivity?.end(showing: finalDisplay)
        liveActivity = nil
        ActiveRunControl.nextStep = nil
        ActiveRunControl.pause = nil
        ActiveRunControl.resume = nil
        #endif
    }

    /// Brings the Live Activity's step up to date. `force` sends the display screen at once, as for a pause,
    /// a resume or a new step; otherwise it goes at most every few seconds.
    private func showStep(at date: Date = .now, force: Bool = true) {
        #if os(iOS)
        // Called on a pause or a resume too, so the Lock Screen's clock stops and starts with the run.
        showDisplay(at: date, force: force)
        guard steps != nil else { return }
        liveActivity?.update(stepState(at: date), at: date)
        #endif
    }

    /// Brings the Live Activity's display screen up to date.
    private func showDisplay(at date: Date, force: Bool = false) {
        #if os(iOS)
        guard let liveActivity, let snapshot = snapshot(at: date, unit: displayUnit) else { return }
        liveActivity.update(display: displayScreen.readings(snapshot, clockRunsAt: date), isPaused: snapshot.isPaused, at: date, force: force)
        #endif
    }

    #if os(iOS)
    /// The unit the Lock Screen shows, the call-outs' own, read afresh each time.
    private var displayUnit: DistanceUnit { DistanceUnit.current() }

    /// The step under way as the Live Activity shows it.
    func stepState(at date: Date = .now) -> RunStepState? {
        guard let run, let tracker = steps else { return nil }
        return Self.stepState(tracker, elapsed: run.activeDuration(at: date), meters: run.distanceMeters, isGoing: run.status == .active, at: date, unit: displayUnit)
    }

    /// While the run is going, the step's clock runs on the Lock Screen from the step's start, or down to its
    /// end; while paused, it shows the time as it stands. A distance step shows the distance left.
    static func stepState(_ tracker: StepTracker, elapsed: TimeInterval, meters: Double, isGoing: Bool, at date: Date, unit: DistanceUnit) -> RunStepState {
        guard let step = tracker.current else {
            return RunStepState(name: "All steps done", number: tracker.timeline.count, count: tracker.timeline.count, isFinished: true)
        }
        let inStep = tracker.elapsedInStep(elapsed)
        // Whole seconds, so the same step sends the same dates every tick.
        let start = Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate - inStep).rounded())
        var state = RunStepState(name: step.name, number: tracker.index + 1, count: tracker.timeline.count, isFinished: false)
        switch tracker.remaining(elapsed: elapsed, meters: meters) {
        case .time(let left):
            if isGoing {
                state.startDate = start
                state.endDate = start.addingTimeInterval(inStep + left)
            } else {
                state.detail = "\(RunFormat.duration(left.rounded(.up))) left"
            }
        case .distance(let left):
            state.detail = "\(RunFormat.distance(left, unit: unit, rounding: .up)) left"
        case .open, nil:
            if isGoing {
                state.startDate = start
            } else {
                state.detail = RunFormat.duration(inStep)
            }
            // An open last step, such as a cool down, runs until the run is finished: nothing to tap on to.
            if tracker.waitsForTap {
                state.nextTitle = step.openStepButtonTitle
            }
        }
        return state
    }
    #endif

    private func receive(_ location: CLLocation) {
        guard let run, !run.isFinished else { return }
        let age = Date.now.timeIntervalSince(location.timestamp)
        let isAccurate = location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= Self.maximumHorizontalAccuracy
        // The first update can be a cached fix from before the run, such as from home or the car park. As the
        // start of the route it would draw a line from there and set the wrong starting height.
        let isStale = location.timestamp < run.startDate || (lastCountedFix == nil && age > Self.staleFixAge)
        let isKept = isAccurate && !isStale
        let message = isKept ? "Fix" : (isStale ? "Fix dropped: stale" : "Fix dropped: not accurate enough")
        // Accuracy and speed only: never where the fix is, its height or which way it's heading.
        Trace.log(.gps, message, [
            "horizontalAccuracy": location.horizontalAccuracy,
            "verticalAccuracy": location.verticalAccuracy,
            "speed": location.speed,
            "speedAccuracy": location.speedAccuracy,
            "ageSeconds": age,
            "status": run.status.rawValue,
        ])
        guard isKept else { return }
        lastCountedFix = .now
        let metersBefore = run.distanceMeters
        run.record(RouteSample(location))
        Trace.log(.gps, "Counted", ["addedMeters": run.distanceMeters - metersBefore, "totalMeters": run.distanceMeters])
        gpsHeight.record(altitude: location.altitude, verticalAccuracy: location.verticalAccuracy)
        if firstLocation == nil { firstLocation = location }
        latestLocation = location
        if run.status == .active {
            let time = run.activeTime(at: location.timestamp)
            let meters = run.distanceMeters
            recentPace.record(time: time, meters: meters)
            kilometerSplits.record(time: time, meters: meters)
            mileSplits.record(time: time, meters: meters)
            rollingPace.record(time: time, meters: meters)
            if let height = heightFromStart {
                slope.record(time: time, meters: meters, height: height)
                climb?.record(height)
            }
            if let lastLeg, time > lastLeg.time {
                // GPS height wobbles by meters over the few tens of meters the grade is read across, and the cost
                // curve rises faster uphill than it falls downhill, so without the barometer it counts as flat.
                let grade = altimeter == nil ? nil : slope.grade
                liveCalories.add(meters: meters - lastLeg.meters, seconds: time - lastLeg.time, grade: grade, sport: run.sport)
            }
            lastLeg = (time, meters)
        }
        autoPause?.fix(speed: location.speedAccuracy >= 0 ? location.speed : -1, at: location.timestamp)
        noteSignal(at: .now)
        saveSensorsIfDue(at: .now)
        // Checked at the time it's handled, not when the fix was taken, which can be a moment before the
        // clock's last tick.
        advanceStepsAndSpeak(at: .now)
    }

    /// Moves through the workout's steps, brings the Lock Screen's step up to date and taps the countdown,
    /// then reads out what's due: a new step first, then a cue, then the split that just ended.
    private func advanceStepsAndSpeak(at date: Date) {
        guard let run, run.status == .active, paceCallouts != nil || spokenCue != nil || steps != nil else { return }
        // Never backwards, so the steps and countdown only ever move on.
        let elapsed = max(run.activeDuration(at: date), lastCheckedElapsed)
        lastCheckedElapsed = elapsed
        let stepText = updateSteps(elapsed: elapsed, meters: run.distanceMeters)
        // Only a new step goes to the Lock Screen at once; the rest follows the usual few seconds.
        showStep(at: date, force: stepText != nil)
        tapCountdown(elapsed: elapsed, meters: run.distanceMeters)
        let callout = paceCallouts?.update(elapsed: elapsed, meters: run.distanceMeters)
        let cue = spokenCue?(elapsed, run.distanceMeters, freshHeartRate(at: date))
        if let text = stepText ?? cue ?? callout?.spokenText {
            speaker.speak(text)
        }
    }

    /// The newest heart rate, or nil when it's older than `heartRateFreshness` at `date`.
    private func freshHeartRate(at date: Date) -> Double? {
        latestHeartRate.flatMap { abs(date.timeIntervalSince($0.date)) <= Self.heartRateFreshness ? $0.beatsPerMinute : nil }
    }

    /// Ends the step under way: a walk break when the runner is ready to run again, or any step cut short.
    func nextStep() {
        guard let run, var tracker = steps, !tracker.isFinished else { return }
        Trace.log(.steps, "Step ended early", ["step": tracker.index + 1, "of": tracker.timeline.count])
        let next = tracker.endCurrentStep(elapsed: run.activeDuration(), meters: run.distanceMeters)
        steps = tracker
        run.saveStepLog(tracker.recorded)
        modelContext.saveQuietly()
        lastCountdown = nil
        showStep()
        speaker.speak(next.map { Self.spokenStep($0, runsUntilFinish: tracker.runsUntilFinish, sport: run.sport) } ?? Self.lastStepDoneText(for: run.sport))
        feel(next.map { StepHaptic.starting($0) } ?? .finished)
    }

    /// The goal the run is working to: a coach session's distance or time when it has no steps, the same as
    /// the run screen shows (a distance to the tenth of the runner's unit, a time to the minute), otherwise the
    /// runner's own distance or time.
    var effectiveGoal: RunGoal? {
        guard let run else { return nil }
        if steps == nil, let coach = run.coachWorkout {
            if let meters = coach.positiveTargetMeters { return .distance(meters: DistanceUnit.current().plannedMeters(meters)) }
            if let seconds = coach.positiveTargetSeconds { return .time(seconds: CoachFormat.plannedSeconds(seconds)) }
        }
        return run.goal
    }

    /// Buzzes once when a distance or timed run, or a coach session, reaches its goal. The run carries on
    /// until the runner finishes it. When the runner hears the run, it's said too; the recorded voice has
    /// no clip for it yet, so it's in the system voice.
    private func checkGoal(at date: Date) {
        guard !goalReached, let run, run.status == .active, let goal = effectiveGoal else { return }
        let elapsed = run.activeDuration(at: date)
        guard goal.isReached(elapsed: elapsed, meters: run.distanceMeters) else { return }
        goalReached = true
        goalReachedElapsed = elapsed
        Trace.log(.run, "Goal reached", runTotals)
        feel(.finished)
        if speaksGoal {
            speaker.speak("Goal reached. Finish when you're ready.")
        }
    }

    /// Buzzes on this device, as the haptics settings ask, whether or not the run screen is showing.
    private func feel(_ haptic: StepHaptic) {
        Trace.log(.haptic, "\(haptic)")
        StepHaptics.play(haptic)
    }

    /// Taps once for each of a timed step's last seconds, or a distance step's last tens of meters. Only
    /// a lower count taps, so a reading that steps back can't tap twice.
    private func tapCountdown(elapsed: TimeInterval, meters: Double) {
        guard let second = steps?.countdown(elapsed: elapsed, meters: meters) else {
            lastCountdown = nil
            return
        }
        guard second < (lastCountdown ?? .max) else { return }
        lastCountdown = second
        feel(.countdown)
    }

    /// Advances the steps and returns what to say about it, if anything.
    private func updateSteps(elapsed: TimeInterval, meters: Double) -> String? {
        guard let run, var tracker = steps else { return nil }
        let event = tracker.update(elapsed: elapsed, meters: meters)
        steps = tracker
        switch event {
        case .started(let step):
            // The step's kind, never its name, which the runner may have typed.
            Trace.log(.steps, "Step started", ["step": tracker.index + 1, "of": tracker.timeline.count, "kind": step.kind.rawValue])
            run.saveStepLog(tracker.recorded)
            // A new step counts down from the top, however short the last one was.
            lastCountdown = nil
            feel(StepHaptic.starting(step))
            return Self.spokenStep(step, runsUntilFinish: tracker.runsUntilFinish, sport: run.sport)
        case .finished:
            Trace.log(.steps, "All steps done")
            run.saveStepLog(tracker.recorded)
            feel(.finished)
            return Self.lastStepDoneText(for: run.sport)
        case .openReminder:
            Trace.log(.steps, "Open step reminder", ["step": tracker.index + 1])
            feel(.reminder)
            // The same words as the walk break's start, which match the button the runner taps.
            return tracker.current?.isWalk == true ? Self.walkBreakText : "Tap when you're ready for the next step."
        case nil:
            return nil
        }
    }

    /// Said when the last step ends, whether on its own or because the runner tapped Next.
    static func lastStepDoneText(for sport: WorkoutSport) -> String {
        "That's the last step. \(sport.noun.capitalized) as you like, then finish when you're done."
    }
    /// Said when a walk break starts, and again as its reminder, so both match the button the runner taps.
    static let walkBreakText = "Walk. Tap when you're ready to run again."

    /// "Walk, 1 minute." "Work, 400 meters." "Recover. Tap when you're ready for the next step." An open last
    /// step, such as a cool down, runs until the runner finishes: "Cool down. Finish the run when you're done."
    /// A distance is said in `unit`, the call-outs' unit unless one is given.
    static func spokenStep(
        _ step: PlannedIntervalStep,
        runsUntilFinish: Bool = false,
        sport: WorkoutSport = .running,
        unit: DistanceUnit = DistanceUnit.current()
    ) -> String {
        let name = step.name
        switch step.goal {
        case .time(let seconds): return "\(name), \(SpokenFormat.duration(seconds))."
        case .distance(let meters): return "\(name), \(SpokenFormat.distance(meters, unit: unit))."
        case .open where runsUntilFinish: return "\(name). Finish the \(sport.noun) when you're done."
        case .open: return step.isWalk ? Self.walkBreakText : "\(name). Tap when you're ready for the next step."
        }
    }
}

/// How GPS is doing during a run, for the run screen.
enum GPSSignal: String, Equatable {
    /// No fix good enough to count has come in yet.
    case searching
    /// Fixes are coming in and counting.
    case good
    /// No fix has counted for a while, such as under trees, between tall buildings or in a tunnel.
    case weak
}

/// What the system last said about location for the run, kept to trace only the changes.
private struct LocationState: Equatable {
    var denied: Bool
    var approximate: Bool
    var unavailable: Bool
    var insufficientlyInUse: Bool
}

extension CoachWorkout {
    /// The session's distance target, for the run screen and the goal. A zero or negative target means none.
    var positiveTargetMeters: Double? {
        targetMeters.flatMap { $0 > 0 ? $0 : nil }
    }

    /// The session's time target, for the run screen and the goal. A zero or negative target means none.
    var positiveTargetSeconds: TimeInterval? {
        targetSeconds.flatMap { $0 > 0 ? $0 : nil }
    }
}
