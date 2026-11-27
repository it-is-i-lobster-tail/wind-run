//
//  LiveRun.swift
//  Wind Run
//

import Foundation
import HealthKit
import Observation
import WatchConnectivity

/// A run under way on one device, as the other device shows it: the iPhone shows a run recorded on the
/// watch, and the watch shows a run recorded on the iPhone. Only the device the run was started on records
/// it, so a run is never kept twice. It carries readings only: no route, place or time of day.
nonisolated struct LiveRunStatus: Codable, Equatable, Sendable {
    enum Device: String, Codable, Sendable {
        case watch
        case iPhone
    }

    enum State: String, Codable, Sendable {
        case running
        case paused
        /// Finished or discarded: the other device stops showing it.
        case ended
    }

    var runID: UUID
    var device: Device
    var sport: WorkoutSport
    var state: State
    /// Running time, leaving out pauses, when this was sent.
    var elapsed: TimeInterval
    var meters: Double
    /// Seconds per kilometer, nil with nothing to show.
    var currentPace: TimeInterval?
    var averagePace: TimeInterval?
    var beatsPerMinute: Double?

    /// The running time at `date`, counting on from when this arrived while the run is going.
    func elapsed(at date: Date, receivedAt: Date) -> TimeInterval {
        guard state == .running else { return elapsed }
        return elapsed + max(0, date.timeIntervalSince(receivedAt))
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    static func decode(_ data: Data) -> LiveRunStatus? {
        try? JSONDecoder().decode(LiveRunStatus.self, from: data)
    }
}

/// What the other device can do to the run it shows.
nonisolated enum LiveRunCommand: String, Codable, Sendable {
    case pause
    case resume
    /// Finishes and saves the run, as Finish does on the device recording it.
    case finish
}

/// Shows a run recorded on one device live on the other, and passes Pause, Resume and Finish back.
///
/// The recording device sends a status every couple of seconds over Watch Connectivity while the other is
/// reachable, and once more when the run ends. Starting a run on the iPhone also opens Wind Run on the
/// watch, through Health, which is the only way an iPhone app can open its watch app.
@Observable
final class LiveRunLink {
    static let shared = LiveRunLink()

    /// The run under way on the other device, or nil.
    private(set) var remote: LiveRunStatus?
    /// When `remote` last arrived, by this device's clock.
    private(set) var receivedAt: Date?

    /// No word for this long and the other device's run is shown as out of reach.
    static let quietAfter: TimeInterval = 15
    /// No word for this long and it's dropped.
    static let dropAfter: TimeInterval = 10 * 60
    /// How often the recording device sends its status.
    static let sendInterval: Duration = .seconds(2)

    /// The run this device is recording, which the other device shows.
    @ObservationIgnored private weak var recorder: RunRecorder?
    @ObservationIgnored private var sendTask: Task<Void, Never>?
    @ObservationIgnored private var lastSent: LiveRunStatus?
    @ObservationIgnored private var dropTask: Task<Void, Never>?
    /// Runs from the other device that ended, so a reading that arrives after the end doesn't show it again.
    @ObservationIgnored private var endedRunIDs: Set<UUID> = []
    /// Called on the watch after the iPhone finished a run there, so it's sent across like one finished on
    /// the watch's own screen.
    @ObservationIgnored var finishedFromOtherDevice: ((Run) -> Void)?
    #if os(watchOS)
    /// Keeps the watch app on screen with the wrist down while it shows the iPhone's run. It reads nothing
    /// and saves nothing.
    @ObservationIgnored private var companionSession: HeartRateMonitor?
    #endif

    /// True while a run is being recorded here or shown from the other device.
    var isRunUnderWay: Bool { recorder?.isRecording == true || remote != nil }

    /// True when the other device's run hasn't been heard from for a while, such as out of Bluetooth range.
    func isQuiet(at date: Date) -> Bool {
        guard let receivedAt else { return true }
        return date.timeIntervalSince(receivedAt) > Self.quietAfter
    }

    // MARK: The recording device

    /// A run started recording here. The other device is told, and on the iPhone the watch app is opened.
    func started(_ recorder: RunRecorder) {
        self.recorder = recorder
        lastSent = nil
        // A run here replaces showing one from the other device.
        clearRemote()
        #if os(iOS)
        openWatchApp(for: recorder.run?.sport ?? .running)
        #endif
        sendTask?.cancel()
        sendTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.sendStatus()
                try? await Task.sleep(for: Self.sendInterval)
            }
        }
    }

    /// The other device asked, such as the watch app just opening: the run here is sent at once.
    func sendNow() {
        sendStatus(force: true)
    }

    /// Asks the other device for a run under way there, so one started before this app opened shows
    /// straight away. Only while the other device is reachable; a run there sends again anyway.
    func askForRemote() {
        guard remote == nil, recorder == nil else { return }
        SettingsSync.shared.sendLive([SettingsSync.liveRunHelloField: true], queuedIfAway: false)
    }

    /// Paused or resumed here: sent at once rather than at the next beat.
    func changed(_ recorder: RunRecorder) {
        guard recorder === self.recorder else { return }
        sendStatus(force: true)
    }

    /// The run here was finished or discarded.
    func ended(_ recorder: RunRecorder) {
        guard recorder === self.recorder else { return }
        sendTask?.cancel()
        sendTask = nil
        if let run = recorder.run, var status = Self.status(for: run, recorder: recorder) {
            status.state = .ended
            send(status, queuedIfAway: true)
        }
        self.recorder = nil
        lastSent = nil
    }

    private func sendStatus(force: Bool = false) {
        guard let recorder, let run = recorder.run, !run.isFinished,
              let status = Self.status(for: run, recorder: recorder) else { return }
        // A paused run doesn't change, so it isn't sent again every beat.
        if !force, status.state == .paused, lastSent?.state == .paused, lastSent?.runID == status.runID { return }
        lastSent = status
        // Only the end is queued for later: a reading that arrives late would show a run that's moved on.
        send(status, queuedIfAway: false)
    }

    static func status(for run: Run, recorder: RunRecorder, at date: Date = .now) -> LiveRunStatus? {
        let snapshot = recorder.snapshot(at: date, unit: .kilometers)
        #if os(watchOS)
        let device = LiveRunStatus.Device.watch
        #else
        let device = LiveRunStatus.Device.iPhone
        #endif
        return LiveRunStatus(
            runID: run.runID,
            device: device,
            sport: run.sport,
            state: run.isFinished ? .ended : (run.status == .paused ? .paused : .running),
            elapsed: run.activeDuration(at: date),
            meters: run.distanceMeters,
            currentPace: snapshot?.currentPace,
            averagePace: snapshot?.averagePace,
            beatsPerMinute: snapshot?.beatsPerMinute
        )
    }

    private func send(_ status: LiveRunStatus, queuedIfAway: Bool) {
        guard let data = status.encoded() else { return }
        SettingsSync.shared.sendLive([SettingsSync.liveRunField: data], queuedIfAway: queuedIfAway)
    }

    /// Pause, Resume or Finish pressed on the other device, for the run recorded here.
    func perform(_ command: LiveRunCommand, runID: UUID) {
        guard let recorder, let run = recorder.run, run.runID == runID, !run.isFinished else {
            Trace.log(.watch, "Live run command for no run here", ["command": command.rawValue])
            return
        }
        Trace.log(.watch, "Live run command from the other device", ["command": command.rawValue])
        switch command {
        case .pause: recorder.pause()
        case .resume: recorder.resume()
        case .finish:
            recorder.finish()
            finishedFromOtherDevice?(run)
        }
    }

    // MARK: The showing device

    /// A status from the other device.
    func receive(_ status: LiveRunStatus, at date: Date = .now) {
        // This device is recording its own run; it doesn't show the other one over it.
        if let run = recorder?.run, !run.isFinished { return }
        guard !endedRunIDs.contains(status.runID) else { return }
        if status.state == .ended {
            endedRunIDs.insert(status.runID)
            if remote?.runID == status.runID || remote == nil { clearRemote() }
            return
        }
        if remote != status { remote = status }
        receivedAt = date
        #if os(watchOS)
        keepWatchAwake(for: status)
        #endif
        dropTask?.cancel()
        dropTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.dropAfter))
            guard !Task.isCancelled else { return }
            Trace.log(.watch, "Live run from the other device went quiet")
            self?.clearRemote()
        }
    }

    /// Pause, Resume or Finish for the run shown from the other device.
    func send(_ command: LiveRunCommand) {
        guard let remote else { return }
        Trace.log(.tap, "Live run \(command.rawValue) for the other device")
        SettingsSync.shared.sendLive([
            SettingsSync.liveRunCommandField: command.rawValue,
            SettingsSync.liveRunIDField: remote.runID.uuidString,
        ], queuedIfAway: true)
        // Shown at once; the next status confirms it.
        switch command {
        case .pause: self.remote?.state = .paused
        case .resume: self.remote?.state = .running
        case .finish:
            endedRunIDs.insert(remote.runID)
            clearRemote()
        }
        if command != .finish { receivedAt = .now }
    }

    /// Stops showing the other device's run here. The run carries on there.
    func hideRemote() {
        guard let remote else { return }
        Trace.log(.tap, "Live run hidden")
        endedRunIDs.insert(remote.runID)
        clearRemote()
    }

    private func clearRemote() {
        dropTask?.cancel()
        dropTask = nil
        remote = nil
        receivedAt = nil
        #if os(watchOS)
        companionSession?.stop()
        companionSession = nil
        #endif
    }

    #if os(iOS)
    /// Opens Wind Run on the paired watch, which then shows this run. Health does this for workout apps.
    private func openWatchApp(for sport: WorkoutSport) {
        let session = WCSession.default
        guard WCSession.isSupported(), session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              HKHealthStore.isHealthDataAvailable() else { return }
        HKHealthStore().startWatchApp(with: sport.healthConfiguration) { opened, error in
            Trace.log(.watch, "Opened the watch app for the run", ["opened": opened, "failed": error != nil])
        }
    }
    #endif

    #if os(watchOS)
    /// The iPhone opened the watch app for its run. The run shows as soon as its first status comes.
    func openedForIPhoneRun(_ configuration: HKWorkoutConfiguration) {
        Trace.log(.watch, "Opened for a run on the iPhone")
        startCompanionSession(configuration)
        // Nothing heard after a minute: the session stops.
        dropTask?.cancel()
        dropTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled, let self, self.remote == nil else { return }
            self.clearRemote()
        }
    }

    private func keepWatchAwake(for status: LiveRunStatus) {
        guard status.device == .iPhone, companionSession == nil, HealthSync.shared.access == .allowed else { return }
        startCompanionSession(status.sport.healthConfiguration)
    }

    private func startCompanionSession(_ configuration: HKWorkoutConfiguration) {
        guard companionSession == nil, recorder == nil else { return }
        let monitor = HeartRateMonitor()
        let sport: WorkoutSport = switch configuration.activityType {
        case .cycling: .cycling
        case .hiking: .hiking
        default: .running
        }
        if monitor.start(at: .now, readsHeartRate: false, sport: sport) {
            companionSession = monitor
        }
    }
    #endif
}
