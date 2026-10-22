//
//  SetupHealthReader.swift
//  Wind Run
//

import Foundation
import HealthKit
import OSLog

/// Reads what Apple Health can tell coach setup: height, weight and past workouts. Read on the device when setup
/// opens, only to fill answers in; nothing from Health is kept except the answers the runner goes on with.
enum SetupHealthReader {
    private static let store = HKHealthStore()

    struct Reading {
        var body = HealthBody()
        var workouts: [PastWorkout] = []
    }

    /// Asks Health for reading (its sheet shows only the first time), then reads.
    /// - Parameters:
    ///   - skipping: workouts Wind Run saved to Health, which setup already has as Wind Run runs.
    ///   - overlapping: Wind Run's runs; a Health run that starts during one is the same run from another app.
    static func read(skipping: Set<UUID>, overlapping runs: [PastWorkout], now: Date = .now) async -> Reading {
        guard HKHealthStore.isHealthDataAvailable() else { return Reading() }
        let types: Set<HKObjectType> = [HKQuantityType(.height), HKQuantityType(.bodyMass), HKObjectType.workoutType()]
        do {
            try await store.requestAuthorization(toShare: [], read: types)
        } catch {
            Logger.health.info("Health reading for setup wasn't allowed: \(error.localizedDescription)")
            return Reading()
        }
        let height = await latest(.height, unit: .meterUnit(with: .centi))
        let weight = await latest(.bodyMass, unit: .gramUnit(with: .kilo))
        let ownBundle = Bundle.main.bundleIdentifier ?? ""
        let workouts = await workouts(now: now).filter { workout in
            !skipping.contains(workout.uuid)
                && !(ownBundle.isEmpty == false && workout.sourceRevision.source.bundleIdentifier.hasPrefix(ownBundle))
                && !runs.contains { abs($0.start.timeIntervalSince(workout.startDate)) < 10 * 60 }
        }
        return Reading(
            body: HealthBody(heightCentimeters: height, weightKilograms: weight),
            workouts: workouts.compactMap { pastWorkout($0) }
        )
    }

    private static func latest(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(identifier))],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        do {
            return try await descriptor.result(for: store).first?.quantity.doubleValue(for: unit)
        } catch {
            Logger.health.info("Couldn't read \(identifier.rawValue) for setup: \(error.localizedDescription)")
            return nil
        }
    }

    /// The last 3 years of workouts, enough for "Have you finished this distance?".
    private static func workouts(now: Date) async -> [HKWorkout] {
        guard let start = Calendar.current.date(byAdding: .year, value: -3, to: now) else { return [] }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: now))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        do {
            return try await descriptor.result(for: store)
        } catch {
            Logger.health.info("Couldn't read workouts for setup: \(error.localizedDescription)")
            return []
        }
    }

    /// A Health workout as setup reads it: runs with their distance, and the other training IN-10 asked about.
    /// Walks and recovery sessions don't count.
    static func pastWorkout(_ workout: HKWorkout) -> PastWorkout? {
        let activity: PastWorkout.Activity
        switch workout.workoutActivityType {
        case .running:
            activity = .run(hard: false)
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            activity = .other(.legStrength)
        case .coreTraining:
            activity = .other(.upperBody)
        case .highIntensityIntervalTraining, .crossTraining, .mixedCardio, .kickboxing, .boxing, .cardioDance,
             .stairClimbing, .stepTraining, .jumpRope:
            activity = .other(.hiit)
        case .cycling, .handCycling:
            activity = .other(.cycling)
        case .swimming, .waterFitness:
            activity = .other(.swimming)
        case .yoga, .pilates, .barre, .flexibility, .taiChi:
            activity = .other(.yoga)
        case .soccer, .basketball, .tennis, .volleyball, .rugby, .hockey, .americanFootball, .australianFootball,
             .baseball, .softball, .cricket, .handball, .lacrosse, .badminton, .squash, .racquetball, .tableTennis,
             .pickleball:
            activity = .other(.teamSport)
        case .walking, .mindAndBody, .cooldown, .preparationAndRecovery:
            return nil
        default:
            activity = .other(.other)
        }
        let meters = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?
            .sumQuantity()?.doubleValue(for: .meter()) ?? 0
        return PastWorkout(start: workout.startDate, seconds: workout.duration, meters: meters, activity: activity)
    }
}
