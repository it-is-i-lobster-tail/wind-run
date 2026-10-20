//
//  RestingHeartRateReader.swift
//  Wind Run
//

import Foundation
import HealthKit
import OSLog

/// Reads resting heart rate from Health for the coach's morning check (PZ-13). The values are read
/// on the device each time and never stored, in the plan or anywhere else.
enum RestingHeartRateReader {
    private static let store = HKHealthStore()

    /// The resting heart rates of the last 60 days, oldest first. Empty when Health has none or
    /// reading isn't allowed.
    static func readings(days: Int = 60, now: Date = .now) async -> [RestingHeartRate] {
        guard HKHealthStore.isHealthDataAvailable(),
              let start = Calendar.current.date(byAdding: .day, value: -days, to: now)
        else { return [] }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.restingHeartRate), predicate: HKQuery.predicateForSamples(withStart: start, end: now))],
            sortDescriptors: [SortDescriptor(\.endDate)]
        )
        do {
            let unit = HKUnit.count().unitDivided(by: .minute())
            return try await descriptor.result(for: store).map { sample in
                RestingHeartRate(
                    date: sample.endDate,
                    bpm: sample.quantity.doubleValue(for: unit),
                    // Baselines are kept per device, never mixed (PZ-13).
                    device: sample.device?.name ?? sample.sourceRevision.source.bundleIdentifier
                )
            }
        } catch {
            Logger.health.info("Couldn't read resting heart rate: \(error.localizedDescription)")
            return []
        }
    }
}
