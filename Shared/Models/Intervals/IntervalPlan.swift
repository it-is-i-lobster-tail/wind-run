//
//  IntervalPlan.swift
//  Wind Run
//

import Foundation
import SwiftData

/// A saved interval workout, such as "10 min warm up, 5 × (3 min hard, 2 min easy), 10 min cool down".
@Model
final class IntervalPlan {
    static let nameLimit = 40

    var nameValue: String = ""
    var createdDateValue: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \IntervalBlock.planValue)
    var blocksValue: [IntervalBlock] = []

    @Relationship(deleteRule: .nullify, inverse: \Run.intervalPlanValue)
    var runsValue: [Run] = []

    init(name: String, createdDate: Date = .now) {
        self.nameValue = name
        self.createdDateValue = createdDate
    }
}

/// One step as the runner will meet it, with its place among the repeats.
struct PlannedIntervalStep: Hashable {
    let kind: IntervalStepKind
    let goal: IntervalGoal
    /// 1-based repeat number within its block.
    let repetition: Int
    let repeatCount: Int
}

extension IntervalPlan {
    var name: String {
        get { nameValue }
        set { nameValue = newValue }
    }

    var blocks: [IntervalBlock] {
        blocksValue.sorted { $0.order < $1.order }
    }

    var runs: [Run] { runsValue }

    @discardableResult
    func addBlock(repeatCount: Int = 1) -> IntervalBlock {
        let block = IntervalBlock(repeatCount: repeatCount, order: (blocks.last?.order ?? -1) + 1)
        blocksValue.append(block)
        return block
    }

    /// Every step in the order it's run, with repeats written out.
    var timeline: [PlannedIntervalStep] {
        blocks.flatMap { block in
            (1...block.repeatCount).flatMap { repetition in
                block.steps.map {
                    PlannedIntervalStep(
                        kind: $0.kind,
                        goal: $0.goal,
                        repetition: repetition,
                        repeatCount: block.repeatCount
                    )
                }
            }
        }
    }

    /// Total time of the timed steps. Distance and open steps aren't counted.
    var timedDuration: TimeInterval {
        timeline.reduce(0) { total, step in
            if case .time(let seconds) = step.goal { total + seconds } else { total }
        }
    }

    /// The workout the brief describes: 10 min warm up, 5 × (3 min hard, 2 min easy), 10 min cool down.
    static func classicFiveByThree() -> IntervalPlan {
        let plan = IntervalPlan(name: "5 × 3 min")
        plan.addBlock().addStep(.warmup, goal: .time(10 * 60))
        let repeats = plan.addBlock(repeatCount: 5)
        repeats.addStep(.work, goal: .time(3 * 60))
        repeats.addStep(.recovery, goal: .time(2 * 60))
        plan.addBlock().addStep(.cooldown, goal: .time(10 * 60))
        return plan
    }
}
