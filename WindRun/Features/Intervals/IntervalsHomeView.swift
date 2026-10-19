//
//  IntervalsHomeView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// Placeholder for interval workouts. Shows what a plan looks like until the builder lands.
struct IntervalsHomeView: View {
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @Query(sort: \IntervalPlan.createdDateValue, order: .reverse) private var plans: [IntervalPlan]

    // Not inserted anywhere: it only shows the shape of a workout.
    @State private var example = IntervalPlan.classicFiveByThree()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                    Text("Warm up, repeat hard and easy efforts, cool down. Build your own workouts here soon.")
                        .foregroundStyle(.secondary)

                    ForEach(plans) { plan in
                        IntervalPlanCard(plan: plan, unit: unit)
                    }

                    if plans.isEmpty {
                        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
                            Text("Example")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            IntervalPlanCard(plan: example, unit: unit)
                        }
                    }

                    ComingSoonLabel()
                }
                .padding()
            }
            .clearsFloatingBar()
            .navigationTitle("Intervals")
        }
    }
}

struct IntervalPlanCard: View {
    let plan: IntervalPlan
    let unit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(plan.name)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(RunFormat.duration(plan.timedDuration))
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
                    Text(block.steps.map { "\(RunFormat.goal($0.goal, unit: unit)) \($0.kind.name.lowercased())" }
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

/// The workout as one bar, each step as wide as its share of the time.
struct IntervalTimelineBar: View {
    let timeline: [PlannedIntervalStep]

    private func weight(of step: PlannedIntervalStep) -> Double {
        if case .time(let seconds) = step.goal { return seconds }
        // Distance and open steps get a nominal width so they still show.
        return 120
    }

    var body: some View {
        GeometryReader { proxy in
            let total = timeline.reduce(0) { $0 + weight(of: $1) }
            HStack(spacing: 2) {
                ForEach(Array(timeline.enumerated()), id: \.offset) { _, step in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(step.kind.tint)
                        .frame(width: max(2, (proxy.size.width - CGFloat(timeline.count - 1) * 2) * weight(of: step) / max(total, 1)))
                }
            }
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

extension IntervalStepKind {
    var tint: Color {
        switch self {
        case .warmup, .cooldown: .secondary.opacity(VisualOpacity.standard)
        case .work: .accentColor
        case .recovery: .accentColor.opacity(VisualOpacity.light)
        }
    }
}

struct ComingSoonLabel: View {
    var body: some View {
        Label("Coming soon", systemImage: "hammer")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
    }
}

#Preview("Intervals") {
    IntervalsHomeView()
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
}
