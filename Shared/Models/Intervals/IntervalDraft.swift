//
//  IntervalDraft.swift
//  Wind Run
//

import Foundation
import SwiftData

/// A workout being built or changed on the Intervals page. It's plain values, so nothing is stored until
/// the runner taps Save, and a workout a run already used is never changed under that run.
struct IntervalDraft: Equatable {
    struct Step: Equatable, Identifiable {
        var id = UUID()
        var choice: IntervalStepChoice
        var goal: IntervalGoal

        /// A new step of this kind with a sensible start: open for any step, minutes for the rest.
        static func new(_ choice: IntervalStepChoice, open: Bool = false) -> Step {
            if open { return Step(choice: choice, goal: .open) }
            let minutes: Double = switch choice {
            case .warmup, .cooldown: 10
            case .work: 3
            case .recovery, .walk: 2
            }
            return Step(choice: choice, goal: .time(minutes * 60))
        }
    }

    /// One step on its own, or steps repeated.
    struct Block: Equatable, Identifiable {
        var id = UUID()
        var repeatCount: Int
        var steps: [Step]

        /// A block the runner sees as a repeat, even at one time through or with one step.
        var isRepeat: Bool

        static func single(_ step: Step) -> Block {
            Block(repeatCount: 1, steps: [step], isRepeat: false)
        }

        /// Work and recover, repeated: the usual shape of a set.
        static func newRepeat() -> Block {
            Block(repeatCount: 4, steps: [.new(.work), .new(.recovery)], isRepeat: true)
        }
    }

    static let timeRange: ClosedRange<TimeInterval> = 5...(5 * 3_600)
    static let distanceRange: ClosedRange<Double> = 50...100_000

    var name: String
    var blocks: [Block]

    /// A new workout, started with a warm up, a set of repeats and a cool down to change.
    static func starter() -> IntervalDraft {
        IntervalDraft(name: "", blocks: [
            .single(.new(.warmup)),
            .newRepeat(),
            .single(.new(.cooldown)),
        ])
    }

    /// The draft of a saved workout.
    init(_ plan: IntervalPlan) {
        self.name = plan.name
        self.blocks = plan.blocks.map { block in
            let steps = block.steps.map { Step(choice: IntervalStepChoice(kind: $0.kind, isWalk: $0.isWalk), goal: $0.goal) }
            return Block(repeatCount: block.repeatCount, steps: steps, isRepeat: block.repeatCount > 1 || steps.count > 1)
        }
    }

    init(name: String, blocks: [Block]) {
        self.name = name
        self.blocks = blocks
    }

    /// The name to save: the runner's, or one made from the steps when they left it blank.
    var trimmedName: String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((typed.isEmpty ? suggestedName : typed).prefix(IntervalPlan.nameLimit))
    }

    /// A name from the first set of repeats, like "5 × 3 min" or "8 × 400 m", in kilometers. Without
    /// repeats it's "Intervals".
    var suggestedName: String {
        guard let repeats = blocks.first(where: { $0.repeatCount > 1 && !$0.steps.isEmpty }),
              let work = repeats.steps.first(where: { $0.choice == .work }) ?? repeats.steps.first
        else { return "Intervals" }
        let length = switch work.goal {
        case .time(let seconds) where seconds.truncatingRemainder(dividingBy: 60) == 0: "\(Int(seconds / 60)) min"
        case .time(let seconds): "\(Int(seconds)) s"
        case .distance(let meters) where meters < 1_000: "\(Int(meters.rounded())) m"
        case .distance(let meters): "\((meters / 1_000).formatted(.number.precision(.fractionLength(0...2)))) km"
        case .open: "open"
        }
        return "\(repeats.repeatCount) × \(length)"
    }

    /// Every step in the order it's run, with repeats written out.
    var timeline: [PlannedIntervalStep] {
        blocks.flatMap { block in
            (1...IntervalBlock.clampedRepeats(block.repeatCount)).flatMap { repetition in
                block.steps.map {
                    PlannedIntervalStep(kind: $0.choice.kind, goal: $0.goal, repetition: repetition, repeatCount: block.repeatCount, isWalk: $0.choice.isWalk)
                }
            }
        }
    }

    /// Why the workout can't be saved yet, or nil when it can.
    var problem: String? {
        if blocks.allSatisfy({ $0.steps.isEmpty }) { return "Add at least one step." }
        return nil
    }

    var canSave: Bool { problem == nil }

    /// Saves the draft as a workout on the Intervals page and returns it. Changing a workout that no run has
    /// used yet changes it in place; one a run used is kept for that run and a new one takes its place.
    @discardableResult
    func save(replacing original: IntervalPlan?, in context: ModelContext) -> IntervalPlan {
        let plan: IntervalPlan
        if let original, original.runs.isEmpty {
            plan = original
            // Unlinked before they're deleted, so nothing reaches a deleted block through the plan.
            let old = original.blocks
            plan.blocksValue = []
            for block in old {
                context.delete(block)
            }
        } else {
            original?.isCustomValue = false
            plan = IntervalPlan(name: trimmedName, createdDate: original?.createdDateValue ?? .now, isCustom: true)
            context.insert(plan)
        }
        plan.name = trimmedName
        plan.isCustomValue = true
        for block in blocks where !block.steps.isEmpty {
            let stored = plan.addBlock(repeatCount: block.repeatCount)
            for step in block.steps {
                stored.addStep(step.choice.kind, goal: Self.clamped(step.goal), isWalk: step.choice.isWalk)
            }
        }
        context.saveQuietly()
        return plan
    }

    /// Keeps a step's time or distance inside what a run can sensibly hold.
    static func clamped(_ goal: IntervalGoal) -> IntervalGoal {
        switch goal {
        case .time(let seconds): .time(min(max(seconds, timeRange.lowerBound), timeRange.upperBound))
        case .distance(let meters): .distance(meters: min(max(meters, distanceRange.lowerBound), distanceRange.upperBound))
        case .open: .open
        }
    }
}
