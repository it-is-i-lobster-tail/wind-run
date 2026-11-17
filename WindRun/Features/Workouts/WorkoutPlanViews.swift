//
//  WorkoutPlanViews.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// What the builder sheet is working on: a new workout, or one of the runner's saved ones to change.
enum WorkoutEditing: Identifiable {
    case new
    case saved(IntervalPlan)

    var id: String {
        switch self {
        case .new: "new"
        case .saved(let plan): "\(plan.persistentModelID.hashValue)"
        }
    }

    var plan: IntervalPlan? {
        if case .saved(let plan) = self { plan } else { nil }
    }
}

extension [IntervalPlan] {
    /// The runner's own workouts, the last one run first. Each one's date is worked out once, not on
    /// every comparison, since it looks through all of its runs.
    var savedWorkouts: [IntervalPlan] {
        filter(\.isSavedWorkout)
            .map { (plan: $0, lastUsed: $0.lastUsed) }
            .sorted { $0.lastUsed > $1.lastUsed }
            .map(\.plan)
    }
}

extension View {
    /// Keeps the watch's list of workouts the same as the runner's own on the Workout page, so each one starts from the wrist.
    func sendsSavedWorkoutsToWatch() -> some View {
        modifier(SavedWorkoutsToWatch())
    }
}

private struct SavedWorkoutsToWatch: ViewModifier {
    @Query(filter: IntervalPlan.onIntervalsPage) private var plans: [IntervalPlan]

    private var workouts: [WatchSavedWorkout] {
        plans.savedWorkouts.map { WatchSavedWorkout($0) }
    }

    func body(content: Content) -> some View {
        content.task(id: workouts) { SettingsSync.shared.sendSavedWorkouts(workouts) }
    }
}

/// A workout in a line, for its row on the Workout page.
enum WorkoutSummary {
    /// "10 min warm-up · 4 × 5 min · 10 min cooldown", "45 min run", "Warm-up until Next · 5 km run".
    static func line(_ draft: WorkoutDraft, unit: DistanceUnit) -> String {
        var parts: [String] = []
        if let warmup = draft.warmup {
            parts.append(end(warmup, name: "warm-up", unit: unit))
        }
        switch draft.main {
        case .time(let seconds): parts.append("\(WorkoutDistance.text(of: .time(seconds), unit: unit)) run")
        case .distance(let meters): parts.append("\(WorkoutDistance.text(meters, preferred: unit)) run")
        case .free: parts.append("Free run")
        case .intervals(let intervals):
            if case .open = intervals.work {
                parts.append("\(intervals.repeats) repeats")
            } else {
                parts.append("\(intervals.repeats) × \(WorkoutDistance.text(of: intervals.work, unit: unit))")
            }
        }
        if let pace = draft.targetPace, let last = parts.popLast() {
            // On the main part, which is last so far: "5 km run @ 5:00–5:15 /km".
            parts.append("\(last) @ \(CoachFormat.paceRange(pace, unit: unit))")
        }
        if let cooldown = draft.cooldown {
            parts.append(end(cooldown, name: "cooldown", unit: unit))
        }
        return parts.joined(separator: " · ")
    }

    private static func end(_ goal: IntervalGoal, name: String, unit: DistanceUnit) -> String {
        if case .open = goal { return "\(name.prefix(1).uppercased())\(name.dropFirst()) until Next" }
        return "\(WorkoutDistance.text(of: goal, unit: unit)) \(name)"
    }
}

/// Short descriptions of a coach session's steps for cards.
enum IntervalSummary {
    /// "3 min work", "400 m recover", "walk until Next".
    static func step(_ choice: IntervalStepChoice, goal: IntervalGoal, unit: DistanceUnit) -> String {
        let name = choice.name.lowercased()
        if case .open = goal { return "\(name) until Next" }
        return "\(RunFormat.goal(goal, unit: unit)) \(name)"
    }
}

/// The workout as one bar, each step as wide as its share of the time. Drawn in one pass from where each
/// step starts and ends, so even 50 repeats fit the width.
struct IntervalTimelineBar: View {
    let timeline: [PlannedIntervalStep]

    private static func weight(of step: PlannedIntervalStep) -> Double {
        if case .time(let seconds) = step.goal { return seconds }
        // Distance and open steps get a nominal width so they still show.
        return 120
    }

    var body: some View {
        // Worked out before drawing, which happens off the main actor.
        let steps = timeline.map { (weight: Self.weight(of: $0), tint: IntervalStepChoice(kind: $0.kind, isWalk: $0.isWalk).tint) }
        Canvas { context, size in
            let total = max(steps.reduce(0) { $0 + $1.weight }, 1)
            // A gap between steps while each has room for one; with many steps they touch instead.
            let gap: CGFloat = size.width / CGFloat(max(steps.count, 1)) >= 8 ? 2 : 0
            let usable = max(0, size.width - gap * CGFloat(max(steps.count - 1, 0)))
            var before = 0.0
            for (index, step) in steps.enumerated() {
                let start = usable * before / total + gap * CGFloat(index)
                before += step.weight
                let end = usable * before / total + gap * CGFloat(index)
                let rect = CGRect(x: start, y: 0, width: max(1, end - start), height: size.height)
                context.fill(Path(roundedRect: rect, cornerRadius: min(3, rect.width / 2)), with: .color(step.tint))
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

extension IntervalStepChoice {
    var tint: Color {
        switch self {
        case .warmup, .cooldown: .secondary.opacity(VisualOpacity.standard)
        case .work: .accentColor
        case .recovery: .accentColor.opacity(VisualOpacity.light)
        case .walk: .secondary.opacity(VisualOpacity.light)
        }
    }
}
