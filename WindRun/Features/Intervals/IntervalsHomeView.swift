//
//  IntervalsHomeView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// The runner's own interval workouts, each one tap from running. They run on the same steps the coach
/// uses, so they look and sound the same mid-run.
struct IntervalsHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage(HeartRateMonitor.storageKey) private var measuresHeartRate = false
    @Query private var allPlans: [IntervalPlan]
    @Query private var coachPlans: [CoachPlan]

    @State private var recorder: RunRecorder?
    @State private var finishedRun: Run?
    @State private var coach = CoachRouter()
    /// The workout open in the builder: a new one, or a saved one to change.
    @State private var editing: IntervalEditing?
    /// The workout open on its own page, if any.
    @State private var path: [IntervalPlan] = []

    /// Saved workouts, the last one run first, so the usual workout is at the top.
    private var plans: [IntervalPlan] { allPlans.savedWorkouts }

    private var coachPlan: CoachPlan? {
        guard TermsAcceptance.isCurrent() else { return nil }
        return coachPlans.active
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                    if plans.isEmpty {
                        emptyState
                    } else {
                        ForEach(plans) { plan in
                            IntervalWorkoutCard(plan: plan, unit: unit) { start(plan) }
                        }
                    }
                }
                .padding()
            }
            .clearsFloatingBar()
            .navigationTitle("Intervals")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New workout", systemImage: "plus") { editing = .new }
                }
            }
            .navigationDestination(for: IntervalPlan.self) { plan in
                IntervalWorkoutView(plan: plan, unit: unit, start: { start(plan) }, edit: { editing = .saved(plan) })
            }
        }
        .sheet(item: $editing) { editing in
            // A saved workout opens on its own page, Start first. A changed workout a run already used is
            // saved as a new one, so its page is swapped for the new one's.
            IntervalEditorView(editing: editing) { saved in path = [saved] }
        }
        .fullScreenCover(isPresented: isRecording, onDismiss: checkIn) {
            if let recorder {
                ActiveRunView(recorder: recorder)
            }
        }
        .coachSheets(coach, plan: coachPlan)
        // Back on this page, nothing shows a deleted workout any more, so it can go.
        .onAppear { IntervalPlan.deleteRemoved(in: modelContext) }
    }

    private var emptyState: some View {
        VStack(spacing: LayoutMetrics.sectionSpacing) {
            EmptyStateView(
                title: "No workouts yet",
                systemImage: "repeat",
                description: "Build a workout once, then start it in one tap. Warm up, repeat fast and easy steps, cool down, or run until you tap Next."
            )
            Button("New workout", systemImage: "plus") { editing = .new }
                .prominentAccentButton()
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, LayoutMetrics.sectionSpacing * 2)
    }

    private var isRecording: Binding<Bool> {
        Binding(
            get: { recorder?.run != nil },
            set: { isPresented in
                // Dismissing can set this more than once, so keep the run from the first time.
                if !isPresented {
                    if let run = recorder?.run { finishedRun = run }
                    recorder = nil
                }
            }
        )
    }

    private func start(_ plan: IntervalPlan) {
        let recorder = RunRecorder(modelContext: modelContext)
        recorder.start(kind: .intervals, intervalPlan: plan, measuresHeartRate: measuresHeartRate)
        self.recorder = recorder
    }

    /// With a coach plan, a finished run goes to the coach, which asks how it went, as on the Run page.
    private func checkIn() {
        defer { finishedRun = nil }
        guard let coachPlan, let run = finishedRun, run.status == .complete else { return }
        if coachPlan.isBuild {
            BuildRunStart.runFinished(in: modelContext)
            return
        }
        coach.open(.runCheckIn(runID: run.runID))
    }
}

/// What the builder sheet is working on.
enum IntervalEditing: Identifiable {
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

extension IntervalPlan {
    /// When the workout was last run, or made when it hasn't been.
    var lastUsed: Date {
        runs.filter { $0.status == .complete }.map(\.startDate).max() ?? createdDateValue
    }
}

extension [IntervalPlan] {
    /// The Intervals page's workouts, the last one run first.
    var savedWorkouts: [IntervalPlan] {
        filter(\.isSavedWorkout).sorted { $0.lastUsed > $1.lastUsed }
    }
}

extension View {
    /// Keeps the watch's list of workouts the same as the Intervals page's, so each one starts from the wrist.
    func sendsSavedWorkoutsToWatch() -> some View {
        modifier(SavedWorkoutsToWatch())
    }
}

private struct SavedWorkoutsToWatch: ViewModifier {
    @Query private var plans: [IntervalPlan]

    private var workouts: [WatchSavedWorkout] {
        plans.savedWorkouts.map { WatchSavedWorkout($0) }
    }

    func body(content: Content) -> some View {
        content.task(id: workouts) { SettingsSync.shared.sendSavedWorkouts(workouts) }
    }
}

/// A saved workout with its Start button up front. The rest of the card opens the workout.
struct IntervalWorkoutCard: View {
    let plan: IntervalPlan
    let unit: DistanceUnit
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            AdaptiveRow {
                NavigationLink(value: plan) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plan.name)
                            .font(.title3.weight(.semibold))
                        Text(RunFormat.intervalLength(plan.timeline, unit: unit))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the steps")

                Button("Start", systemImage: "play.fill", action: start)
                    .prominentAccentButton()
                    .controlSize(.large)
                    .accessibilityLabel("Start \(plan.name)")
            }

            NavigationLink(value: plan) {
                VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
                    IntervalTimelineBar(timeline: plan.timeline)
                    Text(IntervalSummary.blocks(plan.blocks, unit: unit))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
    }
}

/// Short descriptions of a workout for cards and rows.
enum IntervalSummary {
    /// "10 min warm up · 5 × (3 min work, 2 min recover) · open cool down".
    static func blocks(_ blocks: [IntervalBlock], unit: DistanceUnit) -> String {
        blocks.map { block in
            let steps = block.steps.map { step(IntervalStepChoice(kind: $0.kind, isWalk: $0.isWalk), goal: $0.goal, unit: unit) }
            let joined = steps.joined(separator: ", ")
            return block.repeatCount > 1 ? "\(block.repeatCount) × (\(joined))" : joined
        }
        .joined(separator: " · ")
    }

    /// "3 min work", "400 m recover", "open walk".
    static func step(_ choice: IntervalStepChoice, goal: IntervalGoal, unit: DistanceUnit) -> String {
        let name = choice.name.lowercased()
        if case .open = goal { return "open \(name)" }
        return "\(RunFormat.goal(goal, unit: unit)) \(name)"
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
                        .fill(IntervalStepChoice(kind: step.kind, isWalk: step.isWalk).tint)
                        .frame(width: max(2, (proxy.size.width - CGFloat(timeline.count - 1) * 2) * weight(of: step) / max(total, 1)))
                }
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

#Preview("Intervals - Saved") {
    let container = WindRunSchema.makeContainer(inMemory: true)
    let plan = IntervalPlan.classicFiveByThree()
    plan.isCustomValue = true
    container.mainContext.insert(plan)
    return IntervalsHomeView()
        .modelContainer(container)
        .environment(CoachInbox())
}

#Preview("Intervals - Empty") {
    IntervalsHomeView()
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
        .environment(CoachInbox())
}
