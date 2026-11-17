//
//  IntervalsListView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// The runner's own interval workouts, under Workout. Picking one opens its "When you're ready" page;
/// a new one, edit and delete are here too. They run on the same steps the coach uses, so they look and
/// sound the same mid-run.
struct IntervalsListView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @Query private var allPlans: [IntervalPlan]

    /// "Intervals", or the runner's own workout of the intervals type.
    let title: String
    /// Opens a workout's "When you're ready" page, for one just built. The list's rows open theirs as
    /// `WorkoutRoute.ready`.
    let open: (IntervalPlan) -> Void

    /// The workout open in the builder: a new one, or a saved one to change.
    @State private var editing: IntervalEditing?
    @State private var deleting: IntervalPlan?

    /// Saved workouts, the last one run first, so the usual workout is at the top.
    private var plans: [IntervalPlan] { allPlans.savedWorkouts }

    var body: some View {
        List {
            if plans.isEmpty {
                emptyState
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(plans) { plan in
                        NavigationLink(value: WorkoutRoute.ready(.intervals(plan))) {
                            IntervalWorkoutRow(plan: plan, unit: unit)
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Trace.tap("Intervals", "Swipe: Delete")
                                deleting = plan
                            }
                            Button("Edit", systemImage: "pencil") {
                                Trace.tap("Intervals", "Swipe: Edit")
                                editing = .saved(plan)
                            }
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { editing = .saved(plan) }
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = plan }
                        }
                    }
                } header: {
                    // Above the list, so it stays in sight however many there are.
                    Text("Swipe an interval-plan to edit or delete it.")
                        .textCase(nil)
                }
            }
        }
        .clearsFloatingBar()
        .navigationTitle(title)
        .traceScreen("Intervals")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Interval", systemImage: "plus") {
                    Trace.tap("Intervals", "New Interval (toolbar)")
                    editing = .new
                }
            }
        }
        .sheet(item: $editing) { editing in
            // A new workout opens on its own page, Start first.
            IntervalEditorView(editing: editing) { saved in
                if case .new = editing { open(saved) }
            }
        }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "interval")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { plan in
            Button("Delete Interval", role: .destructive) {
                Trace.tap("Intervals", "Delete interval?: Delete Interval")
                plan.remove()
                modelContext.saveQuietly()
                IntervalPlan.deleteRemoved(in: modelContext)
            }
        } message: { _ in
            Text("Runs you've done with it keep their steps.")
        }
        // Back on this page, nothing shows a deleted workout any more, so it can go.
        .onAppear { IntervalPlan.deleteRemoved(in: modelContext) }
    }

    private var emptyState: some View {
        VStack(spacing: LayoutMetrics.sectionSpacing) {
            EmptyStateView(
                title: "No interval workouts yet",
                systemImage: "repeat",
                description: "Build a workout once, then start it from here. Warm up, repeat fast and easy steps, cool down, or run until you tap Next."
            )
            Button("New Interval", systemImage: "plus") {
                Trace.tap("Intervals", "New Interval")
                editing = .new
            }
            .prominentAccentButton()
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, LayoutMetrics.sectionSpacing * 2)
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

/// A saved interval workout in the list: its name and length, the steps as a bar, and each block written out.
struct IntervalWorkoutRow: View {
    let plan: IntervalPlan
    let unit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                    .font(.headline)
                Text(RunFormat.intervalLength(plan.timeline, unit: unit))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            IntervalTimelineBar(timeline: plan.timeline)
            Text(IntervalSummary.blocks(plan.blocks, unit: unit))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the workout, ready to start")
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
    return NavigationStack {
        IntervalsListView(title: "Intervals") { _ in }
    }
    .modelContainer(container)
}

#Preview("Intervals - Empty") {
    NavigationStack {
        IntervalsListView(title: "Intervals") { _ in }
    }
    .modelContainer(WindRunSchema.makeContainer(inMemory: true))
}
