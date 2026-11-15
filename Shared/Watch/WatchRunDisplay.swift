//
//  WatchRunDisplay.swift
//  Wind Run
//

import Foundation

/// What the Watch run screen shows at one moment, worked out from the run, so the screen only lays it out.
///
/// The screen reads top to bottom: what kind of run or which step, the time running, the distance, heart
/// rate, then the pace now with one line under it. While an open step waits for the runner to tap on, the
/// pace gives way to what comes next and a Next step button.
struct WatchRunDisplay: Equatable {
    /// A short line: an optional symbol, a small caption, a value and a quieter detail.
    /// "↓ 43 m below start", "NEXT Recover in 2:37", "TARGET 4:50–5:05 /km".
    struct Line: Equatable {
        var symbol: String?
        var caption: String?
        var value: String
        var detail: String?
    }

    /// What fills the screen below heart rate.
    enum Lower: Equatable {
        /// The pace right now, with a line under it.
        case pace(value: String, unit: String, footer: Line?)
        /// An open step that ends on the runner's tap: what comes next, over a Next step button.
        case nextStep(Line)
    }

    /// "FREE RUN", "RECOVER · 3/12", "EASY RUN", "PAUSED".
    var title: String
    var isPaused: Bool
    var elapsed: String
    /// "ELAPSED", or "OF 40:00" for a coach session with a time to run.
    var elapsedLabel: String
    var distance: String
    var distanceUnit: String
    /// "DISTANCE", or "OF 8.00 KM" for a coach session with a distance to run.
    var distanceLabel: String
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
        /// Seconds per kilometer over the last stretch, or nil when there's none to show.
        var currentPace: TimeInterval?
        /// Meters above the start, negative below, or nil when there's no height.
        var heightFromStart: Double?
    }

    init(_ input: Input) {
        let unit = input.unit
        let steps = input.steps
        // A session with steps is led by its steps; the session's own distance or time is the steps' sum.
        let coach = steps == nil ? input.coach : nil
        isPaused = input.status == .paused
        title = Self.title(input, coach: coach)
        elapsed = RunFormat.duration(input.elapsed)
        if let seconds = coach?.seconds, seconds > 0 {
            elapsedLabel = "OF \(RunFormat.duration(seconds))"
        } else {
            elapsedLabel = "ELAPSED"
        }
        distance = RunFormat.distance(input.meters, unit: unit, withUnit: false)
        distanceUnit = unit.symbol
        if let meters = coach?.meters, meters > 0 {
            distanceLabel = "OF \(RunFormat.distance(meters, unit: unit).uppercased())"
        } else {
            distanceLabel = "DISTANCE"
        }

        if let steps, steps.waitsForTap {
            lower = .nextStep(Self.nextPreview(steps, unit: unit))
        } else {
            lower = .pace(
                value: RunFormat.pace(isPaused ? nil : input.currentPace, unit: unit, withUnit: false),
                unit: "min/\(unit.symbol)",
                footer: Self.footer(input, coach: coach)
            )
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

    /// Under the pace: what's left of a timed or distance step, the coach's pace range, or the height
    /// against the start.
    private static func footer(_ input: Input, coach: CoachWorkoutTarget?) -> Line? {
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
        }
        if let pace = coach?.pace {
            let fast = RunFormat.pace(pace.lowerBound, unit: input.unit, withUnit: false)
            let slow = RunFormat.pace(pace.upperBound, unit: input.unit, withUnit: false)
            return Line(caption: "TARGET", value: fast == slow ? fast : "\(fast)–\(slow)", detail: "/\(input.unit.symbol)")
        }
        guard let height = input.heightFromStart else { return nil }
        let amount = RunFormat.elevation(abs(height), unit: input.unit)
        if amount.hasPrefix("0 ") {
            return Line(symbol: "arrow.left.and.right", value: "Level", detail: "with start")
        }
        return height > 0
            ? Line(symbol: "arrow.up", value: amount, detail: "above start")
            : Line(symbol: "arrow.down", value: amount, detail: "below start")
    }
}
