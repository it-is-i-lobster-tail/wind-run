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
        blocks.flatMap { block in
            (1...max(1, block.repeatCount)).flatMap { repetition in
                block.steps.map {
                    PlannedIntervalStep(kind: $0.kind, goal: $0.goal, repetition: repetition, repeatCount: max(1, block.repeatCount), isWalk: $0.isWalk)
                }
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
            blocks: (workout.intervalPlan?.blocks ?? []).map { block in
                Block(repeatCount: block.repeatCount, steps: block.steps.map { step in
                    Step(kind: step.kind, goalKind: step.goalKindValue, goalAmount: step.goalAmountValue, isWalk: step.isWalk)
                })
            }
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
            for block in blocks {
                let copy = plan.addBlock(repeatCount: block.repeatCount)
                for step in block.steps {
                    copy.addStep(step.kind, goal: step.goal, isWalk: step.isWalk)
                }
            }
            context.insert(plan)
            workout.setIntervalPlan(plan)
        }
        context.insert(workout)
        return workout
    }

    // MARK: Sending

    static func encode(_ sessions: [WatchCoachSession]) -> Data? {
        try? JSONEncoder().encode(sessions)
    }

    static func decode(_ data: Data?) -> [WatchCoachSession] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([WatchCoachSession].self, from: data)) ?? []
    }
}
