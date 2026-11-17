//
//  IntervalWorkoutView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// One saved workout, ready to go: "When you're ready…", Start, then the steps to check. Changing or deleting
/// the workout is in the toolbar.
struct IntervalWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let plan: IntervalPlan
    let unit: DistanceUnit
    let start: () -> Void
    /// A changed workout a run already used is saved as a new one, which takes this page's place.
    var replaced: (IntervalPlan) -> Void = { _ in }

    @State private var editing: IntervalEditing?
    @State private var isConfirmingDelete = false

    var body: some View {
        WorkoutReadyPage(title: plan.name, start: start) {
            IntervalPlanCard(plan: plan, unit: unit)

            if let note = Self.openStepNote(plan.timeline) {
                Label(note, systemImage: "hand.tap")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .traceScreen("Interval workout")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    Trace.tap("Interval workout", "Edit")
                    editing = .saved(plan)
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Delete Workout", systemImage: "trash", role: .destructive) {
                    Trace.tap("Interval workout", "Delete workout")
                    isConfirmingDelete = true
                }
            }
        }
        .sheet(item: $editing) { editing in
            IntervalEditorView(editing: editing) { saved in
                if saved != plan { replaced(saved) }
            }
        }
        .confirmationDialog("Delete \(plan.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Workout", role: .destructive) {
                Trace.tap("Interval workout", "Delete workout?: Delete Workout")
                plan.remove()
                modelContext.saveQuietly()
                dismiss()
            }
        } message: {
            Text("Runs you've done with it keep their steps.")
        }
    }

    /// How the workout's steps that wait for Next end, or nil without any. A last step like that has nothing
    /// after it to tap on to, so it runs until the runner finishes, unless it's a walk break (see
    /// `StepTracker.runsUntilFinish`). There's no Next on this page, so it says where Next is.
    static func openStepNote(_ timeline: [PlannedIntervalStep]) -> String? {
        let lastIsOpen = timeline.last.map { $0.goal == .open && !$0.isWalk } ?? false
        let tapped = (lastIsOpen ? timeline.dropLast() : timeline[...]).contains { $0.goal == .open }
        let ends = "A step until Next ends when you tap Next on the run screen, your Lock Screen or your Apple Watch."
        return switch (tapped, lastIsOpen) {
        case (true, true): "\(ends) The last one runs until you finish."
        case (true, false): ends
        case (false, true): "The last step runs until you finish."
        case (false, false): nil
        }
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
        IntervalWorkoutView(plan: plan, unit: .kilometers, start: {})
    }
    .modelContainer(container)
}
