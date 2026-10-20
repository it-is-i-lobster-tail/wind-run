//
//  CoachFormat+Workout.swift
//  Wind Run
//

import Foundation

/// How a planned session's target reads on screen.
extension CoachFormat {
    /// "45 min · 6:30–7:00 /km · effort 2–3", leaving out whatever the session doesn't set.
    static func targetSummary(_ target: CoachWorkoutTarget, unit: DistanceUnit) -> String {
        var parts: [String] = []
        if let meters = target.meters, meters > 0 {
            parts.append(RunFormat.distance(meters, unit: unit))
        } else if let seconds = target.seconds, seconds > 0 {
            parts.append(minutes(seconds))
        }
        if let pace = target.pace {
            parts.append(paceRange(pace, unit: unit))
        }
        if let effort = target.effort {
            parts.append(effort.lowerBound == effort.upperBound ? "effort \(effort.lowerBound)" : "effort \(effort.lowerBound)–\(effort.upperBound)")
        }
        if let runWalk = target.runWalk {
            parts.append(runWalk)
        }
        return parts.joined(separator: " · ")
    }

    /// "6:30–7:00 /km", fastest first.
    static func paceRange(_ range: ClosedRange<TimeInterval>, unit: DistanceUnit) -> String {
        let fast = RunFormat.pace(range.lowerBound, unit: unit, withUnit: false)
        let slow = RunFormat.pace(range.upperBound, unit: unit, withUnit: false)
        return fast == slow ? "\(fast) /\(unit.symbol)" : "\(fast)–\(slow) /\(unit.symbol)"
    }
}
