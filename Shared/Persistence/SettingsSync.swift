//
//  SettingsSync.swift
//  Wind Run
//

import Foundation
import OSLog
import WatchConnectivity

/// Keeps units and pace call-outs the same on iPhone and Apple Watch, whichever one they were changed on.
/// It also hands today's coach sessions and the saved interval workouts to the watch, and brings coached runs
/// done on the watch back to the iPhone, where the coach counts them.
///
/// Everything goes straight between the paired phone and watch. Nothing passes through a server. Only
/// coached runs are sent; other watch runs stay on the watch.
final class SettingsSync: NSObject {
    static let shared = SettingsSync()

    /// The settings that follow the runner between devices.
    static let keys = [
        DistanceUnit.storageKey,
        PaceCalloutSettings.modeKey,
        PaceCalloutSettings.distanceKey,
        PaceCalloutSettings.secondsKey,
    ]
    private static let changedAtKey = "settingsChangedAt"
    // Read from WatchConnectivity's own queue, so they can't be main-actor isolated.
    private nonisolated static let settingsField = "settings"
    private nonisolated static let changedAtField = "changedAt"
    private nonisolated static let coachTodayField = "coachToday"
    /// Today's coach sessions as JSON: the ones last sent on the iPhone, the ones last received on the watch.
    /// Kept on the device only.
    static let coachTodayKey = "watchCoachToday"
    private nonisolated static let savedWorkoutsField = "savedWorkouts"
    /// The Intervals page's saved workouts as JSON: the ones last sent on the iPhone, the ones last received
    /// on the watch. Kept on the device only; the workouts themselves sync through iCloud with the runs.
    static let savedWorkoutsKey = "watchSavedWorkouts"

    private let defaults: UserDefaults
    /// The values last sent or received, so applying a received change doesn't echo it back.
    private var lastSynced: [String: String] = [:]
    /// True while writing values that came from the other device, which aren't a local change.
    private var isApplyingReceived = false
    private var observer: NSObjectProtocol?
    #if os(iOS)
    /// A coached run that came from the watch, as `WatchRunRecord` JSON. Set it before `start`.
    var runReceived: ((Data) -> Void)?
    #endif

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func start() {
        guard WCSession.isSupported(), observer == nil else { return }
        observeDefaults()
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Starts treating changes to the synced keys as the runner's own, to send to the other device.
    func observeDefaults() {
        lastSynced = snapshot()
        observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.localSettingsChanged() }
        }
    }

    /// The synced values as strings, which property lists and comparisons both handle simply.
    private func snapshot() -> [String: String] {
        var values: [String: String] = [:]
        for key in Self.keys {
            if let value = defaults.object(forKey: key) {
                values[key] = "\(value)"
            }
        }
        return values
    }

    var changedAt: Date {
        defaults.object(forKey: Self.changedAtKey) as? Date ?? .distantPast
    }

    private func localSettingsChanged() {
        guard !isApplyingReceived else { return }
        let current = snapshot()
        guard current != lastSynced else { return }
        lastSynced = current
        defaults.set(Date.now, forKey: Self.changedAtKey)
        send()
    }

    fileprivate func send() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        // The context replaces the last one, so it always carries everything.
        var context: [String: Any] = [:]
        if changedAt > .distantPast {
            context[Self.settingsField] = lastSynced
            context[Self.changedAtField] = changedAt
        }
        #if os(iOS)
        if let coachToday = defaults.data(forKey: Self.coachTodayKey) {
            context[Self.coachTodayField] = coachToday
        }
        if let savedWorkouts = defaults.data(forKey: Self.savedWorkoutsKey) {
            context[Self.savedWorkoutsField] = savedWorkouts
        }
        #endif
        guard !context.isEmpty else { return }
        do {
            try session.updateApplicationContext(context)
        } catch {
            Logger.settings.error("Couldn't send settings to the other device: \(error.localizedDescription)")
        }
    }

    #if os(iOS)
    /// Hands today's coach sessions to the watch, when they changed.
    func sendCoachToday(_ sessions: [WatchCoachSession]) {
        guard let data = WatchCoachSession.encode(sessions), data != defaults.data(forKey: Self.coachTodayKey) else { return }
        defaults.set(data, forKey: Self.coachTodayKey)
        send()
    }

    /// Hands the Intervals page's saved workouts to the watch, when they changed.
    func sendSavedWorkouts(_ workouts: [WatchSavedWorkout]) {
        guard let data = WatchSavedWorkout.encode(workouts), data != defaults.data(forKey: Self.savedWorkoutsKey) else { return }
        defaults.set(data, forKey: Self.savedWorkoutsKey)
        send()
    }
    #endif

    #if os(watchOS)
    fileprivate func receiveCoachToday(_ data: Data) {
        defaults.set(data, forKey: Self.coachTodayKey)
    }

    fileprivate func receiveSavedWorkouts(_ data: Data) {
        defaults.set(data, forKey: Self.savedWorkoutsKey)
    }

    /// Sends a finished coached run to the iPhone. The system holds it until the iPhone is in reach, even
    /// across launches.
    func sendRun(_ record: WatchRunRecord) {
        let session = WCSession.default
        guard session.activationState == .activated, let data = record.encoded() else {
            Logger.settings.error("Couldn't send a coached run to the iPhone: the connection isn't ready.")
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("run-\(record.runID.uuidString).json")
        do {
            try data.write(to: url, options: .atomic)
            session.transferFile(url, metadata: nil)
        } catch {
            Logger.settings.error("Couldn't send a coached run to the iPhone: \(error.localizedDescription)")
        }
    }
    #endif

    func receive(_ values: [String: String], changedAt received: Date) {
        // Whichever device changed last wins.
        guard received > changedAt else { return }
        isApplyingReceived = true
        defer { isApplyingReceived = false }
        for key in Self.keys {
            guard let value = values[key] else { continue }
            switch key {
            case PaceCalloutSettings.distanceKey, PaceCalloutSettings.secondsKey:
                if let number = Double(value) { defaults.set(number, forKey: key) }
            default:
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(received, forKey: Self.changedAtKey)
        lastSynced = snapshot()
        Logger.settings.debug("Applied settings from the other device")
    }

    fileprivate func activated(with context: [String: String]?, changedAt received: Date?, coachToday: Data?, savedWorkouts: Data?, error: String?) {
        if let error {
            Logger.settings.error("Watch connection didn't start: \(error)")
        }
        if let context, let received {
            receive(context, changedAt: received)
        }
        #if os(watchOS)
        if let coachToday { receiveCoachToday(coachToday) }
        if let savedWorkouts { receiveSavedWorkouts(savedWorkouts) }
        #endif
        send()
    }
}

extension SettingsSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let values = context[Self.settingsField] as? [String: String]
        let changedAt = context[Self.changedAtField] as? Date
        let coachToday = context[Self.coachTodayField] as? Data
        let savedWorkouts = context[Self.savedWorkoutsField] as? Data
        let message = error?.localizedDescription
        Task { @MainActor in
            self.activated(with: values, changedAt: changedAt, coachToday: coachToday, savedWorkouts: savedWorkouts, error: message)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        #if os(watchOS)
        if let coachToday = applicationContext[Self.coachTodayField] as? Data {
            Task { @MainActor in self.receiveCoachToday(coachToday) }
        }
        if let savedWorkouts = applicationContext[Self.savedWorkoutsField] as? Data {
            Task { @MainActor in self.receiveSavedWorkouts(savedWorkouts) }
        }
        #endif
        guard let values = applicationContext[Self.settingsField] as? [String: String],
              let changedAt = applicationContext[Self.changedAtField] as? Date
        else { return }
        Task { @MainActor in self.receive(values, changedAt: changedAt) }
    }

    #if os(iOS)
    /// A coached run from the watch. The file goes away when this returns, so it's read here.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let data = try? Data(contentsOf: file.fileURL) else {
            Logger.settings.error("Couldn't read a run sent from the watch.")
            return
        }
        Task { @MainActor in self.runReceived?(data) }
    }
    #endif

    #if os(watchOS)
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error {
            Logger.settings.error("A run didn't reach the iPhone: \(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }
    #endif

    #if os(iOS)
    /// The watch app was just installed, or the runner paired a watch. Catch it up.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.send() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The runner switched to another watch. Start again so this one gets settings too.
        session.activate()
    }
    #endif
}
