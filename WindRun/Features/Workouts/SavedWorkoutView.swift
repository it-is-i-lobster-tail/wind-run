//
//  SavedWorkoutView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// One of the runner's own workouts, ready to go: "When you're ready…", Start, then its warm-up, main part and
/// cooldown to check. Changing or deleting the workout is in the toolbar.
struct SavedWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let plan: IntervalPlan
    let unit: DistanceUnit
    let start: () -> Void
    var edit: () -> Void = {}

    @State private var isConfirmingDelete = false

    var body: some View {
        let timeline = plan.timeline
        WorkoutReadyPage(title: plan.name, sport: plan.sport, start: start) {
            if let route = plan.waypointRoute {
                Label("Start at your current location", systemImage: "location.fill")
                WaypointMap(workout: route, start: nil).frame(height: 210)
                ForEach(route.points) { point in
                    LabeledContent(point.effort.name, value: point.name)
                }
                if route.returnsToStart { LabeledContent(route.returnEffort.name, value: "Back to your start") }
            } else {
            WorkoutPartsCard(draft: WorkoutDraft(plan, preferred: unit), timeline: timeline)

            if let note = Self.openStepNote(timeline) {
                Label(note, systemImage: "hand.tap")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            }
        }
        .traceScreen("Saved workout")
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    WorkoutGlyph(value: plan.workoutSymbol)
                    Text(plan.name).font(.headline)
                }
                .accessibilityAddTraits(.isHeader)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    Trace.tap("Saved workout", "Edit")
                    edit()
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Delete Workout", systemImage: "trash", role: .destructive) {
                    Trace.tap("Saved workout", "Delete workout")
                    isConfirmingDelete = true
                }
            }
        }
        .alert("Delete “\(plan.name)”?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) {
                Trace.tap("Saved workout", "Delete workout?: Delete Workout")
                plan.remove()
                modelContext.saveQuietly()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Runs you've done with it keep their steps.")
        }
    }

    /// How the workout's parts that wait for Next end, or nil without any. A last part like that has nothing
    /// after it to tap on to, so it runs until the runner finishes (see `StepTracker.runsUntilFinish`).
    /// There's no Next on this page, so it says where Next is.
    static func openStepNote(_ timeline: [PlannedIntervalStep]) -> String? {
        let lastIsOpen = timeline.last.map { $0.goal == .open && !$0.isWalk } ?? false
        let tapped = (lastIsOpen ? timeline.dropLast() : timeline[...]).contains { $0.goal == .open }
        let ends = "A part until Next ends when you tap Next on the run screen, your Lock Screen or your Apple Watch."
        return switch (tapped, lastIsOpen) {
        case (true, true): "\(ends) The last one runs until you finish."
        case (true, false): ends
        case (false, true): "The last part runs until you finish."
        case (false, false): nil
        }
    }
}

/// A workout's three parts, as the builder shows them, under its length and the steps as a bar.
struct WorkoutPartsCard: View {
    let draft: WorkoutDraft
    let timeline: [PlannedIntervalStep]
    /// The workout's own unit.
    private var unit: DistanceUnit { draft.unit }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing * 1.5) {
            HStack(alignment: .firstTextBaseline) {
                Text(draft.main.type.name(for: draft.sport))
                    .font(.headline)
                Spacer()
                Text(WorkoutDistance.length(timeline, in: unit))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            IntervalTimelineBar(timeline: timeline)

            if let warmup = draft.warmup {
                line("Warm-up", WorkoutDistance.endDetail(warmup, unit: unit))
            }
            if let goal = draft.main.singleGoal {
                line(draft.sport.noun.capitalized, WorkoutDistance.endDetail(goal, unit: unit), isMain: true)
            } else if case .waypointIntervals(let pairs) = draft.main {
                ForEach(Array(pairs.enumerated()), id: \.offset) { index, pair in
                    if let work = pair.work { line("Work - \(index + 1)", work.name) }
                    if let recovery = pair.recovery { line("Recovery - \(index + 1)", recovery.name) }
                }
            } else if case .intervals(let intervals) = draft.main {
                VStack(alignment: .leading, spacing: 6) {
                    Text(intervals.repeats == 1 ? "Once" : "\(intervals.repeats) times")
                        .font(.body.weight(.semibold))
                    HStack(spacing: 12) {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: 3)
                        VStack(spacing: 6) {
                            line("Work", WorkoutDistance.endDetail(intervals.work, unit: unit))
                            line("Recovery", WorkoutDistance.endDetail(intervals.recovery, unit: unit))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            if let pace = draft.targetPace {
                line("Target pace", WorkoutDistance.paceText(pace, unit: unit))
            }
            if let cooldown = draft.cooldown {
                line("Cooldown", WorkoutDistance.endDetail(cooldown, unit: unit))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
    }

    private func line(_ name: String, _ detail: String, isMain: Bool = false) -> some View {
        HStack {
            Text(name)
                .fontWeight(isMain ? .semibold : .regular)
            Spacer()
            Text(detail)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A workout's steps: its length, the steps as a bar, and each block written out. The coach's sessions
/// show their steps the same way.
struct IntervalPlanCard: View {
    let plan: IntervalPlan
    let unit: DistanceUnit

    var body: some View {
        let timeline = plan.timeline
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.name)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(RunFormat.intervalLength(timeline, unit: unit))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            IntervalTimelineBar(timeline: timeline)

            ForEach(plan.blocks) { block in
                HStack(alignment: .firstTextBaseline) {
                    if block.repeatCount > 1 {
                        Text("\(block.repeatCount) ×")
                            .font(.body.weight(.semibold))
                    }
                    Text(block.steps.map { IntervalSummary.step(IntervalStepChoice(kind: $0.kind, isWalk: $0.isWalk), goal: $0.goal, unit: unit) }
                        .joined(separator: ", "))
                }
                .font(.body)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
    }
}

#Preview("Workout") {
    let container = WindRunSchema.makeContainer(inMemory: true)
    let plan = IntervalPlan.classicFiveByThree()
    plan.isCustomValue = true
    container.mainContext.insert(plan)
    return NavigationStack {
        SavedWorkoutView(plan: plan, unit: .kilometers, start: {})
    }
    .modelContainer(container)
}
