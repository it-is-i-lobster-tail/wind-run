//
//  SettingsSync.swift
//  Wind Run
//

import Foundation
import OSLog
import WatchConnectivity
#if os(watchOS)
import SwiftData
#endif

/// Keeps units, pace call-outs and haptics the same on iPhone and Apple Watch, whichever one they were changed on.
/// Today's coach sessions and saved workouts go to the watch. Finished watch runs go back to the paired
/// iPhone, which confirms each save. Its existing iCloud setting controls whether they sync onward.
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
    static let numberKeys: Set<String> = [
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
    private nonisolated static let runReceiptSupportField = "supportsRunReceipts"
    private nonisolated static let receivedRunField = "savedRunID"
    private nonisolated static let runIDField = "runID"
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
    /// Commits a run received from the watch and returns the ID to acknowledge.
    var runReceived: ((Data) -> UUID?)?
    #elseif os(watchOS)
    var watchRunContext: ModelContext?
    private var runAttempts: [UUID: ContinuousClock.Instant] = [:]
    private var runRetry: Task<Void, Never>?
    private static let runRetryInterval: Duration = .seconds(30)
    private nonisolated static let expectsReceiptField = "expectsRunReceipt"
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
        context[Self.runReceiptSupportField] = true
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

    /// Stages a finished run, including one finished during recovery, even while the phone is offline.
    func sendRun(_ run: Run) {
        let confirmed = WatchRunHistory.receipts(from: defaults.data(forKey: WatchRunHistory.receiptsKey))
        guard !confirmed.contains(run.runID), let record = WatchRunRecord(run) else { return }
        _ = stage(record)
        sendPendingRuns()
    }

    private func stage(_ record: WatchRunRecord) -> URL? {
        guard let data = record.encoded(), let url = Self.pendingRunURL(for: record.runID) else {
            Logger.settings.error("Couldn't prepare a watch run for transfer.")
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            Logger.settings.error("Couldn't stage a watch run: \(error)")
            return nil
        }
    }

    /// Retries runs awaiting a receipt and stages completed runs from before this version of the app.
    func sendPendingRuns() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isCompanionAppInstalled else { return }
        let canConfirm = session.receivedApplicationContext[Self.runReceiptSupportField] as? Bool == true
        let confirmed = WatchRunHistory.receipts(from: defaults.data(forKey: WatchRunHistory.receiptsKey))
        var pending = Self.pendingRuns().filter { !confirmed.contains($0.key) }
        if canConfirm, let watchRunContext {
            do {
                let ended = try watchRunContext.fetch(FetchDescriptor<Run>(predicate: #Predicate { $0.endDateValue != nil }))
                for run in ended where pending[run.runID] == nil && !confirmed.contains(run.runID) {
                    guard let record = WatchRunRecord(run), let url = stage(record) else { continue }
                    pending[run.runID] = url
                }
            } catch {
                Trace.error("Couldn't look up watch runs to sync", error)
            }
        }

        let underway = Set(session.outstandingFileTransfers.compactMap {
            ($0.file.metadata?[Self.runIDField] as? String).flatMap(UUID.init(uuidString:))
        })
        let now = ContinuousClock.now
        for (id, url) in pending where !underway.contains(id) {
            // Older phone apps can still receive coached runs. Other workouts wait for the full importer.
            if !canConfirm {
                guard let data = try? Data(contentsOf: url), WatchRunRecord.decode(data)?.kind == .coached else { continue }
            }
            if let last = runAttempts[id], now - last < Self.runRetryInterval {
                scheduleRunRetry(after: Self.runRetryInterval - (now - last))
                continue
            }
            runAttempts[id] = now
            session.transferFile(url, metadata: [Self.runIDField: id.uuidString, Self.expectsReceiptField: canConfirm])
        }
    }

    private func scheduleRunRetry(after delay: Duration) {
        guard runRetry == nil else { return }
        runRetry = Task {
            try? await Task.sleep(for: delay)
            runRetry = nil
            sendPendingRuns()
        }
    }

    fileprivate func confirmRun(_ id: UUID) {
        WatchRunHistory.recordReceipt(for: id, in: defaults)
        removeStagedRun(id)
    }

    fileprivate func removeStagedRun(_ id: UUID) {
        runAttempts.removeValue(forKey: id)
        if let url = Self.pendingRunURL(for: id) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Gives Watch Connectivity time to deliver queued receipts while the scene wakes in the background.
    func finishBackgroundDelivery() async {
        let session = WCSession.default
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline, session.activationState != .activated || session.hasContentPending {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                return
            }
        }
    }

    private nonisolated static var pendingRunsFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("PendingRuns", isDirectory: true)
    }

    private nonisolated static func pendingRunURL(for id: UUID) -> URL? {
        pendingRunsFolder?.appendingPathComponent("\(pendingRunPrefix)\(id.uuidString).json")
    }

    private static func pendingRuns() -> [UUID: URL] {
        guard let folder = pendingRunsFolder,
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [:] }
        return files.reduce(into: [:]) { result, url in
            guard url.pathExtension == "json",
                  let name = runID(fromPendingFileName: url.deletingPathExtension().lastPathComponent),
                  let id = UUID(uuidString: name) else { return }
            result[id] = url
        }
    }
    #endif

    /// A waiting run's file is named for its run id after this, such as "run-<id>.json".
    private nonisolated static let pendingRunPrefix = "run-"

    /// The run id in a waiting run's file name without its extension, or nil for any other file.
    nonisolated static func runID(fromPendingFileName name: String) -> String? {
        name.hasPrefix(pendingRunPrefix) ? String(name.dropFirst(pendingRunPrefix.count)) : nil
    }

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
        if applicationContext[Self.runReceiptSupportField] as? Bool == true {
            Task { @MainActor in self.sendPendingRuns() }
        }
        #endif
        guard let received = ReceivedSettings(applicationContext) else { return }
        Task { @MainActor in
            self.receive(received.values, changedAt: received.changedAt, keyChangedAt: received.keyChangedAt, removed: received.removed)
        }
    }

    #if os(iOS)
    /// The received file goes away when this returns, so read it before moving to the main actor.
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let data = try? Data(contentsOf: file.fileURL) else {
            Logger.settings.error("Couldn't read a run sent from the watch.")
            return
        }
        Task { @MainActor in
            guard let id = self.runReceived?(data) else { return }
            let session = WCSession.default
            guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
            let receipt = id.uuidString
            guard !session.outstandingUserInfoTransfers.contains(where: { $0.userInfo[Self.receivedRunField] as? String == receipt })
            else { return }
            session.transferUserInfo([Self.receivedRunField: receipt])
        }
    }
    #elseif os(watchOS)
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let value = userInfo[Self.receivedRunField] as? String, let id = UUID(uuidString: value) else { return }
        Task { @MainActor in self.confirmRun(id) }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        if let error {
            Trace.error("A watch run transfer failed", error)
            Task { @MainActor in self.sendPendingRuns() }
            return
        }
        let metadata = fileTransfer.file.metadata
        // Legacy deliveries leave the original run visible. Only a save receipt confirms sync.
        if metadata?[Self.expectsReceiptField] as? Bool != true,
           let value = metadata?[Self.runIDField] as? String, let id = UUID(uuidString: value) {
            Task { @MainActor in self.removeStagedRun(id) }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.sendPendingRuns() }
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
