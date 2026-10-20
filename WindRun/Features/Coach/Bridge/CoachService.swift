//
//  CoachService.swift
//  Wind Run
//

import Foundation
import OSLog
import SwiftData

/// Runs coach engine calls against the stored plan: reads the plan's state and the runs, calls
/// the engine, and stores what comes back, including the copy of the planned weeks.
@MainActor
struct CoachService {
    let context: ModelContext
    var calendar: Calendar = .current
    var unit: DistanceUnit = .current

    /// Track summaries by run, since a finished run's route never changes.
    private static var tracks: [UUID: TrackSummary?] = [:]

    /// The last decoded state of each plan, so screens don't decode it on every redraw.
    private struct StateKey: Equatable {
        var plan: PersistentIdentifier
        var updated: Date
        var size: Int
    }
    private static var states: [PersistentIdentifier: (key: StateKey, state: CoachState)] = [:]

    init(context: ModelContext, calendar: Calendar = .current, unit: DistanceUnit = .current) {
        self.context = context
        self.calendar = calendar
        self.unit = unit
    }

    // MARK: Reading

    /// The runner's current plan, paused ones included.
    func currentPlan() -> CoachPlan? {
        ((try? context.fetch(FetchDescriptor<CoachPlan>())) ?? []).active
    }

    func state(of plan: CoachPlan) -> CoachState? {
        guard let data = plan.stateData else { return nil }
        let key = StateKey(plan: plan.persistentModelID, updated: plan.updatedDate, size: data.count)
        if let cached = Self.states[key.plan], cached.key == key { return cached.state }
        do {
            let state = try JSONDecoder().decode(CoachState.self, from: data)
            Self.states[key.plan] = (key, state)
            return state
        } catch {
            Logger.coach.error("Couldn't read the coach state: \(error.localizedDescription)")
            return nil
        }
    }

    /// Every finished run, as the coach reads them.
    func loggedRuns() -> [LoggedRun] {
        let descriptor = FetchDescriptor<Run>(sortBy: [SortDescriptor(\.startDateValue)])
        let runs = ((try? context.fetch(descriptor)) ?? []).filter { $0.status == .complete }
        return runs.map { LoggedRun($0, track: track(of: $0)) }
    }

    private func track(of run: Run) -> TrackSummary? {
        if let cached = Self.tracks[run.runID] { return cached }
        let track = RunTrack(run).map(TrackSummary.init)
        Self.tracks[run.runID] = track
        return track
    }

    // MARK: Calls

    /// Builds the plan and its first week from the intake.
    func startPlan(intake: CoachIntake, goal: GoalChoice, level: CommitmentLevel, insisted: Bool, now: Date = .now) -> (CoachPlan, CoachUpdate) {
        // One plan at a time: starting a new one stops the old.
        currentPlan()?.stop()
        let update = CoachEngine.startPlan(intake: intake, goal: goal, level: level, insisted: insisted, runs: loggedRuns(), now: now, calendar: calendar)
        let plan = CoachPlan(flavor: goal.flavor.rawValue, startDate: update.state.startDate)
        context.insert(plan)
        save(update, to: plan, now: now)
        return (plan, update)
    }

    /// Calls the engine with the plan's state and stores the result. Nil when the plan has no state.
    @discardableResult
    func perform(
        on plan: CoachPlan,
        now: Date = .now,
        _ call: (CoachState, [LoggedRun], Date, Calendar) -> CoachUpdate
    ) -> CoachUpdate? {
        guard let state = state(of: plan) else { return nil }
        let update = call(state, loggedRuns(), now, calendar)
        save(update, to: plan, now: now)
        return update
    }

    /// At app open, after each saved run, and when the day changes.
    @discardableResult
    func refresh(_ plan: CoachPlan, now: Date = .now) -> CoachUpdate? {
        perform(on: plan, now: now) { state, runs, now, calendar in
            CoachEngine.refresh(state: state, runs: runs, now: now, calendar: calendar)
        }
    }

    /// Tells the coach about a saved run. Call it again after the run's check-in; it's safe to repeat.
    func logRun(_ run: Run, in plan: CoachPlan, now: Date = .now) -> (CoachUpdate, RunReview)? {
        guard run.status == .complete, let state = state(of: plan) else { return nil }
        let runs = loggedRuns()
        let logged = runs.first { $0.id == run.runID } ?? LoggedRun(run, track: track(of: run))
        let (update, review) = CoachEngine.logRun(logged, state: state, runs: runs, now: now, calendar: calendar)
        save(update, to: plan, now: now)
        return (update, review)
    }

    /// Stores the after-run answers and tells the coach.
    func saveCheckIn(_ checkIn: RunCheckIn, for run: Run, in plan: CoachPlan?, now: Date = .now) -> (CoachUpdate, RunReview)? {
        run.saveCheckIn(checkIn)
        context.saveQuietly()
        guard let plan else { return nil }
        return logRun(run, in: plan, now: now)
    }

    private func save(_ update: CoachUpdate, to plan: CoachPlan, now: Date) {
        do {
            let data = try JSONEncoder().encode(update.state)
            plan.saveState(data, rulesVersion: String(update.state.rulesVersion), at: now)
        } catch {
            Logger.coach.error("Couldn't store the coach state: \(error.localizedDescription)")
        }
        CoachProjection.apply(update.state, to: plan, in: context, unit: unit, calendar: calendar)
        context.saveQuietly()
    }
}

extension DistanceUnit {
    /// The unit the runner picked in Settings.
    static var current: DistanceUnit {
        UserDefaults.standard.string(forKey: storageKey).flatMap(DistanceUnit.init(rawValue:)) ?? .kilometers
    }
}
