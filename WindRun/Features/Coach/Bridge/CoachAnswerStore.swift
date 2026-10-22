//
//  CoachAnswerStore.swift
//  Wind Run
//

import Foundation
import OSLog
import SwiftData

/// Keeps the runner's setup answers between plans (`CoachProfile`), and hands setup the logged runs to fill in from.
@MainActor
struct CoachAnswerStore {
    let context: ModelContext

    /// The saved answers: the profile's, or, for a runner who set a plan up before answers were kept, the newest
    /// plan's. Run days changed in plan settings since the last setup come along.
    func load() -> SavedCoachAnswers? {
        let service = CoachService(context: context)
        let plans = (try? context.fetch(FetchDescriptor<CoachPlan>(sortBy: [SortDescriptor(\.updatedDateValue, order: .reverse)]))) ?? []
        let planIntake = plans.lazy.compactMap { service.state(of: $0)?.intake }.first

        var answers: SavedCoachAnswers?
        if let data = newestProfile()?.answersData {
            do {
                answers = try JSONDecoder().decode(SavedCoachAnswers.self, from: data)
            } catch {
                Logger.coach.error("Couldn't read the saved coach answers: \(error.localizedDescription)")
            }
        }
        guard var answers else {
            guard var intake = planIntake else { return nil }
            intake.dateUndatedAnswers()
            return SavedCoachAnswers(intake: intake, savedAt: intake.answeredAt)
        }
        if let planIntake, let changed = planIntake.answerDates[.schedule],
           changed > (answers.intake.answerDates[.schedule] ?? .distantPast) {
            answers.intake.runDays = planIntake.runDays
            answers.intake.weekdayMaxSeconds = planIntake.weekdayMaxSeconds
            answers.intake.weekendMaxSeconds = planIntake.weekendMaxSeconds
            answers.intake.longRunDay = planIntake.longRunDay
            answers.intake.answerDates[.schedule] = changed
        }
        return answers
    }

    func save(_ answers: SavedCoachAnswers?) {
        guard let answers else { return }
        do {
            let data = try JSONEncoder().encode(answers)
            if let profile = newestProfile() {
                profile.store(data, at: answers.savedAt)
            } else {
                context.insert(CoachProfile(answersData: data, updatedDate: answers.savedAt))
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

    // MARK: Logged runs

    /// Every finished Wind Run run, for filling setup in.
    func loggedWorkouts() -> [PastWorkout] {
        let descriptor = FetchDescriptor<Run>(sortBy: [SortDescriptor(\.startDateValue)])
        return ((try? context.fetch(descriptor)) ?? [])
            .filter { $0.status == .complete }
            .map { PastWorkout($0) }
    }

    /// The Apple Health workouts Wind Run saved, which setup already counts as Wind Run runs.
    func healthWorkoutIDs() -> Set<UUID> {
        let descriptor = FetchDescriptor<Run>()
        return Set(((try? context.fetch(descriptor)) ?? []).compactMap(\.healthWorkoutID))
    }
}

extension PastWorkout {
    /// The coach's speed sessions, which count as hard sessions (IN-6).
    private static let hardKinds = Set(
        [SessionKind.threshold, .intervals, .shortReps, .hills, .racePace, .test, .race].map { $0.rawValue }
    )

    init(_ run: Run) {
        let hard = run.kind == .intervals || run.coachWorkout.map { Self.hardKinds.contains($0.kind) } == true
        self.init(start: run.startDate, seconds: run.activeDuration(), meters: run.distanceMeters, activity: .run(hard: hard))
    }
}
