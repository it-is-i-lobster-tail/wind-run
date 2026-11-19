//
//  WatchCoachSession.swift
//  Wind Run
//

import Foundation
import SwiftData

/// One of today's coach sessions as the iPhone hands it to the watch: what to show, and its steps, so the
/// watch can run it the way the iPhone would. The coach itself stays on the iPhone.
struct WatchCoachSession: Codable, Hashable, Identifiable {
    /// One step of a block, with its goal as plain values.
    struct Step: Codable, Hashable {
        var kind: IntervalStepKind
        var goalKind: IntervalGoalKind
        /// Seconds for a time goal, meters for a distance goal, 0 when open.
        var goalAmount: Double
        var isWalk: Bool

        var goal: IntervalGoal {
            switch goalKind {
            case .time: .time(goalAmount)
            case .distance: .distance(meters: goalAmount)
            case .open: .open
            }
        }
    }

    /// Steps repeated `repeatCount` times, as `IntervalBlock` holds them.
    struct Block: Codable, Hashable {
        var repeatCount: Int
        var steps: [Step]
    }

    var sessionID: UUID
    var kind: String
    var title: String
    var detail: String
    /// The day the session is planned for.
    var date: Date
    var targetMeters: Double?
    var targetSeconds: TimeInterval?
    /// Seconds per kilometer, the faster end first.
    var paceFast: TimeInterval?
    var paceSlow: TimeInterval?
    var effortLow: Int?
    var effortHigh: Int?
    var runWalk: String?
    var isKeySession: Bool
    var isQuality: Bool
    /// The iPhone's fingerprint of these steps, so the run that comes back is matched to the same steps.
    var stepsSignature: String
    /// Empty for a session without steps, such as an easy run.
    var blocks: [Block]

    var id: UUID { sessionID }

    var target: CoachWorkoutTarget {
        CoachWorkoutTarget(
            title: title,
            detail: detail,
            notes: "",
            meters: targetMeters,
            seconds: targetSeconds,
            pace: paceFast.flatMap { fast in paceSlow.flatMap { slow in slow >= fast ? fast...slow : nil } },
            effort: effortLow.flatMap { low in effortHigh.flatMap { high in high >= low ? low...high : nil } },
            runWalk: runWalk,
            isKeySession: isKeySession,
            isQuality: isQuality
        )
    }

    /// Every step in the order it's run, with repeats written out, as `IntervalPlan.timeline` has it.
    var timeline: [PlannedIntervalStep] {
        blocks.timeline
    }
}

extension WatchCoachSession.Step {
    /// A step of the iPhone's plan, for sending.
    init(_ step: IntervalStep) {
        self.init(kind: step.kind, goalKind: step.goalKindValue, goalAmount: step.goalAmountValue, isWalk: step.isWalk)
    }
}

extension WatchCoachSession.Block {
    /// A block of the iPhone's plan, for sending.
    init(_ block: IntervalBlock) {
        self.init(repeatCount: block.repeatCount, steps: block.steps.map { WatchCoachSession.Step($0) })
    }
}

extension Array where Element == WatchCoachSession.Block {
    /// Every step in the order it's run, with repeats written out. A repeat count under 1 runs once.
    var timeline: [PlannedIntervalStep] {
        flatMap { block in
            (1...Swift.max(1, block.repeatCount)).flatMap { repetition in
                block.steps.map {
                    PlannedIntervalStep(kind: $0.kind, goal: $0.goal, repetition: repetition, repeatCount: Swift.max(1, block.repeatCount), isWalk: $0.isWalk)
                }
            }
        }
    }
}

extension IntervalPlan {
    /// Adds the blocks as the watch got them, in order.
    func addBlocks(_ blocks: [WatchCoachSession.Block]) {
        for block in blocks {
            let copy = addBlock(repeatCount: block.repeatCount)
            for step in block.steps {
                copy.addStep(step.kind, goal: step.goal, isWalk: step.isWalk)
            }
        }
    }
}

extension WatchCoachSession {
    /// The iPhone's copy of a session, for sending. Nil without the engine's session id or a day.
    init?(_ workout: CoachWorkout) {
        guard let sessionID = workout.sessionID, let date = workout.scheduledDate else { return nil }
        let target = workout.target
        self.init(
            sessionID: sessionID,
            kind: workout.kind,
            title: target.title,
            detail: target.detail,
            date: date,
            targetMeters: target.meters,
            targetSeconds: target.seconds,
            paceFast: target.pace?.lowerBound,
            paceSlow: target.pace?.upperBound,
            effortLow: target.effort?.lowerBound,
            effortHigh: target.effort?.upperBound,
            runWalk: target.runWalk,
            isKeySession: target.isKeySession,
            isQuality: target.isQuality,
            stepsSignature: workout.stepsSignature,
            blocks: (workout.intervalPlan?.blocks ?? []).map { Block($0) }
        )
    }

    /// The watch's own copy of the session to run, with its steps, inserted into `context`. The run keeps
    /// it, so its steps read the same later.
    func makeWorkout(in context: ModelContext) -> CoachWorkout {
        let workout = CoachWorkout(sessionID: sessionID, kind: kind, dayOffset: 0)
        workout.update(kind: kind, dayOffset: 0, date: date, order: 0, status: "planned", target: target)
        workout.setStepsSignature(stepsSignature)
        if !blocks.isEmpty {
            let plan = IntervalPlan(name: title)
            plan.addBlocks(blocks)
            context.insert(plan)
            workout.setIntervalPlan(plan)
        }
        context.insert(workout)
        return workout
    }

    // MARK: The watch's home

    /// The sessions planned for `now`'s day, leaving out the ones in `doneSessionIDs`.
    static func toDo(_ sessions: [WatchCoachSession], doneSessionIDs: Set<UUID>, now: Date = .now, calendar: Calendar = .current) -> [WatchCoachSession] {
        sessions.filter { session in
            calendar.isDate(session.date, inSameDayAs: now) && !doneSessionIDs.contains(session.sessionID)
        }
    }

    /// Whether any of the sessions is planned for `now`'s day, run or not.
    static func anyPlanned(_ sessions: [WatchCoachSession], on now: Date = .now, calendar: Calendar = .current) -> Bool {
        sessions.contains { calendar.isDate($0.date, inSameDayAs: now) }
    }

    /// "40 min · 4:50–5:05 /km", as the iPhone's coach writes it, hours and all from an hour, or how long a
    /// session with steps is: "45 min". Nil when it asks for nothing.
    func summary(unit: DistanceUnit) -> String? {
        guard !timeline.isEmpty else {
            let summary = CoachFormat.targetSummary(target, unit: unit)
            return summary.isEmpty ? nil : summary
        }
        var parts = [RunFormat.intervalLength(timeline, unit: unit)]
        if let pace = target.pace {
            parts.append(RunFormat.paceRange(pace, unit: unit))
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Sending

    static func encode(_ sessions: [WatchCoachSession]) -> Data? {
        try? JSONEncoder().encode(sessions)
    }

    /// One session the watch can't read, such as from a newer iPhone app, drops only itself.
    static func decode(_ data: Data?) -> [WatchCoachSession] {
        guard let data else { return [] }
        return LossyList<WatchCoachSession>.decode(data, what: "coach sessions")
    }
}
