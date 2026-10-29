//
//  BuildBridge.swift
//  Wind Run
//

import Foundation
import OSLog
import SwiftData

/// Keeps setup's answers between plans in the runner's coach profile, so the next setup starts from them.
@MainActor
struct BuildAnswerStore {
    let context: ModelContext

    /// Stored under its own key, so answers saved by an older coach read as none.
    private struct Stored: Codable {
        var buildDistance: SavedBuildAnswers
    }

    func load() -> SavedBuildAnswers? {
        guard let data = newestProfile()?.answersData else { return nil }
        return try? JSONDecoder().decode(Stored.self, from: data).buildDistance
    }

    func save(_ answers: SavedBuildAnswers, at date: Date = .now) {
        do {
            let data = try JSONEncoder().encode(Stored(buildDistance: answers))
            if let profile = newestProfile() {
                profile.store(data, at: date)
            } else {
                context.insert(CoachProfile(answersData: data, updatedDate: date))
            }
            context.saveQuietly()
        } catch {
            Logger.coach.error("Couldn't save the coach answers: \(error.localizedDescription)")
        }
    }

    private func newestProfile() -> CoachProfile? {
        let descriptor = FetchDescriptor<CoachProfile>(sortBy: [SortDescriptor(\.updatedDateValue, order: .reverse)])
        return (try? context.fetch(descriptor))?.first
    }
}

extension CoachToday {
    /// What a Build Distance plan has for today. Nil when the plan is over.
    static func of(_ plan: CoachPlan, build state: BuildPlanState, now: Date, calendar: Calendar) -> CoachToday? {
        guard case .active = state.status else { return nil }
        if state.isPaused { return .paused }
        if let workout = workouts(plan, build: state, now: now, calendar: calendar).first {
            return .workout(workout)
        }
        let next = BuildEngine.nextSession(state, now: now, calendar: calendar).flatMap { workout(for: $0.id, in: plan) }
        if calendar.startOfDay(for: now) < state.planCalendar.firstStart {
            return .startsLater(next: next)
        }
        let today = calendar.startOfDay(for: now)
        let ranToday = BuildEngine.currentWeek(state, now: now, calendar: calendar)?.sessions.contains { session in
            guard session.date == today else { return false }
            if case .done = session.status { return true }
            return false
        } ?? false
        return ranToday ? .done(next: next) : .rest(next: next)
    }

    /// Today's runs from a Build Distance plan that are still to do.
    static func workouts(_ plan: CoachPlan, build state: BuildPlanState, now: Date, calendar: Calendar) -> [CoachWorkout] {
        BuildEngine.todaysSessions(state, now: now, calendar: calendar).compactMap { workout(for: $0.id, in: plan) }
    }

    private static func workout(for sessionID: UUID, in plan: CoachPlan) -> CoachWorkout? {
        plan.weeks.flatMap(\.workouts).first { $0.sessionID == sessionID && !$0.isDone }
    }
}

/// What a Build Distance run needs when it starts: the heart-rate cue on easy and long runs.
@MainActor
enum BuildRunStart {
    /// The age the heart-rate estimate uses, since setup no longer asks. It gives the highest ceiling, so the cue
    /// never asks a runner to ease off sooner than their own numbers would; a lab-tested maximum lowers it.
    static let estimateAge = 18

    /// Gives the recorder the heart-rate cue when the runner's device-local settings allow coaching by heart rate.
    /// The event run has no cue. Call it before the recorder starts.
    static func attachCues(to recorder: RunRecorder, for workout: CoachWorkout) {
        guard workout.kind != BuildSessionKind.event.rawValue else { return }
        let settings = CoachHeartRateStore.load()
        guard settings.coachingAllowed else { return }
        let zones = HeartRateZones.estimated(age: estimateAge, labMax: settings.labMax)
        var tracker = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: zones.easyCeiling)], device: nil)
        recorder.spokenCue = { [weak recorder] elapsed, meters, beatsPerMinute in
            tracker.device = recorder?.heartRate?.source.flatMap { HeartRateDevice(rawValue: $0.rawValue) }
            return tracker.update(elapsed: elapsed, meters: meters, beatsPerMinute: beatsPerMinute) ? HeartRateCue.text : nil
        }
    }

    /// After a run ends, the coach counts it toward the week and shares what's left over the runs left.
    static func runFinished(in context: ModelContext) {
        let service = BuildService(context: context)
        guard let plan = service.currentPlan() else { return }
        service.refresh(plan)
    }
}

extension DistanceUnit {
    /// The unit the runner picked in Settings.
    static var current: DistanceUnit {
        UserDefaults.standard.string(forKey: storageKey).flatMap(DistanceUnit.init(rawValue:)) ?? .kilometers
    }
}
