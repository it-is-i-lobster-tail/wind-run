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
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    private var workouts: [WatchSavedWorkout] {
        plans.savedWorkouts.map { WatchSavedWorkout($0, preferred: unit) }
    }

    func body(content: Content) -> some View {
        content.task(id: workouts) { SettingsSync.shared.sendSavedWorkouts(workouts) }
    }
}

/// A workout part by part, for its row on the Workout page.
enum WorkoutSummary {
    /// One line of a workout's row: "Warm-up" and "10 min".
    struct Part: Equatable, Hashable {
        let label: String
        let value: String
    }

    /// The warm-up, main part and cooldown, leaving out a warm-up or cooldown the workout doesn't have:
    /// "10 min" or "Until Next" for the ends, and "20 min run", "5 km run", "Free run" or "Intervals" for the
    /// main part, with its target pace after it: "Free run @ 9:30–11:30 min/mi".
    static func parts(_ draft: WorkoutDraft) -> [Part] {
        let unit = draft.unit
        var parts: [Part] = []
        if let warmup = draft.warmup {
            parts.append(Part(label: "Warm-up", value: WorkoutDistance.text(of: warmup, unit: unit)))
        }
        var main: String
        switch draft.main {
        case .time(let seconds): main = "\(WorkoutDistance.text(of: .time(seconds), unit: unit)) \(draft.sport.noun)"
        case .distance(let meters): main = "\(WorkoutDistance.text(meters, in: unit)) \(draft.sport.noun)"
        case .free: main = WorkoutType.free.name(for: draft.sport)
        case .intervals: main = "Intervals"
        }
        if draft.sport != .cycling, let pace = draft.targetPace {
            main += " @ \(WorkoutDistance.paceText(pace, unit: unit))"
        }
        parts.append(Part(label: "Main", value: main))
        if let cooldown = draft.cooldown {
            parts.append(Part(label: "Cooldown", value: WorkoutDistance.text(of: cooldown, unit: unit)))
        }
        return parts
    }

    /// The parts read as one, for VoiceOver: "Warm-up, 10 min. Main, 20 min run. Cooldown, 5 min."
    static func spoken(_ parts: [Part]) -> String {
        parts.map { "\($0.label), \($0.value)." }.joined(separator: " ")
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
