//
//  WatchSavedWorkout.swift
//  Wind Run
//

import Foundation
import SwiftData

/// A workout from the iPhone's Intervals page as the watch gets it, so it starts from the wrist in one tap.
/// Workouts are built and changed on the iPhone; the watch keeps the last list it was sent.
struct WatchSavedWorkout: Codable, Hashable, Identifiable {
    var name: String
    var createdDate: Date
    var blocks: [WatchCoachSession.Block]

    var id: String { "\(createdDate.timeIntervalSinceReferenceDate)-\(name)" }

    /// Every step in the order it's run, with repeats written out.
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

extension WatchSavedWorkout {
    /// The iPhone's saved workout, for sending.
    init(_ plan: IntervalPlan) {
        self.init(
            name: plan.name,
            createdDate: plan.createdDateValue,
            blocks: plan.blocks.map { block in
                WatchCoachSession.Block(repeatCount: block.repeatCount, steps: block.steps.map { step in
                    WatchCoachSession.Step(kind: step.kind, goalKind: step.goalKindValue, goalAmount: step.goalAmountValue, isWalk: step.isWalk)
                })
            }
        )
    }

    /// The watch's own copy of the workout to run, inserted into `context`. The run keeps it, so its steps
    /// read the same later. It isn't a saved workout on the watch: the list stays the iPhone's.
    func makePlan(in context: ModelContext) -> IntervalPlan {
        let plan = IntervalPlan(name: name, isCustom: false)
        for block in blocks {
            let copy = plan.addBlock(repeatCount: block.repeatCount)
            for step in block.steps {
                copy.addStep(step.kind, goal: step.goal, isWalk: step.isWalk)
            }
        }
        context.insert(plan)
        return plan
    }

    // MARK: Sending

    static func encode(_ workouts: [WatchSavedWorkout]) -> Data? {
        try? JSONEncoder().encode(workouts)
    }

    static func decode(_ data: Data?) -> [WatchSavedWorkout] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([WatchSavedWorkout].self, from: data)) ?? []
    }
}
