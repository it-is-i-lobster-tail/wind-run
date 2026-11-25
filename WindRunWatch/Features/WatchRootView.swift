//
//  WatchRootView.swift
//  Wind Run Watch
//

import SwiftData
import SwiftUI

private enum WatchRoute: Hashable {
    case goal(RunGoal)
    case summary(Run)
    case settings
}

struct WatchRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage(HeartRateMonitor.storageKey) private var measuresHeartRate = false
    @AppStorage(WorkoutGoalMemory.distanceKey) private var lastDistance: Double?
    @AppStorage(WorkoutGoalMemory.timeKey) private var lastTime: Double?
    @AppStorage(WatchRunHistory.receiptsKey) private var runReceipts: Data?
    @Query(filter: #Predicate<Run> { $0.endDateValue != nil }, sort: \Run.startDateValue, order: .reverse)
    private var endedRuns: [Run]
    /// Today's finished runs on this watch. The coached ones drop their session off the list.
    @Query private var todaysRuns: [Run]
    /// Today's coach sessions as the iPhone last sent them.
    @AppStorage(SettingsSync.coachTodayKey) private var coachToday: Data?
    /// The iPhone's saved interval workouts, the last one run first.
    @AppStorage(SettingsSync.savedWorkoutsKey) private var savedWorkouts: Data?
    /// The two lists above, read once each time the iPhone sends them rather than on every redraw.
    @State private var sessions: [WatchCoachSession] = []
    @State private var workouts: [WatchSavedWorkout] = []

    @State private var recorder: RunRecorder?
    @State private var path: [WatchRoute] = []
    /// True at launch while a run the app was closed in waits to carry on with its workout session.
    @State private var isPickingUpRun = RunRecovery.recordingRunID() != nil
    /// True while Health asks about workouts before the first run.
    @State private var isAskingHealth = false

    init() {
        let today = Calendar.current.startOfDay(for: .now)
        // A relationship can't be compared with nil in a predicate, so the coached runs are picked out below.
        _todaysRuns = Query(filter: #Predicate<Run> { $0.startDateValue >= today && $0.endDateValue != nil })
    }

    var body: some View {
        let today = todaysSessions
        let confirmed = WatchRunHistory.receipts(from: runReceipts)
        let recentRuns = WatchRunHistory.visibleRuns(endedRuns, confirmed: confirmed)
        NavigationStack(path: $path) {
            List {
                if isPickingUpRun {
                    HStack {
                        ProgressView()
                        Text("Picking up your run…")
                            .font(.footnote)
                    }
                }

                if !today.isEmpty {
                    Section("Today's Workout") {
                        ForEach(today) { session in
                            Button { startRun(session) } label: {
                                WatchWorkoutLabel(
                                    title: session.title,
                                    detail: session.summary(unit: unit),
                                    symbol: "flag.checkered",
                                    actionSymbol: "play.fill"
                                )
                            }
                            .accessibilityHint("Starts this workout immediately")
                        }
                    }
                }

                Section {
                    Button { startRun() } label: {
                        WatchWorkoutLabel(title: WorkoutChoice.freeRun.name, symbol: WorkoutType.free.systemImage, actionSymbol: "play.fill")
                    }
                    .accessibilityHint("Starts a free run immediately")

                    Button { startRun(sport: .cycling) } label: {
                        WatchWorkoutLabel(title: WorkoutChoice.cycling.name, symbol: WorkoutChoice.cycling.systemImage, actionSymbol: "play.fill")
                    }

                    Button {
                        if let savedHike { startRun(savedHike) }
                        else { startRun(sport: .hiking) }
                    } label: {
                        WatchWorkoutLabel(title: WorkoutChoice.hike.name, symbol: WorkoutChoice.hike.systemImage, actionSymbol: "play.fill")
                    }

                    let meters = DistanceGoalOptions.startingMeters(lastMeters: lastDistance, unit: unit)
                    goalLink(.distanceRun, goal: .distance(meters: meters), detail: WorkoutFormat.distance(meters, unit: unit))

                    let seconds = TimeGoalOptions.startingSeconds(last: lastTime)
                    goalLink(.timedRun, goal: .time(seconds: seconds), detail: WorkoutFormat.time(seconds))
                }

                if !sessions.isEmpty, !WatchCoachSession.anyPlanned(sessions) {
                    Section("Coach") {
                        Text("Open Wind Run on iPhone to refresh Coach.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Saved Workouts") {
                    ForEach(workouts.filter { $0.id != savedHike?.id }) { workout in
                        Button { startRun(workout) } label: {
                            WatchWorkoutLabel(
                                title: workout.name,
                                detail: workout.summary(defaultUnit: unit),
                                symbol: workout.sport == .running ? "bookmark" : workout.sport.systemImage,
                                actionSymbol: "play.fill"
                            )
                        }
                        .accessibilityHint("Starts this workout immediately")
                    }
                    if savedWorkouts == nil {
                        Text("Open Wind Run on iPhone to sync workouts.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if workouts.isEmpty {
                        Text("Create workouts in the iPhone app.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !recentRuns.isEmpty {
                    Section("Recent Runs") {
                        ForEach(recentRuns) { run in
                            NavigationLink(value: WatchRoute.summary(run)) {
                                WatchRunHistoryRow(run: run, unit: unit, isSynced: confirmed.contains(run.runID))
                            }
                        }
                    }
                }

                NavigationLink(value: WatchRoute.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .navigationTitle("Workouts")
            .navigationDestination(for: WatchRoute.self) { route in
                switch route {
                case .goal(let goal):
                    WatchWorkoutGoalView(goal: goal, unit: unit) { startRun(goal: $0) }
                case .summary(let run):
                    WatchRunSummaryView(run: run, unit: unit, isSynced: confirmed.contains(run.runID))
                case .settings:
                    WatchSettingsView()
                }
            }
        }
        .disabled(isPickingUpRun || isAskingHealth)
        .fullScreenCover(isPresented: isRecording, onDismiss: { path.removeAll() }) {
            if let recorder {
                WatchActiveRunView(recorder: recorder)
            }
        }
        // First open: ask about settings that stay off until the runner says yes, like heart rate.
        .presentsPrompts()
        // Heart rate turned on before Wind Run kept Apple's distance: Health asks about it once.
        .task {
            await HeartRateMonitor.askForNewAccessIfOn()
            await HealthSync.shared.askForNewAccessIfOn()
        }
        // A run the app was closed in carries on, if watchOS kept its workout going.
        .task {
            guard isPickingUpRun else { return }
            if let carriedOn = await WorkoutRecovery.shared.carryOnOrFinish(in: modelContext, measuresHeartRate: measuresHeartRate) {
                recorder = carriedOn
            }
            isPickingUpRun = false
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { SettingsSync.shared.sendPendingRuns() }
        }
        .onChange(of: coachToday, initial: true) { sessions = WatchCoachSession.decode(coachToday) }
        .onChange(of: savedWorkouts, initial: true) { workouts = WatchSavedWorkout.decode(savedWorkouts) }
    }

    private var savedHike: WatchSavedWorkout? {
        workouts.first { WorkoutSport.isHikeName($0.name) && $0.sport == .hiking }
    }

    private func goalLink(_ choice: WorkoutChoice, goal: RunGoal, detail: String) -> some View {
        NavigationLink(value: WatchRoute.goal(goal)) {
            WatchWorkoutLabel(title: choice.name, detail: detail, symbol: choice.type.systemImage, actionSymbol: "chevron.forward")
        }
        .accessibilityHint("Opens goal and start controls")
    }

    private var isRecording: Binding<Bool> {
        Binding(
            get: { recorder?.run != nil },
            set: { isPresented in
                if !isPresented { recorder = nil }
            }
        )
    }

    /// Sessions planned for today that haven't been run on this watch. The iPhone drops the ones run there.
    private var todaysSessions: [WatchCoachSession] {
        WatchCoachSession.toDo(sessions, doneSessionIDs: Set(todaysRuns.compactMap { $0.coachWorkout?.sessionID }))
    }

    /// A free run, a run with a goal, or one of today's coach sessions.
    private func startRun(_ session: WatchCoachSession? = nil, goal: RunGoal? = nil, sport: WorkoutSport = .running) {
        whenHealthHasAsked {
            let recorder = RunRecorder(modelContext: modelContext)
            if let session {
                recorder.start(coachWorkout: session.makeWorkout(in: modelContext), measuresHeartRate: measuresHeartRate)
            } else {
                switch goal {
                case .distance(let meters): lastDistance = meters
                case .time(let seconds): lastTime = seconds
                case nil: break
                }
                recorder.start(sport: sport, goal: goal, measuresHeartRate: measuresHeartRate)
            }
            self.recorder = recorder
        }
    }

    /// One of the iPhone's saved interval workouts, started in one tap.
    private func startRun(_ workout: WatchSavedWorkout) {
        whenHealthHasAsked {
            let recorder = RunRecorder(modelContext: modelContext)
            recorder.start(kind: .intervals, intervalPlan: workout.makePlan(in: modelContext), measuresHeartRate: measuresHeartRate)
            self.recorder = recorder
        }
    }

    /// Only a workout session keeps the run going with the wrist down, and it needs workouts allowed in
    /// Health. The first run asks, even with heart rate off; after that the run starts at once.
    private func whenHealthHasAsked(_ start: @escaping () -> Void) {
        guard recorder == nil, !isPickingUpRun, !isAskingHealth else { return }
        guard HealthSync.shared.isAvailable, HealthSync.shared.access == .notDetermined else {
            start()
            return
        }
        isAskingHealth = true
        Task {
            let access = await HeartRateMonitor.requestSessionAccess()
            Trace.log(.health, "Workout access asked before the first run", ["allowed": access == .allowed])
            isAskingHealth = false
            start()
        }
    }
}

/// A workout's name, optional target, and an icon for starting or opening it.
private struct WatchWorkoutLabel: View {
    let title: String
    var detail: String? = nil
    let symbol: String
    let actionSymbol: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(.tint)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let detail {
                    Text(detail)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: actionSymbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WatchRootView()
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
}
