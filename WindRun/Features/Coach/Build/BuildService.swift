//
//  BuildService.swift
//  Wind Run
//

import Foundation
import OSLog
import SwiftData

/// Runs coach calls against the stored plan: reads the plan's state and the runs, calls the coach, and stores what
/// comes back, with the copy of the weeks the screens show and runs link to.
@MainActor
struct BuildService {
    static let flavor = "buildDistance"
    static let rulesVersion = "build-\(BuildPlanState.currentVersion)"

    let context: ModelContext
    var calendar: Calendar = .current

    /// The last decoded state of each plan, so screens don't decode it on every redraw.
    private struct StateKey: Equatable {
        var plan: PersistentIdentifier
        var updated: Date
        var size: Int
    }
    private static var states: [PersistentIdentifier: (key: StateKey, state: BuildPlanState)] = [:]

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    // MARK: Reading

    /// The runner's current plan.
    func currentPlan() -> CoachPlan? {
        ((try? context.fetch(FetchDescriptor<CoachPlan>())) ?? []).active
    }

    func state(of plan: CoachPlan) -> BuildPlanState? {
        guard let data = plan.stateData, plan.rulesVersion.hasPrefix("build-") else { return nil }
        let key = StateKey(plan: plan.persistentModelID, updated: plan.updatedDate, size: data.count)
        if let cached = Self.states[key.plan], cached.key == key { return cached.state }
        do {
            let state = try JSONDecoder().decode(BuildPlanState.self, from: data)
            Self.states[key.plan] = (key, state)
            return state
        } catch {
            Logger.coach.error("Couldn't read the coach state: \(error.localizedDescription)")
            return nil
        }
    }

    /// A plan saved by an older version of the coach, which this one can't read.
    func hasUnreadableState(_ plan: CoachPlan) -> Bool {
        state(of: plan) == nil
    }

    /// Stops a plan whose state can't be read, so the runner can set up a new one.
    func retireUnreadable(_ plan: CoachPlan) {
        guard hasUnreadableState(plan) else { return }
        plan.stop()
        context.saveQuietly()
    }

    /// Every finished Wind Run run, as the coach reads them.
    func runs() -> [CoachRun] {
        RecentRunsReader.appRuns(in: context)
    }

    // MARK: Calls

    /// Starts a plan from setup's answers. Starting a new plan stops the old one.
    @discardableResult
    func start(_ settings: BuildSettings, now: Date = .now) -> CoachPlan {
        currentPlan()?.stop()
        let state = BuildEngine.start(settings, runs: runs(), now: now, calendar: calendar)
        let plan = CoachPlan(flavor: Self.flavor, startDate: state.planCalendar.firstStart, eventDate: state.goalDate, goalDistanceMeters: settings.goal.meters)
        context.insert(plan)
        save(state, to: plan, now: now)
        return plan
    }

    /// Calls the coach with the plan's state and stores the result.
    @discardableResult
    func perform(on plan: CoachPlan, now: Date = .now, _ call: (BuildPlanState, [CoachRun], Date, Calendar) -> BuildPlanState) -> BuildPlanState? {
        guard let state = state(of: plan) else { return nil }
        let updated = call(state, runs(), now, calendar)
        save(updated, to: plan, now: now)
        return updated
    }

    /// At app open, after each saved run, and when the day changes.
    @discardableResult
    func refresh(_ plan: CoachPlan, now: Date = .now) -> BuildPlanState? {
        perform(on: plan, now: now) { state, runs, now, calendar in
            BuildEngine.refresh(state, runs: runs, now: now, calendar: calendar)
        }
    }

    private func save(_ state: BuildPlanState, to plan: CoachPlan, now: Date) {
        do {
            plan.saveState(try JSONEncoder().encode(state), rulesVersion: Self.rulesVersion, at: now)
        } catch {
            Logger.coach.error("Couldn't store the coach state: \(error.localizedDescription)")
        }
        BuildProjection.apply(state, to: plan, in: context, calendar: calendar)
        context.saveQuietly()
    }
}

/// Copies the plan's weeks into the stored weeks and workouts the screens show and runs link to. Weeks are matched
/// by number and workouts by session id, which stays the same when a week is planned again, so a linked run keeps
/// its workout.
@MainActor
enum BuildProjection {
    static func apply(_ state: BuildPlanState, to plan: CoachPlan, in context: ModelContext, calendar: Calendar) {
        let status: CoachPlanStatus = switch state.status {
        case .active: state.isPaused ? .paused : .active
        case .complete: .complete
        case .stopped: .stopped
        }
        plan.updateSummary(status: status, startDate: state.planCalendar.firstStart, eventDate: state.goalDate, goalDistanceMeters: state.settings.goal.meters)
        plan.setFlavor(BuildService.flavor)

        var orders = Set<Int>()
        for planned in state.weeks {
            let order = planned.number - 1
            orders.insert(order)
            let week = plan.week(at: order) ?? plan.addWeek(order: order)
            let long = planned.sessions.first { $0.kind == .long }
            week.update(
                kind: planned.kind.rawValue,
                title: planned.kind.name,
                because: "",
                startDate: planned.start,
                plannedMeters: planned.target.meters,
                plannedSeconds: nil,
                longRunMeters: long?.target.meters,
                longRunSeconds: nil,
                outcome: planned.closed ? (planned.doneShare >= BuildLimits.doneShare ? "done" : "short") : nil
            )
            sync(planned, into: week, in: context, calendar: calendar)
        }
        for week in plan.weeks where !orders.contains(week.order) && !week.workouts.contains(where: \.isDone) {
            plan.removeWeek(week)
            context.delete(week)
        }
    }

    private static func sync(_ planned: BuildWeek, into week: CoachWeek, in context: ModelContext, calendar: Calendar) {
        var ids = Set<UUID>()
        // A planned run with nothing left in the week for it is a rest day, so it isn't shown.
        let shown = planned.sessions.filter { !$0.status.isPlanned || $0.isToDo }
        for (order, session) in shown.sorted(by: { $0.date < $1.date }).enumerated() {
            ids.insert(session.id)
            let dayOffset = calendar.dateComponents([.day], from: planned.start, to: session.date).day ?? 0
            let workout = week.workout(withSessionID: session.id)
                ?? week.addWorkout(sessionID: session.id, kind: session.kind.rawValue, dayOffset: dayOffset)
            workout.update(
                kind: session.kind.rawValue,
                dayOffset: dayOffset,
                date: session.date,
                order: order,
                status: session.status.rawName,
                target: CoachWorkoutTarget(
                    title: session.kind.name,
                    detail: detail(session),
                    notes: "",
                    meters: session.target.meters,
                    seconds: nil,
                    pace: nil,
                    effort: nil,
                    runWalk: nil,
                    isKeySession: session.kind != .easy,
                    isQuality: false
                )
            )
        }
        for workout in week.workouts where !(workout.sessionID.map(ids.contains) ?? false) && !workout.isDone {
            week.removeWorkout(workout)
            context.delete(workout)
        }
    }

    /// "About 2,800 ft of climb" when the run has climb.
    static func detail(_ session: BuildSession) -> String {
        guard session.target.climb >= 1 else { return "" }
        return "About \(DistanceUnit.current.climb(session.target.climb)) of climb."
    }
}

extension BuildSessionStatus {
    /// How the status is stored with the workout's copy.
    var rawName: String {
        switch self {
        case .planned: "planned"
        case .done: "done"
        case .missed: "missed"
        }
    }
}
