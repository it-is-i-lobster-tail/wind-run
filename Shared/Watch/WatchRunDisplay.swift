//
//  WatchRunDisplay.swift
//  Wind Run
//

import Foundation

/// The workout around the Watch's display screen: the header beside the clock, and what the run's steps or
/// coach session need under the headlines. The numbers themselves come from the display screen.
///
/// While an open step waits for the runner to tap on, the grid gives way to what comes next and a Next step
/// button. A timed or distance step adds a line counting down to the next step; a coach session adds its
/// pace range.
struct WatchRunDisplay: Equatable {
    /// A short line: a small caption, a value and a quieter detail. "NEXT Recover in 2:37", "TARGET 4:50–5:05 /km".
    struct Line: Equatable {
        var caption: String?
        var value: String
        var detail: String?
    }

    /// What fills the screen under the headlines.
    enum Lower: Equatable {
        /// The display screen's grid, with a line about the workout over it when there's one to say.
        case grid(Line?)
        /// An open step that ends on the runner's tap: what comes next, over a Next step button.
        case nextStep(Line)
    }

    /// "FREE RUN", "RECOVER · 3/12", "EASY RUN", "PAUSED".
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
            lower = .grid(Self.workoutLine(input, coach: coach))
        }
    }

    private static func title(_ input: Input, coach: CoachWorkoutTarget?) -> String {
        if input.status == .paused {
            return input.isAutoPaused ? "AUTO-PAUSED" : "PAUSED"
        }
        if let steps = input.steps {
            guard let step = steps.current else { return "STEPS DONE" }
            return "\(step.name.uppercased()) · \(steps.index + 1)/\(steps.timeline.count)"
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

    /// Over the grid: what's left of a timed or distance step, an open last step that runs to the finish,
    /// or the coach's pace range. Nil for a free run.
    private static func workoutLine(_ input: Input, coach: CoachWorkoutTarget?) -> Line? {
        if let steps = input.steps, let step = steps.current {
            let left: String? = switch steps.remaining(elapsed: input.elapsed, meters: input.meters) {
            case .time(let seconds): RunFormat.duration(seconds.rounded(.up))
            case .distance(let meters): RunFormat.goal(.distance(meters: meters.rounded(.up)), unit: input.unit)
            case .open, nil: nil
            }
            if let left {
                let nextIndex = steps.index + 1
                if steps.timeline.indices.contains(nextIndex) {
                    return Line(caption: "NEXT", value: steps.timeline[nextIndex].name, detail: "in \(left)")
                }
                return Line(caption: "LAST STEP", value: left, detail: "left")
            }
            if steps.runsUntilFinish {
                return Line(caption: "LAST STEP", value: step.name, detail: "until you finish")
            }
            return nil
        }
        if let pace = coach?.pace {
            let fast = RunFormat.pace(pace.lowerBound, unit: input.unit, withUnit: false)
            let slow = RunFormat.pace(pace.upperBound, unit: input.unit, withUnit: false)
            return Line(caption: "TARGET", value: fast == slow ? fast : "\(fast)–\(slow)", detail: "/\(input.unit.symbol)")
        }
        return nil
    }
}
