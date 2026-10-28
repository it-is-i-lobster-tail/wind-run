//
//  RecentRunsReader.swift
//  Wind Run
//

import Foundation
import HealthKit
import OSLog
import SwiftData

extension CoachRun {
    /// A finished Wind Run run as the coach reads it, its climb from the barometer or GPS heights.
    @MainActor
    init(_ run: Run) {
        self.init(
            id: run.runID,
            start: run.startDate,
            meters: run.distanceMeters,
            climb: run.elevation?.gain ?? 0,
            plannedSessionID: run.coachWorkout?.sessionID
        )
    }
}

/// The runs setup fills "Weekly mileage now" and "Weekly climb now" in from: Wind Run's own, and Apple Health's
/// running workouts from other apps. Health is read on the device, and nothing from it is kept but the answers.
@MainActor
enum RecentRunsReader {
    private static let store = HKHealthStore()

    /// Every finished Wind Run run.
    static func appRuns(in context: ModelContext) -> [CoachRun] {
        let descriptor = FetchDescriptor<Run>(sortBy: [SortDescriptor(\.startDateValue)])
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.status == .complete }.map { CoachRun($0) }
    }

    /// Wind Run's runs and Health's runs from other apps over the last 4 weeks. A Health run Wind Run saved, or one
    /// that starts within 10 minutes of a Wind Run run, is the same run and counts once.
    static func recentRuns(in context: ModelContext, now: Date = .now) async -> [CoachRun] {
        let own = appRuns(in: context)
        let saved = Set(((try? context.fetch(FetchDescriptor<Run>())) ?? []).compactMap(\.healthWorkoutID))
        let health = await healthRuns(now: now).filter { workout in
            !saved.contains(workout.id) && !own.contains { abs($0.start.timeIntervalSince(workout.start)) < 10 * 60 }
        }
        return (own + health).sorted { $0.start < $1.start }
    }

    /// Running workouts in Health from the last 29 days, with their distance and climb.
    private static func healthRuns(now: Date) async -> [CoachRun] {
        guard HKHealthStore.isHealthDataAvailable(),
              let start = Calendar.current.date(byAdding: .day, value: -29, to: now) else { return [] }
        do {
            try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
        } catch {
            Logger.health.info("Health reading for setup wasn't allowed: \(error.localizedDescription)")
            return []
        }
        let ownBundle = Bundle.main.bundleIdentifier ?? ""
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(NSCompoundPredicate(andPredicateWithSubpredicates: [
                HKQuery.predicateForWorkouts(with: .running),
                HKQuery.predicateForSamples(withStart: start, end: now),
            ]))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        do {
            return try await descriptor.result(for: store)
                .filter { ownBundle.isEmpty || !$0.sourceRevision.source.bundleIdentifier.hasPrefix(ownBundle) }
                .map { workout in
                    let meters = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
                    let climb = (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter()) ?? 0
                    return CoachRun(id: workout.uuid, start: workout.startDate, meters: meters, climb: climb)
                }
        } catch {
            Logger.health.info("Couldn't read running workouts for setup: \(error.localizedDescription)")
            return []
        }
    }
}
