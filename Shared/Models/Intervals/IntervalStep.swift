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

/// The steps a runner can pick when building a workout: the coach's step kinds, with its walk step on
/// its own, under the names the coach uses mid-run.
enum IntervalStepChoice: String, CaseIterable, Identifiable {
    case warmup
    case work
    case recovery
    case walk
    case cooldown

    var id: Self { self }

    init(kind: IntervalStepKind, isWalk: Bool) {
        if isWalk {
            self = .walk
            return
        }
        switch kind {
        case .warmup: self = .warmup
        case .work: self = .work
        case .recovery: self = .recovery
        case .cooldown: self = .cooldown
        }
    }

    var kind: IntervalStepKind {
        switch self {
        case .warmup: .warmup
        case .work: .work
        case .recovery, .walk: .recovery
        case .cooldown: .cooldown
        }
    }

    var isWalk: Bool { self == .walk }

    var name: String { isWalk ? "Walk" : kind.name }

    /// What the step asks for, for the builder.
    var detail: String {
        switch self {
        case .warmup: "Easy running to get going."
        case .work: "The fast part: a hard, steady effort."
        case .recovery: "Easy jogging to get your breath back."
        case .walk: "Walk, or go as slowly as you like."
        case .cooldown: "Easy running to finish."
        }
    }

    var systemImage: String {
        switch self {
        case .warmup: "figure.walk.motion"
        case .work: "bolt.fill"
        case .recovery: "figure.run"
        case .walk: "figure.walk"
        case .cooldown: "wind"
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

    var isWalk: Bool {
        get { isWalkValue }
        set { isWalkValue = newValue }
    }

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
