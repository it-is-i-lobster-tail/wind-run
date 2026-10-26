//
//  IntervalWorkoutView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// One saved workout. Its job is to get the runner going: Start comes first and fills the top of the
/// screen, and the steps sit under it to check. Changing the workout is in the toolbar.
struct IntervalWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let plan: IntervalPlan
    let unit: DistanceUnit
    let start: () -> Void
    let edit: () -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.sectionSpacing * 1.5) {
                StartBubble(title: "Start", systemImage: "figure.run", size: StartBubble.soloSize, isProminent: true, action: start)
                    .padding(.top, LayoutMetrics.sectionSpacing)

                IntervalPlanCard(plan: plan, unit: unit)

                if plan.timeline.contains(where: { $0.goal == .open }) {
                    Label("Open steps run until you tap Next here, on your Lock Screen or on your Apple Watch.", systemImage: "hand.tap")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
        }
        .clearsFloatingBar()
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", action: edit)
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Delete workout", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
            }
        }
        .confirmationDialog("Delete \(plan.name)?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete workout", role: .destructive) {
                plan.remove()
                modelContext.saveQuietly()
                dismiss()
            }
        } message: {
            Text("Runs you've done with it keep their steps.")
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
                Text(IntervalSummary.length(plan.timeline))
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
        IntervalWorkoutView(plan: plan, unit: .kilometers, start: {}, edit: {})
    }
    .modelContainer(container)
}
