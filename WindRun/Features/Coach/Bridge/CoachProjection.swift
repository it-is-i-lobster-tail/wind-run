//
//  CoachProjection.swift
//  Wind Run
//

import Foundation
import SwiftData

/// Copies the engine's planned weeks into the stored weeks and sessions the screens show and runs
/// link to.
///
/// Weeks are matched by index and sessions by the engine's session id, which stays the same when a
/// week is re-planned, so a linked run keeps its session.
enum CoachProjection {
    static func apply(_ state: CoachState, to plan: CoachPlan, in context: ModelContext, unit: DistanceUnit, calendar: Calendar = .current) {
        plan.updateSummary(
            status: CoachPlanStatus(state.status),
            startDate: state.startDate,
            eventDate: state.goal.flavor == .event ? state.goal.eventDate : nil,
            goalDistanceMeters: state.goal.distance.meters
        )
        plan.setFlavor(state.goal.flavor.rawValue)

        var plannedIndexes = Set<Int>()
        for record in state.weeks {
            let planned = record.plan
            plannedIndexes.insert(planned.index)
            let week = plan.week(at: planned.index) ?? plan.addWeek(order: planned.index)
            let isDistance = planned.volumeUnit == .distance
            week.update(
                kind: planned.kind.rawValue,
                title: planned.kind.name,
                because: planned.notes.map(\.text).joined(separator: " "),
                startDate: planned.start,
                plannedMeters: isDistance ? planned.plannedVolume : nil,
                plannedSeconds: isDistance ? nil : planned.plannedVolume,
                longRunMeters: planned.longRun.flatMap { $0.meters > 0 ? $0.meters : nil },
                longRunSeconds: planned.longRun.flatMap { $0.seconds > 0 ? $0.seconds : nil },
                outcome: record.review?.outcome.rawValue
            )
            sync(planned, into: week, in: context, unit: unit, calendar: calendar)
        }

        // Weeks the engine no longer has, unless a run was done in them.
        for week in plan.weeks where !plannedIndexes.contains(week.order) {
            if !week.workouts.contains(where: \.isDone) {
                plan.removeWeek(week)
                context.delete(week)
            }
        }
    }

    private static func sync(_ planned: PlannedWeek, into week: CoachWeek, in context: ModelContext, unit: DistanceUnit, calendar: Calendar) {
        var sessionIDs = Set<UUID>()
        for (order, session) in planned.sessions.sorted(by: { ($0.dayOffset, $0.kind.rawValue) < ($1.dayOffset, $1.kind.rawValue) }).enumerated() {
            sessionIDs.insert(session.id)
            let workout = week.workout(withSessionID: session.id)
                ?? week.addWorkout(sessionID: session.id, kind: session.kind.rawValue, dayOffset: session.dayOffset)
            workout.update(
                kind: session.kind.rawValue,
                dayOffset: session.dayOffset,
                date: calendar.date(byAdding: .day, value: session.dayOffset, to: planned.start),
                order: order,
                status: session.status.rawName,
                target: target(for: session, unit: unit, calendar: calendar, weekStart: planned.start)
            )
            syncSteps(of: session, into: workout, in: context)
        }

        // Sessions the engine dropped, unless they were run.
        for workout in week.workouts where !(workout.sessionID.map(sessionIDs.contains) ?? false) {
            if !workout.isDone {
                if let steps = workout.intervalPlan, steps.runs.isEmpty {
                    context.delete(steps)
                }
                week.removeWorkout(workout)
                context.delete(workout)
            }
        }
    }

    /// What the session asks for, as the screens show it.
    static func target(for session: PlannedSession, unit: DistanceUnit, calendar: Calendar = .current, weekStart: Date? = nil) -> CoachWorkoutTarget {
        var detail: [String] = []
        if let dose = session.dose, session.madeEasy == nil {
            detail.append("\(dose.summary) at \(dose.type.effort.name.lowercased()) effort")
        }
        if session.strides > 0 {
            detail.append("Finish with \(session.strides) relaxed strides.")
        }
        if session.isNewLongest {
            detail.append("Your longest run yet.")
        }
        if let reason = session.madeEasy {
            detail.append(reason.explanation)
        }
        if let from = session.movedFrom, let weekStart,
           let date = calendar.date(byAdding: .day, value: from, to: weekStart) {
            detail.append("Moved from \(date.formatted(.dateTime.weekday(.wide))).")
        }

        let leadsWithDistance = session.leadsWith == .distance && session.target.meters > 0
        return CoachWorkoutTarget(
            title: session.madeEasy == nil ? session.kind.name : SessionKind.easy.name,
            detail: detail.joined(separator: " "),
            notes: session.notes.joined(separator: "\n"),
            meters: leadsWithDistance ? session.target.meters : nil,
            seconds: leadsWithDistance || session.target.seconds <= 0 ? nil : session.target.seconds,
            pace: session.paceBand.map { $0.fast...$0.slow },
            effort: session.rpeTarget,
            runWalk: runWalk(session),
            isKeySession: session.isKey,
            isQuality: session.isQuality
        )
    }

    /// "1 min run, 1½ min walk" for run-walk sessions.
    private static func runWalk(_ session: PlannedSession) -> String? {
        guard session.kind == .runWalk else { return nil }
        let steps = session.blocks.max { $0.repeats < $1.repeats }?.steps ?? []
        guard let run = steps.first(where: { !$0.walk && $0.kind == .work }),
              let walk = steps.first(where: \.walk),
              case .time(let runSeconds) = run.goal,
              case .time(let walkSeconds) = walk.goal
        else { return nil }
        return "\(CoachFormat.clock(runSeconds)) run, \(CoachFormat.clock(walkSeconds)) walk"
    }

    /// Keeps the session's steps as an interval workout, so it can be guided, and only rebuilds
    /// them when they change.
    private static func syncSteps(of session: PlannedSession, into workout: CoachWorkout, in context: ModelContext) {
        let signature = session.blocks.isEmpty ? "" : ((try? JSONEncoder().encode(session.blocks)).map { $0.base64EncodedString() } ?? "")
        guard signature != workout.stepsSignature else { return }
        if let old = workout.intervalPlan {
            workout.setIntervalPlan(nil)
            if old.runs.isEmpty { context.delete(old) }
        }
        workout.setStepsSignature(signature)
        guard !session.blocks.isEmpty else { return }

        let steps = IntervalPlan(name: session.kind.name)
        context.insert(steps)
        for block in session.blocks {
            let stored = steps.addBlock(repeatCount: block.repeats)
            for step in block.steps {
                stored.addStep(IntervalStepKind(step.kind), goal: IntervalGoal(step.goal))
            }
        }
        workout.setIntervalPlan(steps)
    }
}

extension CoachPlanStatus {
    init(_ status: PlanStatus) {
        switch status {
        case .active: self = .active
        case .paused: self = .paused
        case .complete: self = .complete
        case .stopped: self = .stopped
        }
    }
}

extension SessionStatus {
    /// How the status is stored with the session's copy.
    var rawName: String {
        switch self {
        case .planned: "planned"
        case .done: "done"
        case .missed: "missed"
        case .dropped: "dropped"
        }
    }
}

extension EasyReason {
    /// Why the session became an easy run, for the session screen.
    var explanation: String {
        switch self {
        case .spacing: "Made easy so hard days don't come back to back."
        case .readiness: "Made easy because your legs or energy were below normal."
        case .extraRun: "Made easy because an extra hard run already took this week's hard session."
        case .mildInjury: "Made easy while your injury settles."
        case .adaptation: "Made easy for a lighter week."
        case .illness: "Made easy while you get over your cold."
        case .budget: "Made easy to keep the week inside your recovery budget."
        }
    }
}

extension IntervalStepKind {
    init(_ kind: SessionStepKind) {
        switch kind {
        case .warmup: self = .warmup
        case .work: self = .work
        case .recovery: self = .recovery
        case .cooldown: self = .cooldown
        }
    }
}

extension IntervalGoal {
    init(_ goal: StepGoal) {
        switch goal {
        case .time(let seconds): self = .time(seconds)
        case .distance(let meters): self = .distance(meters: meters)
        case .open: self = .open
        }
    }
}
