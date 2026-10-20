//
//  IntervalStep.swift
//  Wind Run
//

import Foundation
import SwiftData

/// What a step asks of the runner.
enum IntervalStepKind: String, Codable, CaseIterable {
    case warmup
    case work
    case recovery
    case cooldown

    var name: String {
        switch self {
        case .warmup: "Warm up"
        case .work: "Work"
        case .recovery: "Recover"
        case .cooldown: "Cool down"
        }
    }
}

/// When a step ends: after a time, after a distance, or when the runner taps on.
enum IntervalGoal: Hashable {
    case time(TimeInterval)
    case distance(meters: Double)
    case open
}

/// How the goal is stored, since SwiftData keeps flat values more reliably than enums with payloads.
enum IntervalGoalKind: String, Codable {
    case time
    case distance
    case open
}

/// One step of a block, such as "3 min hard".
@Model
final class IntervalStep {
    var orderValue: Int = 0
    var kindValue: IntervalStepKind = IntervalStepKind.work
    var goalKindValue: IntervalGoalKind = IntervalGoalKind.open
    /// Seconds for a time goal, meters for a distance goal, unused when open.
    var goalAmountValue: Double = 0
    /// A walking step, such as a run-walk session's walk break.
    var isWalkValue: Bool = false

    var blockValue: IntervalBlock?

    init(kind: IntervalStepKind, goal: IntervalGoal, order: Int = 0, isWalk: Bool = false) {
        self.kindValue = kind
        self.orderValue = order
        self.isWalkValue = isWalk
        self.goal = goal
    }
}

extension IntervalStep {
    var order: Int {
        get { orderValue }
        set { orderValue = newValue }
    }

    var kind: IntervalStepKind {
        get { kindValue }
        set { kindValue = newValue }
    }

    var isWalk: Bool { isWalkValue }

    var goal: IntervalGoal {
        get {
            switch goalKindValue {
            case .time: .time(goalAmountValue)
            case .distance: .distance(meters: goalAmountValue)
            case .open: .open
            }
        }
        set {
            switch newValue {
            case .time(let seconds):
                goalKindValue = .time
                goalAmountValue = seconds
            case .distance(let meters):
                goalKindValue = .distance
                goalAmountValue = meters
            case .open:
                goalKindValue = .open
                goalAmountValue = 0
            }
        }
    }
}
