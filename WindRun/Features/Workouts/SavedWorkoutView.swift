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
    /// A changed workout a run already used is saved as a new one, which takes this page's place.
    var replaced: (IntervalPlan) -> Void = { _ in }

    @State private var editing: WorkoutEditing?
    @State private var isConfirmingDelete = false

    var body: some View {
        WorkoutReadyPage(title: plan.name, start: start) {
            WorkoutPartsCard(draft: WorkoutDraft(plan), timeline: plan.timeline, unit: unit)

            if let note = Self.openStepNote(plan.timeline) {
                Label(note, systemImage: "hand.tap")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .traceScreen("Saved workout")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    Trace.tap("Saved workout", "Edit")
                    editing = .saved(plan)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Delete Workout", systemImage: "trash", role: .destructive) {
                    Trace.tap("Saved workout", "Delete workout")
                    isConfirmingDelete = true
                }
            }
        }
        .sheet(item: $editing) { editing in
            WorkoutBuilderView(editing: editing) { saved in
                if saved != plan { replaced(saved) }
            }
        }
        .confirmationDialog("Delete \(plan.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) {
                Trace.tap("Saved workout", "Delete workout?: Delete Workout")
                plan.remove()
                modelContext.saveQuietly()
                dismiss()
            }
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
    let unit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing * 1.5) {
            HStack(alignment: .firstTextBaseline) {
                Text(draft.main.type == .intervals ? "Intervals" : draft.main.type.name)
                    .font(.headline)
                Spacer()
                Text(RunFormat.intervalLength(timeline, unit: unit))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            IntervalTimelineBar(timeline: timeline)

            if let warmup = draft.warmup {
                line("Warm-up", WorkoutBuilderView.endDetail(warmup, unit: unit))
            }
            switch draft.main {
            case .time(let seconds):
                line("Run", WorkoutDistance.text(of: .time(seconds), unit: unit), isMain: true)
            case .distance(let meters):
                line("Run", WorkoutDistance.text(meters, preferred: unit), isMain: true)
            case .free:
                line("Run", "Until you tap Next", isMain: true)
            case .intervals(let intervals):
                VStack(alignment: .leading, spacing: 6) {
                    Text(intervals.repeats == 1 ? "Once" : "\(intervals.repeats) times")
                        .font(.body.weight(.semibold).monospacedDigit())
                    HStack(spacing: 12) {
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: 3)
                        VStack(spacing: 6) {
                            line("Work", WorkoutBuilderView.endDetail(intervals.work, unit: unit))
                            line("Recovery", WorkoutBuilderView.endDetail(intervals.recovery, unit: unit))
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            if let cooldown = draft.cooldown {
                line("Cooldown", WorkoutBuilderView.endDetail(cooldown, unit: unit))
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
                .monospacedDigit()
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
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.name)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(RunFormat.intervalLength(plan.timeline, unit: unit))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            IntervalTimelineBar(timeline: plan.timeline)

            ForEach(plan.blocks) { block in
                HStack(alignment: .firstTextBaseline) {
                    if block.repeatCount > 1 {
                        Text("\(block.repeatCount) ×")
                            .font(.body.weight(.semibold).monospacedDigit())
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
