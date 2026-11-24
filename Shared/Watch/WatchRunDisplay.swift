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
        /// button titled `button`, "Next step", or "Run again" on a walk break.
        case nextStep(Line, button: String)
    }

    /// "FREE RUN", "RECOVER · 3/12", "WORK · 2:37", "EASY RUN", "PAUSED".
    var title: String
    var lower: Lower
    /// What GPS can't do right now, shown as a symbol by the header, or nil while it's fine.
    var gpsProblem: GPSProblem?

    /// Why the run can't count distance, or might not be.
    enum GPSProblem: Equatable {
        /// Location isn't allowed, or Precise Location is off: no distance this run.
        case off
        /// Still finding GPS, or the signal has gone.
        case weak

        var symbol: String {
            switch self {
            case .off: "location.slash.fill"
            case .weak: "location"
            }
        }

        var spoken: String {
            switch self {
            case .off: "No GPS"
            case .weak: "GPS weak"
            }
        }
    }

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
        /// The target picked for a standalone distance or timed run.
        var goal: RunGoal? = nil
        var goalReached = false
        /// How GPS is doing, and whether location is off for the app altogether.
        var gps: GPSSignal = .good
        var locationOff = false
    }

    init(_ input: Input) {
        // A session with steps is led by its steps.
        let coach = input.steps == nil ? input.coach : nil
        title = Self.title(input, coach: coach)
        if let steps = input.steps, steps.waitsForTap, let step = steps.current {
            lower = .nextStep(Self.nextPreview(steps, unit: input.unit), button: step.openStepButtonTitle)
        } else {
            lower = .grid
        }
        if input.locationOff {
            gpsProblem = .off
        } else if input.gps != .good, input.status == .active {
            gpsProblem = .weak
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
                return "\(name) · \(RunFormat.goal(.distance(meters: meters), unit: input.unit, rounding: .up))"
            case .open, nil:
                return "\(name) · \(steps.index + 1)/\(steps.timeline.count)"
            }
        }
        if let title = coach?.title, !title.isEmpty {
            return title.uppercased()
        }
        if input.goal != nil, input.goalReached {
            return "GOAL REACHED"
        }
        let choice: WorkoutChoice = switch input.goal {
        case .distance: .distanceRun
        case .time: .timedRun
        case nil: .freeRun
        }
        return choice.name.uppercased()
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
