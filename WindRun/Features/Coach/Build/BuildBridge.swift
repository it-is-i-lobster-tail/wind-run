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
        do {
            return try JSONDecoder().decode(Stored.self, from: data).buildDistance
        } catch {
            // Setup starts from its usual answers; the saved ones stay as they are until the next plan.
            Logger.coach.error("Couldn't read the saved setup answers (\(data.count) bytes): \(error)")
            return nil
        }
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
            Logger.coach.error("Couldn't save the coach answers: \(error)")
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
        if state.planCalendar.number(on: now, calendar: calendar) < 1 {
            return .startsLater(on: state.planCalendar.firstStart, next: next)
        }
        return BuildEngine.ranToday(state, now: now, calendar: calendar) ? .done(next: next) : .rest(next: next)
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
    static func canStart(_ workout: CoachWorkout, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard workout.kind == BuildSessionKind.long.rawValue, let event = workout.week?.plan?.eventDate else { return true }
        return BuildGoal.allowsLongRun(on: now, before: event, calendar: calendar)
    }

    /// The age the heart-rate estimate uses, since setup no longer asks. It gives the highest ceiling, so the cue
    /// never asks a runner to ease off sooner than their own numbers would; a lab-tested maximum lowers it.
    static let estimateAge = 18

    /// Gives the recorder the heart-rate cue when the runner's device-local settings allow coaching by heart rate.
    /// The event run has no cue. Call it before the recorder starts.
    static func attachCues(to recorder: RunRecorder, for workout: CoachWorkout) {
        guard !workout.isQuality, workout.kind != BuildSessionKind.event.rawValue else { return }
        let settings = CoachHeartRateStore.load()
        guard settings.coachingAllowed else { return }
        let zones = HeartRateZones.estimated(age: estimateAge, labMax: settings.labMax)
        var tracker = HeartRateCueTracker(parts: [HeartRateCue.Part(span: .toEnd, ceiling: zones.easyCeiling)], device: nil)
        Trace.log(.coach, "Heart-rate cue attached", ["kind": workout.kind, "labMax": settings.labMax.map(HeartRateZones.plausibleMax.contains) ?? false])
        recorder.spokenCue = { [weak recorder] elapsed, meters, beatsPerMinute in
            tracker.device = recorder?.heartRate?.source.flatMap { HeartRateDevice(rawValue: $0.rawValue) }
            guard tracker.update(elapsed: elapsed, meters: meters, beatsPerMinute: beatsPerMinute) else { return nil }
            Trace.log(.coach, "Heart-rate cue played", ["device": tracker.device?.rawValue ?? "none", "minutesIn": Int(elapsed / 60)])
            return HeartRateCue.text
        }
    }

    /// After a run ends, the coach counts it toward the week and shares what's left over the runs left.
    static func runFinished(in context: ModelContext) {
        let service = BuildService(context: context)
        guard let plan = service.currentPlan() else { return }
        service.refresh(plan)
    }
}
