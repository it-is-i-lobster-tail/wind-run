//
//  HealthWeight.swift
//  Wind Run
//

#if os(iOS)
import Foundation
import HealthKit
import OSLog

/// Body weight from Apple Health, so the runner isn't asked for what Health already knows.
///
/// Read on the device only. The weight question at first open is skipped when Health has a weight from the last
/// 3 months, and Health is checked again about once a month for a newer one (Brendon, 2026-10-27).
enum HealthWeight {
    /// When this iPhone last looked in Health. Kept on each device, like which questions were answered.
    static let checkedKey = "bodyWeightHealthChecked"
    static let checkInterval: TimeInterval = 30 * 24 * 60 * 60

    private static let store = HKHealthStore()
    private static let bodyMass = HKQuantityType(.bodyMass)

    /// Whether the runner let Wind Run into Health, by turning on heart rate or saving runs.
    static func usesHealth(_ defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: HeartRateMonitor.storageKey) || defaults.bool(forKey: HealthSync.enabledKey)
    }

    /// Before the weight question: a runner who uses Health is asked to let Wind Run read weight too (Health's
    /// sheet only shows if that hasn't been asked), then a weight from the last 3 months is taken.
    static func fillBeforeAsking(defaults: UserDefaults = .standard, now: Date = .now) async {
        guard HKHealthStore.isHealthDataAvailable(), usesHealth(defaults), BodyWeight.kilograms(in: defaults) == nil else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [bodyMass])
        } catch {
            Logger.health.info("Health weight permission request failed: \(error.localizedDescription)")
        }
        await check(defaults: defaults, now: now)
    }

    /// Looks in Health for a newer weight when it's been a month since the last look. Never shows Health's sheet:
    /// without permission to read, Health just has nothing to say.
    static func refreshIfDue(defaults: UserDefaults = .standard, now: Date = .now) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if let last = defaults.object(forKey: checkedKey) as? Date, now.timeIntervalSince(last) < checkInterval { return }
        await check(defaults: defaults, now: now)
    }

    private static func check(defaults: UserDefaults, now: Date) async {
        defaults.set(now, forKey: checkedKey)
        guard let latest = await latest() else { return }
        if BodyWeight.adoptFromHealth(latest.kilograms, measuredAt: latest.date, now: now, in: defaults) {
            Logger.health.debug("Took a newer weight from Health")
        }
    }

    /// The newest weight in Health, or nil when there's none or reading isn't allowed.
    private static func latest() async -> (kilograms: Double, date: Date)? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: bodyMass)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        do {
            guard let sample = try await descriptor.result(for: store).first else { return nil }
            return (sample.quantity.doubleValue(for: .gramUnit(with: .kilo)), sample.endDate)
        } catch {
            Logger.health.info("Couldn't read weight from Health: \(error.localizedDescription)")
            return nil
        }
    }
}
#endif
