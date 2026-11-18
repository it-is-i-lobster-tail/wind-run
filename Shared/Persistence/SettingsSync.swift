//
//  SettingsSync.swift
//  Wind Run
//

import Foundation
import OSLog
import WatchConnectivity

/// Keeps units, pace call-outs and haptics the same on iPhone and Apple Watch, whichever one they were changed on.
/// It also hands today's coach sessions and the saved interval workouts to the watch, and brings coached runs
/// done on the watch back to the iPhone, where the coach counts them.
///
/// Everything goes straight between the paired phone and watch. Nothing passes through a server. Only
/// coached runs are sent; other watch runs stay on the watch.
///
/// Each setting carries when it last changed, so a change on each device merges key by key: units changed
/// on the iPhone and haptics changed on the watch both stay.
final class SettingsSync: NSObject {
    static let shared = SettingsSync()

    /// The settings that follow the runner between devices.
    static let keys = [
        DistanceUnit.storageKey,
        PaceCalloutSettings.modeKey,
        PaceCalloutSettings.distanceKey,
        PaceCalloutSettings.secondsKey,
        PaceCalloutSettings.pacesKey,
        HapticDevices.storageKey,
        HapticPattern.storageKey,
        DisplayScreen.storageKey,
        // The saved displays and which one each kind of run shows; a saved workout's pick goes with it.
        DisplayLibrary.screensKey,
        DisplayLibrary.defaultKey,
        // For calories on the watch's run screen. It goes straight to the paired watch, never through a server.
        BodyWeight.storageKey,
    ] + DisplayRunKind.storageKeys
    private static let changedAtKey = "settingsChangedAt"
    /// When each synced setting last changed, on this device or the other. Kept on the device only.
    private static let keyChangedAtKey = "settingsKeyChangedAt"
    /// The synced settings stored as numbers, which travel as text like the rest.
    private static let numberKeys: Set<String> = [
        PaceCalloutSettings.distanceKey,
        PaceCalloutSettings.secondsKey,
        BodyWeight.storageKey,
    ]
    // Read from WatchConnectivity's own queue, so they can't be main-actor isolated.
    private nonisolated static let settingsField = "settings"
    private nonisolated static let changedAtField = "changedAt"
    private nonisolated static let keyChangedAtField = "keyChangedAt"
    private nonisolated static let removedField = "removed"
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

    /// When each synced setting last changed. Empty for settings that never changed since this came in.
    var keyChangedAt: [String: Date] {
        get { (defaults.dictionary(forKey: Self.keyChangedAtKey) as? [String: Date]) ?? [:] }
        set { defaults.set(newValue, forKey: Self.keyChangedAtKey) }
    }

    private func localSettingsChanged() {
        guard !isApplyingReceived else { return }
        let current = snapshot()
        guard current != lastSynced else { return }
        let now = Date.now
        var dates = keyChangedAt
        for key in Self.keys where current[key] != lastSynced[key] {
            dates[key] = now
        }
        lastSynced = current
        keyChangedAt = dates
        defaults.set(now, forKey: Self.changedAtKey)
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
            let dates = keyChangedAt.filter { Self.keys.contains($0.key) }
            context[Self.keyChangedAtField] = dates
            // Settings changed back to nothing, so the other device drops them too.
            let removed = dates.keys.filter { lastSynced[$0] == nil }.sorted()
            if !removed.isEmpty {
                context[Self.removedField] = removed
            }
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
        Trace.log(.watch, "Sending settings and workouts to the other device", ["parts": context.keys.sorted().joined(separator: "+")])
        do {
            try session.updateApplicationContext(context)
        } catch {
            Logger.settings.error("Couldn't send settings to the other device: \(error)")
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

    /// Sends a finished coached run to the iPhone. It's kept on the watch until the iPhone has it, and sent
    /// again each time the connection starts until then, so a run finished while the connection wasn't
    /// ready still gets there.
    func sendRun(_ record: WatchRunRecord) {
        guard let data = record.encoded(), let url = Self.pendingRunURL(for: record.runID.uuidString) else {
            Logger.settings.error("Couldn't keep a coached run to send to the iPhone.")
            return
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.settings.error("Couldn't keep a coached run to send to the iPhone: \(error)")
            return
        }
        sendPendingRuns()
    }

    /// Hands every coached run the iPhone doesn't have yet to the system, which holds them until the iPhone
    /// is in reach. Runs already on their way aren't handed over twice.
    func sendPendingRuns() {
        let session = WCSession.default
        let pending = Self.pendingRuns()
        guard !pending.isEmpty else { return }
        guard session.activationState == .activated else {
            Trace.log(.watch, "Coached runs waiting for the connection", ["pending": pending.count])
            return
        }
        let underway = Set(session.outstandingFileTransfers.compactMap { $0.file.metadata?[Self.runIDField] as? String })
        var sent = 0
        for (id, url) in pending where !underway.contains(id) {
            session.transferFile(url, metadata: [Self.runIDField: id])
            sent += 1
        }
        Trace.log(.watch, "Coached runs queued for the iPhone", ["pending": pending.count, "sent": sent])
    }

    private nonisolated static let runIDField = "runID"

    /// Where a coached run waits until the iPhone has it: Application Support, which watchOS doesn't clear.
    nonisolated static func pendingRunURL(for id: String) -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PendingRuns", isDirectory: true)
            .appendingPathComponent("run-\(id).json")
    }

    /// The coached runs waiting to reach the iPhone, by run id.
    private static func pendingRuns() -> [(id: String, url: URL)] {
        guard let folder = pendingRunURL(for: "")?.deletingLastPathComponent(),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return files.compactMap { url in
            let name = url.deletingPathExtension().lastPathComponent
            guard name.hasPrefix("run-") else { return nil }
            return (String(name.dropFirst(4)), url)
        }
    }
    #endif

    /// Applies the other device's settings, each one only if it changed there after it last changed here.
    /// `keyChangedAt` is nil from an older app, which only says when anything last changed; each setting then
    /// goes with that.
    func receive(_ values: [String: String], changedAt received: Date, keyChangedAt theirDates: [String: Date]? = nil, removed: Set<String> = []) {
        let ourDates = keyChangedAt
        let ourChangedAt = changedAt
        var merged = ourDates
        var applied = 0
        isApplyingReceived = true
        defer { isApplyingReceived = false }
        for key in Self.keys {
            let ours = ourDates[key] ?? ourChangedAt
            let theirs = Self.theirChangeDate(for: key, theirDates: theirDates, ourDates: ourDates, received: received)
            guard theirs > ours else { continue }
            if removed.contains(key) {
                defaults.removeObject(forKey: key)
            } else if let value = values[key] {
                if Self.numberKeys.contains(key) {
                    guard let number = Double(value) else { continue }
                    defaults.set(number, forKey: key)
                } else {
                    defaults.set(value, forKey: key)
                }
            } else {
                continue
            }
            merged[key] = theirs
            applied += 1
        }
        if theirDates != nil {
            keyChangedAt = merged
        }
        if received > ourChangedAt {
            defaults.set(received, forKey: Self.changedAtKey)
        }
        lastSynced = snapshot()
        // How old the settings are, never the time they changed.
        Trace.log(.watch, "Settings from the other device", [
            "applied": applied,
            "keys": values.count,
            "ageSeconds": max(0, Date.now.timeIntervalSince(received)),
        ])
    }

    /// When the other device last changed `key`, to weigh against when it last changed here.
    static func theirChangeDate(for key: String, theirDates: [String: Date]?, ourDates: [String: Date], received: Date) -> Date {
        // An older app only says when anything last changed.
        guard let theirDates else { return received }
        if let date = theirDates[key] { return date }
        // A setting the other device never changed loses to one changed here.
        return ourDates[key] == nil ? received : .distantPast
    }

    fileprivate func activated(with received: ReceivedSettings?, coachToday: Data?, savedWorkouts: Data?, failed: Bool) {
        if failed {
            Logger.settings.error("Watch connection didn't start")
        }
        if let received {
            receive(received.values, changedAt: received.changedAt, keyChangedAt: received.keyChangedAt, removed: received.removed)
        }
        #if os(watchOS)
        if let coachToday { receiveCoachToday(coachToday) }
        if let savedWorkouts { receiveSavedWorkouts(savedWorkouts) }
        sendPendingRuns()
        #endif
        send()
    }

    /// The settings part of an application context.
    fileprivate struct ReceivedSettings: Sendable {
        var values: [String: String]
        var changedAt: Date
        var keyChangedAt: [String: Date]?
        var removed: Set<String>

        nonisolated init?(_ context: [String: Any]) {
            guard let values = context[SettingsSync.settingsField] as? [String: String],
                  let changedAt = context[SettingsSync.changedAtField] as? Date
            else { return nil }
            self.values = values
            self.changedAt = changedAt
            keyChangedAt = context[SettingsSync.keyChangedAtField] as? [String: Date]
            removed = Set(context[SettingsSync.removedField] as? [String] ?? [])
        }
    }
}

extension SettingsSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Trace.log(.watch, "Connection started", ["state": activationState.rawValue, "failed": error != nil])
        if let error {
            Trace.error("Watch connection didn't start", error)
        }
        let context = session.receivedApplicationContext
        let received = ReceivedSettings(context)
        let coachToday = context[Self.coachTodayField] as? Data
        let savedWorkouts = context[Self.savedWorkoutsField] as? Data
        let failed = error != nil
        Task { @MainActor in
            self.activated(with: received, coachToday: coachToday, savedWorkouts: savedWorkouts, failed: failed)
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        Trace.log(.watch, "Received settings and workouts", ["parts": applicationContext.keys.sorted().joined(separator: "+")])
        #if os(watchOS)
        if let coachToday = applicationContext[Self.coachTodayField] as? Data {
            Task { @MainActor in self.receiveCoachToday(coachToday) }
        }
        if let savedWorkouts = applicationContext[Self.savedWorkoutsField] as? Data {
            Task { @MainActor in self.receiveSavedWorkouts(savedWorkouts) }
        }
        #endif
        guard let received = ReceivedSettings(applicationContext) else { return }
        Task { @MainActor in
            self.receive(received.values, changedAt: received.changedAt, keyChangedAt: received.keyChangedAt, removed: received.removed)
        }
    }

    #if os(iOS)
    /// A coached run from the watch. The file goes away when this returns, so it's read here.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        Trace.log(.watch, "Received a coached run from the watch")
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
            // Kept, and sent again when the connection next starts.
            Trace.error("A coached run didn't reach the iPhone", error)
            return
        }
        Trace.log(.watch, "A coached run reached the iPhone")
        if let id = fileTransfer.file.metadata?[Self.runIDField] as? String, let url = Self.pendingRunURL(for: id) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    #endif

    #if os(iOS)
    /// The watch app was just installed, or the runner paired a watch. Catch it up.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Trace.log(.watch, "Watch state changed", ["paired": session.isPaired, "appInstalled": session.isWatchAppInstalled])
        Task { @MainActor in self.send() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Trace.log(.watch, "Connection inactive")
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Trace.log(.watch, "Connection deactivated")
        // The runner switched to another watch. Start again so this one gets settings too.
        session.activate()
    }
    #endif
}
