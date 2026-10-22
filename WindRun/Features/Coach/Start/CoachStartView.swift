//
//  CoachStartView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// No plan yet: the three ways the coach can help, and the way in.
struct CoachStartView: View {
    @Environment(CoachInbox.self) private var inbox
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    /// A goal to open the setup for straight away, such as after an old plan was stopped.
    var startWith: Binding<CoachGoal?> = .constant(nil)

    @State private var setup: SetupChoice?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                Text("Pick a goal and the coach plans your weeks. You run.")
                    .foregroundStyle(.secondary)

                ForEach(CoachGoal.allCases, id: \.self) { goal in
                    Button {
                        setup = SetupChoice(goal: goal)
                    } label: {
                        CoachGoalCard(goal: goal)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        // A sheet can't present until the screen is in place, so this waits a moment after it appears.
        .task {
            guard let goal = startWith.wrappedValue else { return }
            startWith.wrappedValue = nil
            try? await Task.sleep(for: .milliseconds(300))
            setup = SetupChoice(goal: goal)
        }
        .sheet(item: $setup) { choice in
            CoachSetupView(flavor: choice.goal, unit: unit, saved: CoachAnswerStore(context: modelContext).load()) { update in
                inbox.receive(update)
            }
        }
    }

    private struct SetupChoice: Identifiable {
        let goal: CoachGoal
        var id: String { goal.rawValue }
    }
}

struct CoachGoalCard: View {
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
            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard(interactive: true)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

#Preview("Coach start") {
    NavigationStack {
        CoachStartView()
    }
    .environment(CoachInbox())
}
