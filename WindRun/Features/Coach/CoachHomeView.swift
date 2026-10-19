//
//  CoachHomeView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// Placeholder for the coach. Lays out the three goals it will plan for.
struct CoachHomeView: View {
    @Query private var plans: [CoachPlan]

    private var activePlan: CoachPlan? { plans.active }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                    Text("Pick a goal and the coach plans your weeks. You run.")
                        .foregroundStyle(.secondary)

                    if let activePlan {
                        Text("Current plan: \(activePlan.goal.name)")
                            .font(.headline)
                    }

                    ForEach(CoachGoal.allCases, id: \.self) { goal in
                        CoachGoalCard(goal: goal)
                    }

                    ComingSoonLabel()
                }
                .padding()
            }
            .navigationTitle("Coach")
        }
    }
}

private struct CoachGoalCard: View {
    let goal: CoachGoal

    var body: some View {
        HStack(alignment: .top, spacing: LayoutMetrics.sectionSpacing * 0.75) {
            Image(systemName: goal.systemImage)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(goal.name)
                    .font(.headline)
                Text(goal.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
        .accessibilityElement(children: .combine)
    }
}

#Preview("Coach") {
    CoachHomeView()
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
}
