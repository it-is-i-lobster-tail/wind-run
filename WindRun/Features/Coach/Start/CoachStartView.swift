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
    var startWith: Binding<Bool> = .constant(false)
    /// A plan that just reached its event, to mark the end of it.
    var finished: CoachPlan?

    @State private var settingUp = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                if let finished {
                    FinishedPlanCard(plan: finished) {
                        Trace.tap("Coach start", "Plan your next event")
                        settingUp = true
                    }
                }

                Text("Tell the coach your weekly mileage now, your event and its date. It builds your weeks up to it, never adding more than 10% a week. You run.")
                    .foregroundStyle(.secondary)

                Button {
                    Trace.tap("Coach start", "Set up a plan")
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
            guard startWith.wrappedValue else { return }
            startWith.wrappedValue = false
            try? await Task.sleep(for: .milliseconds(300))
            settingUp = true
        }
        .traceScreen("Coach start")
        .sheet(isPresented: $settingUp) {
            BuildSetupView(saved: BuildAnswerStore(context: modelContext).load(), unit: unit) { settings, answers in
                Trace.log(.coach, "Plan set up")
                BuildAnswerStore(context: modelContext).save(answers)
                BuildService(context: modelContext).start(settings)
            }
        }
    }
}

/// The end of a plan: the event, the weeks it took and the biggest one, and the way into the next.
private struct FinishedPlanCard: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    let plan: CoachPlan
    let planNext: () -> Void

    var body: some View {
        let state = BuildService(context: modelContext).state(of: plan)
        VStack(alignment: .leading, spacing: 10) {
            Label(title(state), systemImage: "flag.checkered")
                .font(.headline)
            if let state {
                Text(summary(state))
                    .foregroundStyle(.secondary)
            }
            Button("Plan your next event", action: planNext)
                .prominentAccentButton()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
        .onAppear { Trace.log(.coach, "Finished plan shown", ["weeks": state?.weeks.count ?? 0]) }
    }

    private func title(_ state: BuildPlanState?) -> String {
        guard let state else { return "Your plan is done" }
        let event = state.settings.goal.event
        let name = event == .custom ? "your event" : "your \(event.shortName)"
        let ran = state.weeks.flatMap(\.sessions).contains { $0.kind == .event && $0.status.runID != nil }
        return ran ? "You ran \(name)" : "\(name.capitalizedFirst) plan is done"
    }

    /// "Well done. 16 weeks of training, the biggest at 31.6 km."
    private func summary(_ state: BuildPlanState) -> String {
        let weeks = state.weeks.count
        let biggest = state.weeks.map(\.done.meters).max() ?? 0
        let training = "\(weeks) \(weeks == 1 ? "week" : "weeks") of training"
        return biggest > 0 ? "Well done. \(training), the biggest at \(unit.weekly(biggest))." : "Well done. \(training)."
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

#Preview("Coach start") {
    NavigationStack {
        CoachStartView()
    }
}
