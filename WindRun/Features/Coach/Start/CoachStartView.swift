//
//  CoachStartView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// No plan yet: what the coach does, and the way in.
struct CoachStartView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    /// Opens the setup straight away when set, such as after an old plan was stopped.
    var startWith: Binding<CoachGoal?> = .constant(nil)

    @State private var settingUp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                Text("Tell the coach your weekly mileage now, your event and its date. It builds your weeks up to it, never adding more than 10% a week. You run.")
                    .foregroundStyle(.secondary)

                Button {
                    settingUp = true
                } label: {
                    BuildStartCard()
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        // A sheet can't present until the screen is in place, so this waits a moment after it appears.
        .task {
            guard startWith.wrappedValue != nil else { return }
            startWith.wrappedValue = nil
            try? await Task.sleep(for: .milliseconds(300))
            settingUp = true
        }
        .sheet(isPresented: $settingUp) {
            BuildSetupView(saved: BuildAnswerStore(context: modelContext).load(), unit: unit) { settings, answers in
                BuildAnswerStore(context: modelContext).save(answers)
                BuildService(context: modelContext).start(settings)
            }
        }
    }
}

/// The way into setup.
private struct BuildStartCard: View {
    var body: some View {
        HStack(alignment: .top, spacing: LayoutMetrics.sectionSpacing * 0.75) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text("Build distance")
                    .font(.headline)
                Text("From a 5K to an ultra: weekly mileage and climb up to a peak week, with easy weeks between.")
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
