//
//  RunRecorder.swift
//  Wind Run
//

import CoreLocation
import Foundation
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
    /// Live heart rate, or nil when heart rate is off for this run.
    private(set) var heartRate: HeartRateMonitor?

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
    /// A cue to speak, checked about once a second with the run's active time, distance and recent
    /// heart rate, such as the coach's heart-rate cue. Set it before `start`. When it and a split
    /// read-out land together, only the cue plays.
    var spokenCue: ((_ elapsed: TimeInterval, _ meters: Double, _ beatsPerMinute: Double?) -> String?)?
    /// The newest heart-rate reading, for `spokenCue`.
    private var latestHeartRate: (beatsPerMinute: Double, date: Date)?
    /// For a structured run, where the runner is in its steps. The steps as run are kept with the run.
    private(set) var steps: StepTracker?
    /// The countdown second last tapped, so each of a step's last seconds taps once.
    private var lastCountdown: Int?
    /// The newest step haptic, for the run screen to play. The watch also plays it on the wrist at once.
    private(set) var haptic: StepHapticEvent?
    /// Step counts from the workout session, kept with the run when it ends or pauses.
    private var stepCounts: [StepCountSample] = []
    /// Footsteps and cadence from the motion sensor, or nil when motion isn't in use for this run.
    private(set) var motion: MotionMonitor?
    /// The motion sensor's footsteps, which auto-pause reads too.
    private var footsteps: FootstepLog?
    /// Whether the runner turned step counting on, so the footsteps are shown and kept with the run.
    private var savesFootsteps = false
    /// Stops and starts the run on its own, or nil when auto-pause is off.
    private var autoPause: AutoPause?
    /// True while the run is paused because the runner stood still, not because they tapped Pause.
    private(set) var isAutoPaused = false
    /// Readings older than this count as no reading.
    private static let heartRateFreshness: TimeInterval = 15
    #if os(iOS)
    /// Heart rate and the step under way on the Lock Screen and in the Dynamic Island, while this run
    /// measures heart rate or has steps.
    private var liveActivity: HeartRateActivityController?
    #endif

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var isRecording: Bool {
        guard let run else { return false }
        return !run.isFinished
    }

    func start(
        kind: RunKind = .free,
        intervalPlan: IntervalPlan? = nil,
        coachWorkout: CoachWorkout? = nil,
        measuresHeartRate: Bool = false,
        countsSteps: Bool = UserDefaults.standard.bool(forKey: MotionMonitor.stepsKey),
        autoPauses: Bool = UserDefaults.standard.bool(forKey: AutoPause.storageKey)
    ) {
        guard !isRecording else {
            Logger.recording.warning("A run is already being recorded.")
            return
        }
        let run = Run(kind: coachWorkout == nil ? kind : .coached)
        run.intervalPlanValue = intervalPlan ?? coachWorkout?.intervalPlan
        run.coachWorkoutValue = coachWorkout
        modelContext.insert(run)
        modelContext.saveQuietly()
        self.run = run
        if let timeline = run.intervalPlanValue?.timeline, !timeline.isEmpty {
            steps = StepTracker(timeline: timeline)
        }
        paceCallouts = PaceCalloutTracker(settings: .current())
        startLocationUpdates()
        if countsSteps || autoPauses {
            startMotion(at: run.startDate, savesFootsteps: countsSteps)
        }
        if autoPauses {
            autoPause = AutoPause(usesMotion: motion != nil, start: run.startDate)
        }
        startClock()
        if let tracker = steps, let first = tracker.current {
            speaker.speak(Self.spokenStep(first, runsUntilFinish: tracker.runsUntilFinish))
            feel(StepHaptic.starting(first))
        }
        if measuresHeartRate {
            startHeartRate(at: run.startDate)
        }
        #if os(iOS)
        startLiveActivity(at: run.startDate)
        #endif
    }

    /// The runner paused. Only they can start it again.
    func pause() {
        isAutoPaused = false
        pauseRun()
    }

    func resume() {
        isAutoPaused = false
        autoPause?.runnerResumed(at: .now)
        resumeRun()
    }

    private func pauseRun() {
        run?.saveStepCounts(keptStepCounts)
        run?.pause()
        heartRate?.pause()
        modelContext.saveQuietly()
        showStep()
    }

    private func resumeRun() {
        run?.resume()
        heartRate?.resume()
        modelContext.saveQuietly()
        showStep()
    }

    /// The step counts kept with the run: the motion sensor's when step counting is on and it counted,
    /// otherwise the workout session's.
    private var keptStepCounts: [StepCountSample] {
        if savesFootsteps, let samples = footsteps?.samples, !samples.isEmpty {
            return samples
        }
        return stepCounts
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
        stopLocationUpdates()
        stopHeartRate()
        stopMotion()
        stopLiveActivity()
        stopClock()
        guard let run else { return }
        run.saveStepCounts(keptStepCounts)
        if var tracker = steps {
            tracker.finish(elapsed: run.activeDuration(), meters: run.distanceMeters)
            run.saveStepLog(tracker.recorded)
            steps = tracker
        }
        run.finish()
        modelContext.saveQuietly()
        HealthSync.shared.saveIfEnabled(run, in: modelContext)
    }

    /// Throws the run away, along with its route and heart rate.
    func discard() {
        stopLocationUpdates()
        stopHeartRate()
        stopMotion()
        stopLiveActivity()
        stopClock()
        speaker.stop()
        if let run {
            run.discard()
            modelContext.delete(run)
            modelContext.saveQuietly()
        }
        run = nil
    }

    private func startLocationUpdates() {
        session = CLServiceSession(authorization: .whenInUse)
        #if os(iOS)
        backgroundSession = CLBackgroundActivitySession()
        #endif
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self, !Task.isCancelled else { return }
                    self.locationDenied = update.authorizationDenied || update.authorizationDeniedGlobally
                    Logger.recording.debug("Location update: fix \(update.location != nil), denied \(self.locationDenied), requestInProgress \(update.authorizationRequestInProgress), insufficient \(update.insufficientlyInUse)")
                    if let location = update.location {
                        self.receive(location)
                    }
                }
            } catch {
                Logger.recording.error("Location updates ended: \(error.localizedDescription)")
            }
        }
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
        guard paceCallouts != nil || spokenCue != nil || steps != nil || autoPause != nil || motion != nil else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                let now = Date.now
                self.motion?.tick(at: now)
                self.checkAutoPause(at: now)
                self.checkPaceCallout(at: now)
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
            return
        }
        let monitor = HeartRateMonitor()
        monitor.onSteps = { [weak self] count, interval in
            self?.stepCounts.append(StepCountSample(start: interval.start, end: interval.end, count: count))
        }
        monitor.onReading = { [weak self] beatsPerMinute, date, source in
            self?.latestHeartRate = (beatsPerMinute, date)
            self?.run?.record(HeartRateSample(timestamp: date, beatsPerMinute: beatsPerMinute, source: source))
            #if os(iOS)
            self?.liveActivity?.record(beatsPerMinute, at: date)
            #endif
        }
        guard monitor.start(at: date) else { return }
        heartRate = monitor
    }

    private func stopHeartRate() {
        heartRate?.stop()
        heartRate = nil
    }

    private func startMotion(at date: Date, savesFootsteps: Bool) {
        let monitor = MotionMonitor()
        monitor.onSteps = { [weak self] totalSteps, cadence, date in
            self?.receiveFootsteps(totalSteps, cadence: cadence, at: date)
        }
        monitor.onActivity = { [weak self] activity, date in
            self?.autoPause?.activity(activity, at: date)
        }
        monitor.onFailure = { [weak self] in
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

    private func stopMotion() {
        motion?.stop()
        motion = nil
    }

    private func receiveFootsteps(_ totalSteps: Double, cadence: Double?, at date: Date) {
        guard let run, !run.isFinished, var log = footsteps else { return }
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
        switch autoPause.check(at: date, isPaused: run.status == .paused) {
        case .pause:
            isAutoPaused = true
            pauseRun()
            speaker.speak("Paused.")
            feel(.paused)
        case .resume:
            isAutoPaused = false
            resumeRun()
            speaker.speak("Resumed.")
            feel(.resumed)
        case nil:
            break
        }
    }

    /// Puts the run on the Lock Screen when it measures heart rate or has steps, and lets the Live
    /// Activity's Next button reach this run.
    private func startLiveActivity(at date: Date) {
        #if os(iOS)
        guard heartRate != nil || steps != nil else { return }
        let activity = HeartRateActivityController()
        activity.start(at: date, showsHeartRate: heartRate != nil, step: stepState(at: date))
        liveActivity = activity
        if steps != nil {
            ActiveRunControl.nextStep = { [weak self] in self?.nextStep() }
        }
        #endif
    }

    private func stopLiveActivity() {
        #if os(iOS)
        liveActivity?.end()
        liveActivity = nil
        ActiveRunControl.nextStep = nil
        #endif
    }

    /// Brings the Live Activity's step up to date.
    private func showStep(at date: Date = .now) {
        #if os(iOS)
        guard steps != nil else { return }
        liveActivity?.update(stepState(at: date), at: date)
        #endif
    }

    #if os(iOS)
    /// The step under way as the Live Activity shows it.
    func stepState(at date: Date = .now) -> RunStepState? {
        guard let run, let tracker = steps else { return nil }
        return Self.stepState(tracker, elapsed: run.activeDuration(at: date), meters: run.distanceMeters, isGoing: run.status == .active, at: date, unit: PaceCalloutSettings.current().unit)
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
                state.detail = "\(RunFormat.duration(left)) left"
            }
        case .distance(let left):
            state.detail = "\(RunFormat.distance(left, unit: unit)) left"
        case .open, nil:
            if isGoing {
                state.startDate = start
            } else {
                state.detail = RunFormat.duration(inStep)
            }
            // An open last step, such as a cool down, runs until the run is finished: nothing to tap on to.
            if tracker.waitsForTap {
                state.nextTitle = step.isWalk ? "Run again" : "Next step"
            }
        }
        return state
    }
    #endif

    private func receive(_ location: CLLocation) {
        guard let run, !run.isFinished else { return }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.maximumHorizontalAccuracy
        else { return }
        run.record(RouteSample(location))
        autoPause?.fix(speed: location.speedAccuracy >= 0 ? location.speed : -1, at: location.timestamp)
        checkPaceCallout(at: location.timestamp)
    }

    /// Moves through the workout's steps, then reads out what's due: a new step first, then a cue,
    /// then the split that just ended.
    private func checkPaceCallout(at date: Date) {
        guard let run, run.status == .active, paceCallouts != nil || spokenCue != nil || steps != nil else { return }
        let elapsed = run.activeDuration(at: date)
        let stepText = updateSteps(elapsed: elapsed, meters: run.distanceMeters)
        showStep(at: date)
        tapCountdown(elapsed: elapsed)
        let callout = paceCallouts?.update(elapsed: elapsed, meters: run.distanceMeters)
        let heartRate = latestHeartRate.flatMap { abs(date.timeIntervalSince($0.date)) <= Self.heartRateFreshness ? $0.beatsPerMinute : nil }
        let cue = spokenCue?(elapsed, run.distanceMeters, heartRate)
        if let text = stepText ?? cue ?? callout?.spokenText {
            speaker.speak(text)
        }
    }

    /// Ends the step under way: a walk break when the runner is ready to run again, or any step cut short.
    func nextStep() {
        guard let run, var tracker = steps, !tracker.isFinished else { return }
        let next = tracker.endCurrentStep(elapsed: run.activeDuration(), meters: run.distanceMeters)
        steps = tracker
        run.saveStepLog(tracker.recorded)
        modelContext.saveQuietly()
        lastCountdown = nil
        showStep()
        speaker.speak(next.map { Self.spokenStep($0, runsUntilFinish: tracker.runsUntilFinish) } ?? "That's the last step. Run as you like, then finish when you're done.")
        feel(next.map { StepHaptic.starting($0) } ?? .finished)
    }

    private func feel(_ haptic: StepHaptic) {
        self.haptic = StepHapticEvent(haptic: haptic, number: (self.haptic?.number ?? 0) + 1)
        StepHaptics.play(haptic)
    }

    /// Taps once for each of a timed step's last seconds.
    private func tapCountdown(elapsed: TimeInterval) {
        guard let second = steps?.countdown(elapsed: elapsed) else {
            lastCountdown = nil
            return
        }
        guard second != lastCountdown else { return }
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
            run.saveStepLog(tracker.recorded)
            feel(StepHaptic.starting(step))
            return Self.spokenStep(step, runsUntilFinish: tracker.runsUntilFinish)
        case .finished:
            run.saveStepLog(tracker.recorded)
            feel(.finished)
            return "That's the last step. Run as you like, then finish when you're done."
        case .openReminder:
            feel(.reminder)
            return tracker.current?.isWalk == true ? "Run again when you're ready, and tap to start." : "Tap when you're ready for the next step."
        case nil:
            return nil
        }
    }

    /// "Walk, 1 minute." "Work, 400 meters." "Recover. Tap when you're ready for the next step." An open last
    /// step, such as a cool down, runs until the runner finishes: "Cool down. Finish the run when you're done."
    static func spokenStep(_ step: PlannedIntervalStep, runsUntilFinish: Bool = false) -> String {
        let name = step.name
        let unit = PaceCalloutSettings.current().unit
        switch step.goal {
        case .time(let seconds): return "\(name), \(SpokenFormat.duration(seconds))."
        case .distance(let meters): return "\(name), \(SpokenFormat.distance(meters, unit: unit))."
        case .open where runsUntilFinish: return "\(name). Finish the run when you're done."
        case .open: return step.isWalk ? "Walk. Tap when you're ready to run again." : "\(name). Tap when you're ready for the next step."
        }
    }
}
