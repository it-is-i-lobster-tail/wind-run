//
//  RunDerivedCache.swift
//  Wind Run
//

import CoreData
import Foundation
import SwiftData
import UIKit

/// What the run summary, the comparison page and the "Best" ranks work out from a finished run's route,
/// kept while the app is open, so going back to a run, or comparing it again, doesn't walk its thousands
/// of fixes again.
///
/// Only finished runs are kept. An entry is dropped when the run's recorded data looks different from when
/// it was worked out, and the whole cache is emptied whenever the store saves or iCloud brings changes, when
/// the system is short of memory, and when a run is deleted.
@MainActor
final class RunDerivedCache {
    static let shared = RunDerivedCache()

    /// Enough for the runs someone flicks between and a comparison's group, while staying small: each
    /// entry is a few thousand points at most.
    static let limit = 60

    private struct Key: Hashable {
        let runID: UUID
        let kind: String
    }

    /// What the cached values were worked out from. Cheap to read: no fixes or heart rate readings.
    private struct Fingerprint: Equatable {
        let end: Date?
        let meters: Double
        let method: String?
        let pauses: Int
        let steps: Int?
        let stepCounts: Int?
        let altitude: Int?
        let plan: PersistentIdentifier?
        let goalMeters: Double?
        let goalSeconds: Double?

        init(_ run: Run) {
            end = run.endDateValue
            meters = run.distanceMetersValue
            method = run.distanceMethodValue
            pauses = run.pausesValue?.count ?? 0
            steps = run.stepLogDataValue?.count
            stepCounts = run.stepCountDataValue?.count
            altitude = run.altitudeDataValue?.count
            plan = run.intervalPlanValue?.persistentModelID
            goalMeters = run.goalMetersValue
            goalSeconds = run.goalSecondsValue
        }
    }

    private struct Entry {
        let fingerprint: Fingerprint
        let value: Any
    }

    private var entries: [Key: Entry] = [:]
    /// Keys from least to most recently used.
    private var order: [Key] = []
    private var observers: [NSObjectProtocol] = []

    private(set) var hits = 0
    private(set) var misses = 0

    init() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            ModelContext.didSave,
            .NSPersistentStoreRemoteChange,
            UIApplication.didReceiveMemoryWarningNotification,
        ]
        observers = names.map { name in
            // Straight away when it's posted on the main thread, so nothing reads a stale entry after a save.
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                if Thread.isMainThread {
                    MainActor.assumeIsolated { self?.removeAll() }
                } else {
                    Task { @MainActor in self?.removeAll() }
                }
            }
        }
    }

    /// The value kept for the run, or `build`'s, kept for next time when the run is finished.
    func value<T>(_ kind: String, for run: Run, build: () -> T) -> T {
        if let cached: T = cached(kind, for: run) { return cached }
        let value = build()
        store(value, kind, for: run)
        return value
    }

    /// The value kept for the run, or nil when there's none or the run has changed since.
    func cached<T>(_ kind: String, for run: Run) -> T? {
        guard run.status == .complete else { return nil }
        let key = Key(runID: run.runID, kind: kind)
        guard let entry = entries[key] else {
            misses += 1
            return nil
        }
        guard entry.fingerprint == Fingerprint(run), let value = entry.value as? T else {
            remove(key)
            misses += 1
            return nil
        }
        touch(key)
        hits += 1
        return value
    }

    /// Keeps a value worked out for a finished run.
    func store<T>(_ value: T, _ kind: String, for run: Run) {
        guard run.status == .complete else { return }
        let key = Key(runID: run.runID, kind: kind)
        entries[key] = Entry(fingerprint: Fingerprint(run), value: value)
        touch(key)
        while order.count > Self.limit {
            entries[order.removeFirst()] = nil
        }
    }

    /// Forgets everything kept for one run, as when it's deleted.
    func remove(runID: UUID) {
        for key in entries.keys where key.runID == runID { remove(key) }
    }

    func removeAll() {
        entries.removeAll()
        order.removeAll()
    }

    var count: Int { entries.count }

    private func remove(_ key: Key) {
        entries[key] = nil
        order.removeAll { $0 == key }
    }

    private func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
