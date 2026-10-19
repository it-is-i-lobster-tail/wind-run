//
//  SettingsSync.swift
//  Wind Run
//

import Foundation
import OSLog
import WatchConnectivity

/// Keeps units and pace call-outs the same on iPhone and Apple Watch, whichever one they were changed on.
///
/// Settings go straight between the paired phone and watch. Nothing passes through a server, and runs aren't sent.
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

    private let defaults: UserDefaults
    /// The values last sent or received, so applying a received change doesn't echo it back.
    private var lastSynced: [String: String] = [:]
    /// True while writing values that came from the other device, which aren't a local change.
    private var isApplyingReceived = false
    private var observer: NSObjectProtocol?

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
        guard session.activationState == .activated, changedAt > .distantPast else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        do {
            try session.updateApplicationContext([
                Self.settingsField: lastSynced,
                Self.changedAtField: changedAt,
            ])
        } catch {
            Logger.settings.error("Couldn't send settings to the other device: \(error.localizedDescription)")
        }
    }

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

    fileprivate func activated(with context: [String: String]?, changedAt received: Date?, error: String?) {
        if let error {
            Logger.settings.error("Watch connection didn't start: \(error)")
        }
        if let context, let received {
            receive(context, changedAt: received)
        }
        send()
    }
}

extension SettingsSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let values = context[Self.settingsField] as? [String: String]
        let changedAt = context[Self.changedAtField] as? Date
        let message = error?.localizedDescription
        Task { @MainActor in self.activated(with: values, changedAt: changedAt, error: message) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let values = applicationContext[Self.settingsField] as? [String: String],
              let changedAt = applicationContext[Self.changedAtField] as? Date
        else { return }
        Task { @MainActor in self.receive(values, changedAt: changedAt) }
    }

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
