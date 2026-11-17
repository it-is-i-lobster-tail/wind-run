//
//  WatchRunDisplay.swift
//  Wind Run
//

import Foundation

/// The workout around the Watch's display screen: the header beside the clock, and whether the grid gives
/// way to a Next step button. The numbers themselves come from the display screen, at the same size in
/// every state.
///
/// The header names the run or the step: "FREE RUN", "EASY RUN", "RECOVER · 3/12". A timed or distance step
/// counts down in it instead: "WORK · 2:37", "WORK · 320 m". While an open step waits for the runner to tap
/// on, the grid's bottom row gives way to what comes next and a Next step button.
struct WatchRunDisplay: Equatable {
    /// A short line: a small caption and a value. "NEXT Work · 3:00".
    struct Line: Equatable {
        var caption: String?
        var value: String
    }

    /// What fills the screen under the headlines.
    enum Lower: Equatable {
        /// The display screen's grid.
        case grid
        /// An open step that ends on the runner's tap: the grid's top row, then what comes next over a
        /// Next step button.
        case nextStep(Line)
    }

    /// "FREE RUN", "RECOVER · 3/12", "WORK · 2:37", "EASY RUN", "PAUSED".
    var title: String
    var lower: Lower

    /// The run at one moment.
    struct Input {
        var status: RunStatus
        var isAutoPaused = false
        /// Running time, leaving out pauses.
        var elapsed: TimeInterval
        var meters: Double
        var unit: DistanceUnit
        var steps: StepTracker?
        /// The coach session being run, if it is one.
        var coach: CoachWorkoutTarget?
    }

    init(_ input: Input) {
        // A session with steps is led by its steps.
        let coach = input.steps == nil ? input.coach : nil
        title = Self.title(input, coach: coach)
        if let steps = input.steps, steps.waitsForTap {
            lower = .nextStep(Self.nextPreview(steps, unit: input.unit))
        } else {
            lower = .grid
        }
    }

    private static func title(_ input: Input, coach: CoachWorkoutTarget?) -> String {
        if input.status == .paused {
            return input.isAutoPaused ? "AUTO-PAUSED" : "PAUSED"
        }
        if let steps = input.steps {
            guard let step = steps.current else { return "STEPS DONE" }
            let name = step.name.uppercased()
            switch steps.remaining(elapsed: input.elapsed, meters: input.meters) {
            case .time(let seconds):
                return "\(name) · \(RunFormat.duration(seconds.rounded(.up)))"
            case .distance(let meters):
                return "\(name) · \(RunFormat.goal(.distance(meters: meters.rounded(.up)), unit: input.unit))"
            case .open, nil:
                return "\(name) · \(steps.index + 1)/\(steps.timeline.count)"
            }
        }
        if let title = coach?.title, !title.isEmpty {
            return title.uppercased()
        }
        return "FREE RUN"
    }

    /// The step after the one waiting for the tap: "Work · 3:00", "Cool down · 1.00 km", or "Walk".
    private static func nextPreview(_ steps: StepTracker, unit: DistanceUnit) -> Line {
        let nextIndex = steps.index + 1
        guard steps.timeline.indices.contains(nextIndex) else {
            return Line(caption: "NEXT", value: "Run as you like")
        }
        let next = steps.timeline[nextIndex]
        let value = switch next.goal {
        case .time(let seconds): "\(next.name) · \(RunFormat.duration(seconds))"
        case .distance: "\(next.name) · \(RunFormat.goal(next.goal, unit: unit))"
        case .open: next.name
        }
        return Line(caption: "NEXT", value: value)
    }
}
