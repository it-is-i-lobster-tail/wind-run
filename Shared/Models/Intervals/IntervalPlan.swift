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
    /// True for a workout the runner built on the Intervals page; false once they deleted or edited it
    /// but a run still uses it; nil for the coach's session steps. Optional so older stores still load.
    var isCustomValue: Bool?

    // To-many relationships are optional because iCloud sync requires it.
    @Relationship(deleteRule: .cascade, inverse: \IntervalBlock.planValue)
    var blocksValue: [IntervalBlock]? = []

    @Relationship(deleteRule: .nullify, inverse: \Run.intervalPlanValue)
    var runsValue: [Run]? = []

    /// Coach sessions that use this workout. iCloud sync needs every relationship to have an inverse.
    @Relationship(deleteRule: .nullify, inverse: \CoachWorkout.intervalPlanValue)
    var coachWorkoutsValue: [CoachWorkout]? = []

    init(name: String, createdDate: Date = .now, isCustom: Bool? = nil) {
        self.nameValue = name
        self.createdDateValue = createdDate
        self.isCustomValue = isCustom
    }
}

/// One step as the runner will meet it, with its place among the repeats.
struct PlannedIntervalStep: Hashable {
    let kind: IntervalStepKind
    let goal: IntervalGoal
    /// 1-based repeat number within its block.
    let repetition: Int
    let repeatCount: Int
    /// A walking step, such as a walk break.
    var isWalk = false

    /// The step's name mid-run: "Work", or "Walk" for a walking step.
    var name: String { IntervalStepChoice(kind: kind, isWalk: isWalk).name }
}

extension IntervalPlan {
    var name: String {
        get { nameValue }
        set { nameValue = newValue }
    }

    var blocks: [IntervalBlock] {
        (blocksValue ?? []).sorted { $0.order < $1.order }
    }

    var runs: [Run] { runsValue ?? [] }

    /// A workout the runner built and still keeps on the Intervals page.
    var isSavedWorkout: Bool { isCustomValue == true }

    /// Takes a saved workout off the Intervals page. It's deleted later by `deleteRemoved`, once no screen
    /// shows it, unless runs done with it need its steps.
    func remove() {
        isCustomValue = false
    }

    /// Deletes workouts taken off the Intervals page that no run uses.
    static func deleteRemoved(in context: ModelContext) {
        let plans = (try? context.fetch(FetchDescriptor<IntervalPlan>())) ?? []
        let unused = plans.filter { $0.isCustomValue == false && $0.runs.isEmpty }
        guard !unused.isEmpty else { return }
        for plan in unused {
            context.delete(plan)
        }
        context.saveQuietly()
    }

    @discardableResult
    func addBlock(repeatCount: Int = 1) -> IntervalBlock {
        let block = IntervalBlock(repeatCount: repeatCount, order: (blocks.last?.order ?? -1) + 1)
        blocksValue = (blocksValue ?? []) + [block]
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
                        repeatCount: block.repeatCount,
                        isWalk: $0.isWalk
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
