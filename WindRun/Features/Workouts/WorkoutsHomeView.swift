//
//  WorkoutsHomeView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// Every way to start a run, as a list: the coach's workout when a plan is running, a distance run, a timed
/// run, the saved interval workouts, a free run, then the runner's own workouts. Picking one asks what it
/// needs (how far, how long, which intervals), then "When you're ready…" with Start, then the run screen.
struct WorkoutsHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage(HeartRateMonitor.storageKey) private var measuresHeartRate = false

    @Query(sort: \Workout.createdDateValue) private var workouts: [Workout]
    @Query private var coachPlans: [CoachPlan]
    @Query private var intervalPlans: [IntervalPlan]

    @State private var path: [WorkoutRoute] = []
    @State private var recorder: RunRecorder?
    @State private var finishedRun: Run?
    @State private var editing: WorkoutEditing?
    @State private var deleting: Workout?

    /// Switches to the Coach section, for a rest day or a paused plan.
    private let showCoach: () -> Void

    init(showCoach: @escaping () -> Void = {}) {
        self.showCoach = showCoach
    }

    private var coachPlan: CoachPlan? {
        guard TermsAcceptance.isCurrent() else { return nil }
        return coachPlans.active
    }

    /// What the coach has for today, or nil without a running plan.
    private var coachToday: CoachToday? {
        guard let coachPlan, let state = BuildService(context: modelContext).state(of: coachPlan) else { return nil }
        return CoachToday.of(coachPlan, build: state, now: .now, calendar: .current)
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    if let coachToday {
                        coachRow(coachToday)
                    }
                    ForEach(WorkoutChoice.builtIn, id: \.name) { choice in
                        choiceRow(choice, detail: detail(for: choice))
                    }
                }

                Section {
                    ForEach(workouts) { workout in
                        choiceRow(WorkoutChoice(workout), detail: workout.type.name)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    Trace.tap("Workouts", "Swipe: Delete")
                                    deleting = workout
                                }
                                Button("Edit", systemImage: "pencil") {
                                    Trace.tap("Workouts", "Swipe: Edit")
                                    editing = .saved(workout)
                                }
                            }
                            .contextMenu {
                                Button("Edit", systemImage: "pencil") { editing = .saved(workout) }
                                Button("Delete", systemImage: "trash", role: .destructive) { deleting = workout }
                            }
                    }
                    Button {
                        Trace.tap("Workouts", "New workout")
                        editing = .new
                    } label: {
                        Label("New Workout", systemImage: "plus")
                    }
                } header: {
                    Text("Your workouts")
                } footer: {
                    Text(workouts.isEmpty
                        ? "Add your own, like a city run or a trail run. Each one is a distance, time, intervals or free run."
                        : "Swipe a workout to edit or delete it.")
                }
            }
            .clearsFloatingBar()
            .navigationTitle("Workout")
            .traceScreen("Workouts")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New workout", systemImage: "plus") {
                        Trace.tap("Workouts", "New workout (toolbar)")
                        editing = .new
                    }
                }
            }
            .navigationDestination(for: WorkoutRoute.self) { destination($0) }
        }
        .sheet(item: $editing) { editing in
            WorkoutEditorView(editing: editing)
        }
        .confirmationDialog(
            "Delete \(deleting?.name ?? "workout")?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { workout in
            Button("Delete workout", role: .destructive) {
                Trace.tap("Workouts", "Delete workout?: Delete workout")
                modelContext.delete(workout)
                modelContext.saveQuietly()
            }
        } message: { _ in
            Text("Runs you've done with it stay.")
        }
        .fullScreenCover(isPresented: isRecording, onDismiss: runFinished) {
            if let recorder {
                ActiveRunView(recorder: recorder)
            }
        }
        #if DEBUG
        .task { openDemoPage() }
        #endif
    }

    #if DEBUG
    /// Opens the page `-workoutsDemo` names, for screenshots.
    private func openDemoPage() {
        guard path.isEmpty, let page = WorkoutsDemo.page else { return }
        if page == "editor" {
            editing = .new
            return
        }
        var session: CoachWorkout?
        if case .workout(let today) = coachToday { session = today }
        path = WorkoutsDemo.path(for: page, plan: intervalPlans.savedWorkouts.first, coach: session)
    }
    #endif

    // MARK: - Rows

    private func choiceRow(_ choice: WorkoutChoice, detail: String?) -> some View {
        NavigationLink(value: choice.firstStep) {
            WorkoutRow(title: choice.name, detail: detail, systemImage: choice.type.systemImage)
        }
    }

    /// The coach's run for today, ready to start, or what the plan is doing instead, which opens Coach.
    @ViewBuilder
    private func coachRow(_ today: CoachToday) -> some View {
        if case .workout(let session) = today {
            NavigationLink(value: WorkoutRoute.ready(.coach(session))) {
                WorkoutRow(
                    title: "Coach's Workout",
                    detail: [session.title, CoachFormat.targetSummary(session.target, unit: unit)].filter { !$0.isEmpty }.joined(separator: " · "),
                    systemImage: "flag.checkered"
                )
            }
        } else {
            Button {
                Trace.tap("Workouts", "Coach's Workout (no run today)")
                showCoach()
            } label: {
                WorkoutRow(title: "Coach's Workout", detail: Self.coachNote(today), systemImage: "flag.checkered", isDimmed: true)
            }
            .accessibilityHint("Opens Coach")
        }
    }

    /// "Rest day", "Done today", "Plan starts soon" or "Plan paused".
    static func coachNote(_ today: CoachToday) -> String {
        switch today {
        case .workout(let session): session.title
        case .done: "Done today · Opens Coach"
        case .rest: "Rest day · Opens Coach"
        case .startsLater: "Plan starts soon · Opens Coach"
        case .paused: "Plan paused · Opens Coach"
        }
    }

    private func detail(for choice: WorkoutChoice) -> String {
        switch choice.type {
        case .distance:
            choice.lastGoal().map { "Last time \(WorkoutFormat.distance($0, unit: unit))" } ?? "Pick how far"
        case .time:
            choice.lastGoal().map { "Last time \(WorkoutFormat.time($0))" } ?? "Pick how long"
        case .intervals:
            switch intervalPlans.savedWorkouts.count {
            case 0: "Build your own"
            case 1: "1 workout"
            case let count: "\(count) workouts"
            }
        case .free:
            "Just run"
        }
    }

    // MARK: - Pages

    @ViewBuilder
    private func destination(_ route: WorkoutRoute) -> some View {
        switch route {
        case .distance(let choice):
            DistanceGoalView(choice: choice, unit: unit) { meters in
                path.append(.ready(.distance(name: choice.name, meters: meters)))
            }
        case .time(let choice):
            TimeGoalView(choice: choice) { seconds in
                path.append(.ready(.time(name: choice.name, seconds: seconds)))
            }
        case .intervals(let choice):
            IntervalsListView(title: choice.name) { plan in
                path.append(.ready(.intervals(plan)))
            }
        case .ready(.intervals(let plan)):
            IntervalWorkoutView(plan: plan, unit: unit, start: { start(.intervals(plan)) }, replaced: { newPlan in
                guard !path.isEmpty else { return }
                path[path.count - 1] = .ready(.intervals(newPlan))
            })
        case .ready(let ready):
            WorkoutReadyView(ready: ready, unit: unit) { start(ready) }
        }
    }

    // MARK: - Running

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

    private func start(_ ready: ReadyWorkout) {
        Trace.tap("Workout ready", "Start", ["kind": ready.traceKind])
        let recorder = RunRecorder(modelContext: modelContext)
        switch ready {
        case .free:
            recorder.start(measuresHeartRate: measuresHeartRate)
        case .distance(_, let meters):
            recorder.start(goal: .distance(meters: meters), measuresHeartRate: measuresHeartRate)
        case .time(_, let seconds):
            recorder.start(goal: .time(seconds: seconds), measuresHeartRate: measuresHeartRate)
        case .intervals(let plan):
            recorder.start(kind: .intervals, intervalPlan: plan, measuresHeartRate: measuresHeartRate)
        case .coach(let workout):
            BuildRunStart.attachCues(to: recorder, for: workout)
            recorder.start(coachWorkout: workout, measuresHeartRate: measuresHeartRate)
        }
        self.recorder = recorder
    }

    /// Back to the list once the run screen closes. With a coach plan, a finished run counts toward the
    /// week straight away, as on the Run page.
    private func runFinished() {
        Trace.log(.screen, "Run screen closed", ["status": finishedRun?.status.rawValue ?? "none"])
        defer { finishedRun = nil }
        path = []
        guard coachPlan != nil, let run = finishedRun, run.status == .complete else { return }
        BuildRunStart.runFinished(in: modelContext)
    }
}

/// One workout in the list: an icon, its name and a line about it.
struct WorkoutRow: View {
    let title: String
    let detail: String?
    let systemImage: String
    var isDimmed = false

    var body: some View {
        HStack(spacing: LayoutMetrics.sectionSpacing) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(isDimmed ? Color.secondary : Color.onAccent)
                .frame(width: 36, height: 36)
                .background(isDimmed ? Color.secondary.opacity(VisualOpacity.light) : Color.accentColor, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Workouts") {
    let container = WindRunSchema.makeContainer(inMemory: true)
    container.mainContext.insert(Workout(name: "City Run", type: .distance))
    container.mainContext.insert(Workout(name: "Trail Blaster", type: .time))
    return WorkoutsHomeView()
        .modelContainer(container)
}
