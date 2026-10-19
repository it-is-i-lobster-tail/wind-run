//
//  IntervalBlock.swift
//  Wind Run
//

import Foundation
import OSLog
import SwiftData

/// A run of steps repeated some number of times. A warm up is a block of one step done once;
/// "5 × (3 min hard, 2 min easy)" is a block of two steps repeated five times.
@Model
final class IntervalBlock {
    static let repeatRange = 1...50

    var orderValue: Int = 0
    var repeatCountValue: Int = 1

    @Relationship(deleteRule: .cascade, inverse: \IntervalStep.blockValue)
    var stepsValue: [IntervalStep] = []

    var planValue: IntervalPlan?

    init(repeatCount: Int = 1, order: Int = 0) {
        self.repeatCountValue = Self.clampedRepeats(repeatCount)
        self.orderValue = order
    }

    static func clampedRepeats(_ count: Int) -> Int {
        min(max(count, repeatRange.lowerBound), repeatRange.upperBound)
    }
}

extension IntervalBlock {
    var order: Int {
        get { orderValue }
        set { orderValue = newValue }
    }

    var repeatCount: Int {
        get { repeatCountValue }
        set { repeatCountValue = Self.clampedRepeats(newValue) }
    }

    var steps: [IntervalStep] {
        stepsValue.sorted { $0.order < $1.order }
    }

    func addStep(_ kind: IntervalStepKind, goal: IntervalGoal) {
        let step = IntervalStep(kind: kind, goal: goal, order: (steps.last?.order ?? -1) + 1)
        stepsValue.append(step)
    }
}
