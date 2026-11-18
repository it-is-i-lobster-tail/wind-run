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
    /// Every Build Distance rules version starts with this, then the state's version number.
    static let rulesPrefix = "build-"
    static let rulesVersion = "\(rulesPrefix)\(BuildPlanState.currentVersion)"
    /// The runs the coach reads go back this far before the plan's first week, for its first weeks' runs.
    static let runsBefore = 28

    let context: ModelContext
    var calendar: Calendar = .current

    /// The last decoded state of each plan, so screens don't decode it on every redraw.
    private struct StateKey: Equatable {
        var plan: PersistentIdentifier
        var updated: Date
        var size: Int
    }
    private static var states: [PersistentIdentifier: (key: StateKey, state: BuildPlanState)] = [:]
    /// Plans whose state couldn't be read, so it's logged once rather than on every redraw.
    private static var unreadable: [PersistentIdentifier: StateKey] = [:]

    init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    // MARK: Reading

    /// The runner's current plan.
    func currentPlan() -> CoachPlan? {
        ((try? context.fetch(FetchDescriptor<CoachPlan>())) ?? []).active
    }

    /// The plan's state, with its days in this device's time zone.
    func state(of plan: CoachPlan) -> BuildPlanState? {
        storedState(of: plan)?.inZone(of: calendar)
    }

    /// The plan's state as stored. Nil when there's none yet, it can't be read, or a newer Wind Run saved it.
    private func storedState(of plan: CoachPlan) -> BuildPlanState? {
        guard let data = plan.stateData, plan.rulesVersion.hasPrefix(Self.rulesPrefix) else { return nil }
        let key = StateKey(plan: plan.persistentModelID, updated: plan.updatedDate, size: data.count)
        if let cached = Self.states[key.plan], cached.key == key { return cached.state }
        if Self.unreadable[key.plan] == key { return nil }
        do {
            let state = try JSONDecoder().decode(BuildPlanState.self, from: data)
            // A newer coach's state would lose what this one doesn't know about if it were saved again.
            guard state.version <= BuildPlanState.currentVersion else {
                Self.unreadable[key.plan] = key
                Logger.coach.error("The coach state is from a newer version (\(state.version), \(data.count) bytes)")
                return nil
            }
            Self.states[key.plan] = (key, state)
            return state
        } catch {
            Self.unreadable[key.plan] = key
            Logger.coach.error("Couldn't read the coach state (\(plan.rulesVersion, privacy: .public), \(data.count) bytes): \(error)")
            return nil
        }
    }

    /// Why a plan can't be shown.
    enum Problem: Equatable {
        /// Its state isn't on this device yet: iCloud is still bringing it.
        case loading
        /// A newer Wind Run saved it.
        case newer
        /// An earlier version of the coach made it, or it can't be read.
        case unreadable
    }

    /// Nil when the plan can be shown.
    func problem(with plan: CoachPlan) -> Problem? {
        guard storedState(of: plan) == nil else { return nil }
        guard let data = plan.stateData else { return .loading }
        if let number = Self.rulesNumber(plan.rulesVersion), number > BuildPlanState.currentVersion {
            return .newer
        }
        struct Version: Decodable { var version: Int }
        if plan.rulesVersion.hasPrefix(Self.rulesPrefix), let version = try? JSONDecoder().decode(Version.self, from: data).version, version > BuildPlanState.currentVersion {
            return .newer
        }
        return .unreadable
    }

    /// The number in a Build Distance rules version, or nil for any other.
    static func rulesNumber(_ version: String) -> Int? {
        version.hasPrefix(rulesPrefix) ? Int(version.dropFirst(rulesPrefix.count)) : nil
    }

    /// Stops a plan whose state can't be read, so the runner can set up a new one.
    func retireUnreadable(_ plan: CoachPlan) {
        guard problem(with: plan) == .unreadable else { return }
        plan.stop()
        context.saveQuietly()
        Trace.log(.coach, "Unreadable plan stopped")
    }

    /// The finished Wind Run runs the plan can count: from 4 weeks before its first week on, or every run.
    func runs(for state: BuildPlanState? = nil) -> [CoachRun] {
        let since = state.flatMap { calendar.date(byAdding: .day, value: -Self.runsBefore, to: $0.planCalendar.firstStart) }
        return RecentRunsReader.appRuns(in: context, since: since)
    }

    // MARK: Calls

    /// Starts a plan from setup's answers. Starting a new plan stops the old one.
    @discardableResult
    func start(_ settings: BuildSettings, now: Date = .now) -> CoachPlan {
        currentPlan()?.stop()
        let since = calendar.date(byAdding: .day, value: -Self.runsBefore - 7, to: now)
        let state = BuildEngine.start(settings, runs: RecentRunsReader.appRuns(in: context, since: since), now: now, calendar: calendar)
        let plan = CoachPlan(flavor: Self.flavor, startDate: state.planCalendar.firstStart, eventDate: state.goalDate, goalDistanceMeters: settings.goal.meters)
        context.insert(plan)
        save(state, to: plan, now: now)
        Trace.log(.coach, "Plan started", ["weeks": state.planCalendar.count, "event": settings.goal.event.rawValue, "runDays": settings.runDays.count])
        return plan
    }

    /// Calls the coach with the plan's state and stores the result. Nothing is saved when nothing changed, so a
    /// refresh doesn't send the plan to iCloud again, or write an older copy over a newer one from another device.
    @discardableResult
    func perform(on plan: CoachPlan, now: Date = .now, _ call: (BuildPlanState, [CoachRun], Date, Calendar) -> BuildPlanState) -> BuildPlanState? {
        guard let stored = storedState(of: plan) else { return nil }
        let state = stored.inZone(of: calendar)
        let updated = call(state, runs(for: state), now, calendar)
        let changed = updated != stored || plan.rulesVersion != Self.rulesVersion
        trace(from: state, to: updated, changed: changed, now: now)
        if changed { save(updated, to: plan, now: now) }
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
            Logger.coach.error("Couldn't store the coach state (\(state.weeks.count) weeks): \(error)")
        }
        BuildProjection.apply(state, to: plan, in: context, calendar: calendar)
        context.saveQuietly()
    }

    /// What the coach decided, in counts and states only.
    private func trace(from before: BuildPlanState, to after: BuildPlanState, changed: Bool, now: Date) {
        Trace.log(.coach, changed ? "Plan worked out and saved" : "Plan worked out, nothing changed", [
            "week": after.planCalendar.number(on: now, calendar: calendar),
            "weeksClosed": after.weeks.filter(\.closed).count - before.weeks.filter(\.closed).count,
            "status": after.status.traceName,
            "holdNext": after.holdNext,
            "lowWeeks": after.lowWeeks,
            "baseDown": after.base.meters < before.base.meters - 0.5,
            "paused": after.isPaused,
            "injuries": after.openInjuries.count,
        ])
    }
}

extension BuildPlanStatus {
    /// For the trace.
    var traceName: String {
        switch self {
        case .active: "active"
        case .complete: "complete"
        case .stopped: "stopped"
        }
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
                outcome: planned.outcomeName
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
                // The climb is shown from the plan, in the unit each screen uses, so none is kept here.
                target: CoachWorkoutTarget(
                    title: session.kind.name,
                    detail: "",
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
}

extension CoachFormat {
    /// "About 2,800 ft of climb." when the run has climb.
    static func climbNote(_ meters: Double, unit: DistanceUnit) -> String? {
        guard meters >= 1 else { return nil }
        return "About \(unit.climb(meters)) of climb."
    }
}

extension BuildPlanState {
    /// The climb planned for a session, 0 when there's none.
    func climb(ofSession id: UUID?) -> Double {
        guard let id else { return 0 }
        return BuildEngine.locate(id, in: self)?.session.target.climb ?? 0
    }
}

extension BuildSessionStatus {
    /// How the status is stored with the workout's copy.
    var rawName: String {
        switch self {
        case .planned: CoachWorkoutStatus.planned
        case .done: CoachWorkoutStatus.done
        case .missed: CoachWorkoutStatus.missed
        }
    }
}
