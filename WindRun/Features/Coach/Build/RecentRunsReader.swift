//
//  RecentRunsReader.swift
//  Wind Run
//

import Foundation
import HealthKit
import OSLog
import SwiftData

/// The runs setup fills "Weekly mileage now" and "Weekly climb now" in from: Wind Run's own, and Apple Health's
/// running workouts from other apps. Health is read on the device, and nothing from it is kept but the answers.
@MainActor
enum RecentRunsReader {
    private static let store = HKHealthStore()

    /// A Health run that starts this close to a Wind Run run is the same run.
    private static let sameRunWindow: TimeInterval = 10 * 60

    /// Each run's climb, worked out once: it walks the run's whole route. Kept while the run stays the same.
    private static var climbs: [UUID: (end: Date?, meters: Double, climb: Double)] = [:]

    /// Wind Run's finished runs that started from `since` on, or all of them.
    static func appRuns(in context: ModelContext, since: Date? = nil) -> [CoachRun] {
        let from = since ?? .distantPast
        let descriptor = FetchDescriptor<Run>(
            predicate: #Predicate { $0.startDateValue >= from && $0.endDateValue != nil },
            sortBy: [SortDescriptor(\.startDateValue)]
        )
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.status == .complete && $0.sport == .running }.map { coachRun($0) }
    }

    /// A finished Wind Run run as the coach reads it, its climb from the barometer or GPS heights.
    static func coachRun(_ run: Run) -> CoachRun {
        let climb: Double
        if let cached = climbs[run.runID], cached.end == run.endDate, cached.meters == run.distanceMeters {
            climb = cached.climb
        } else {
            climb = run.climbGain
            climbs[run.runID] = (run.endDate, run.distanceMeters, climb)
        }
        return CoachRun(id: run.runID, start: run.startDate, meters: run.distanceMeters, climb: climb, plannedSessionID: run.coachWorkout?.sessionID)
    }

    /// Wind Run's runs and Health's runs from other apps over the last 4 weeks. A Health run Wind Run saved, or one
    /// that starts within 10 minutes of a Wind Run run, is the same run and counts once.
    static func recentRuns(in context: ModelContext, now: Date = .now) async -> [CoachRun] {
        // A day more than recentWeek reads, so its window is covered from any time of day.
        let since = Calendar.current.date(byAdding: .day, value: -(BuildPlanner.recentDays + 1), to: now) ?? now
        let own = appRuns(in: context, since: since)
        let window = FetchDescriptor<Run>(predicate: #Predicate { $0.startDateValue >= since })
        let saved = Set(((try? context.fetch(window)) ?? []).compactMap(\.healthWorkoutID))
        let read = await healthRuns(from: since, to: now)
        let health = read.runs.filter { workout in
            !saved.contains(workout.id) && !own.contains { abs($0.start.timeIntervalSince(workout.start)) < sameRunWindow }
        }
        Trace.log(.coach, "Runs read for setup", ["own": own.count, "health": health.count, "healthRead": read.outcome])
        return (own + health).sorted { $0.start < $1.start }
    }

    /// Running workouts in Health between the dates, with their distance and climb, and how the reading went:
    /// "read", "unavailable", or "error" with the error logged.
    private static func healthRuns(from start: Date, to now: Date) async -> (runs: [CoachRun], outcome: String) {
        guard HKHealthStore.isHealthDataAvailable() else { return ([], "unavailable") }
        do {
            try await store.requestAuthorization(toShare: [], read: [HKObjectType.workoutType()])
        } catch {
            Logger.health.info("Health reading for setup wasn't allowed: \(error)")
            return ([], "error")
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
            let runs = try await descriptor.result(for: store)
                .filter { ownBundle.isEmpty || !$0.sourceRevision.source.bundleIdentifier.hasPrefix(ownBundle) }
                .map { workout in
                    let meters = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
                    let climb = (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter()) ?? 0
                    return CoachRun(id: workout.uuid, start: workout.startDate, meters: meters, climb: climb)
                }
            return (runs, "read")
        } catch {
            Logger.health.info("Couldn't read running workouts for setup: \(error)")
            return ([], "error")
        }
    }
}
