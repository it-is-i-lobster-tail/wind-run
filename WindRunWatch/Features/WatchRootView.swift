//
//  WatchRootView.swift
//  Wind Run Watch
//

import SwiftData
import SwiftUI

struct WatchRootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage(HeartRateMonitor.storageKey) private var measuresHeartRate = false
    /// The newest finished run.
    @Query private var lastRuns: [Run]
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
    /// True at launch while a run the app was closed in waits to carry on with its workout session.
    @State private var isPickingUpRun = RunRecovery.recordingRunID() != nil
    /// True while Health asks about workouts before the first run.
    @State private var isAskingHealth = false

    init() {
        var last = FetchDescriptor<Run>(
            predicate: #Predicate { $0.endDateValue != nil },
            sortBy: [SortDescriptor(\.startDateValue, order: .reverse)]
        )
        last.fetchLimit = 1
        _lastRuns = Query(last)
        let today = Calendar.current.startOfDay(for: .now)
        // A relationship can't be compared with nil in a predicate, so the coached runs are picked out below.
        _todaysRuns = Query(filter: #Predicate<Run> { $0.startDateValue >= today && $0.endDateValue != nil })
    }

    private var lastRun: Run? {
        lastRuns.first
    }

    var body: some View {
        let today = todaysSessions
        NavigationStack {
            List {
                if isPickingUpRun {
                    HStack {
                        ProgressView()
                        Text("Picking up your run…")
                            .font(.footnote)
                    }
                }

                Button { startRun() } label: {
                    Label("Free Run", systemImage: "figure.run")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12).fill(Color.accentColor)
                )
                .accessibilityHint("Starts a run")

                if !today.isEmpty {
                    Section("Today's Workout") {
                        ForEach(today) { session in
                            Button { startRun(session) } label: {
                                WatchSessionRow(session: session, unit: unit)
                            }
                            .accessibilityHint("Starts this workout")
                        }
                    }
                } else if coachToday != nil, !sessions.contains(where: { Calendar.current.isDateInToday($0.date) }) {
                    // Not sent today: a rest day, or the iPhone hasn't been opened since yesterday.
                    Section("Today's Workout") {
                        Text("Nothing here for today. Open Wind Run on your iPhone to bring today's workout over.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Intervals") {
                    ForEach(workouts) { workout in
                        Button { startRun(workout) } label: {
                            WatchWorkoutRow(workout: workout, unit: unit)
                        }
                        .accessibilityHint("Starts this workout")
                    }
                    if workouts.isEmpty {
                        Text("Build interval workouts under Workout on your iPhone, then start them here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastRun {
                    Section {
                        VStack(alignment: .leading) {
                            Text(RunFormat.distance(lastRun.distanceMeters, unit: unit))
                                .font(.headline.monospacedDigit())
                            Text("\(RunFormat.duration(lastRun.activeDuration())) · \(RunFormat.day(lastRun.startDate))")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    } header: {
                        Text("Last run")
                    } footer: {
                        if lastRun.kind != .coached {
                            Text("Runs started here stay on your watch for now. Coach sessions go to your iPhone.")
                        }
                    }
                }

                NavigationLink {
                    WatchSettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .navigationTitle("Wind Run")
            .disabled(isPickingUpRun || isAskingHealth)
        }
        .fullScreenCover(isPresented: isRecording) {
            if let recorder {
                WatchActiveRunView(recorder: recorder)
            }
        }
        // First open: ask about settings that stay off until the runner says yes, like heart rate.
        .presentsPrompts()
        // Heart rate turned on before Wind Run kept Apple's distance: Health asks about it once.
        .task { await HeartRateMonitor.askForNewAccessIfOn() }
        // A run the app was closed in carries on, if watchOS kept its workout going.
        .task {
            guard isPickingUpRun else { return }
            if let carriedOn = await WorkoutRecovery.shared.carryOnOrFinish(in: modelContext, measuresHeartRate: measuresHeartRate) {
                recorder = carriedOn
            }
            isPickingUpRun = false
        }
        .onChange(of: coachToday, initial: true) { sessions = WatchCoachSession.decode(coachToday) }
        .onChange(of: savedWorkouts, initial: true) { workouts = WatchSavedWorkout.decode(savedWorkouts) }
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
        let done = Set(todaysRuns.compactMap { $0.coachWorkout?.sessionID })
        return sessions.filter { session in
            Calendar.current.isDateInToday(session.date) && !done.contains(session.sessionID)
        }
    }

    /// A plain run, or one of today's coach sessions with its steps.
    private func startRun(_ session: WatchCoachSession? = nil) {
        whenHealthHasAsked {
            let recorder = RunRecorder(modelContext: modelContext)
            if let session {
                recorder.start(coachWorkout: session.makeWorkout(in: modelContext), measuresHeartRate: measuresHeartRate)
            } else {
                recorder.start(measuresHeartRate: measuresHeartRate)
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

/// A saved workout to start: its name and its length.
private struct WatchWorkoutRow: View {
    let workout: WatchSavedWorkout
    let unit: DistanceUnit

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.name)
                    .font(.headline)
                Text(summary)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }

    /// "45 min", or "22 min + open warm up and cool down".
    private var summary: String {
        RunFormat.intervalLength(workout.timeline, unit: unit)
    }
}

/// A coach session to start: its name and what it asks for.
private struct WatchSessionRow: View {
    let session: WatchCoachSession
    let unit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.title)
                .font(.headline)
            if let summary {
                Text(summary)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The title and what it asks for, read together.
        .accessibilityElement(children: .combine)
    }

    /// "40 min · 4:50–5:05 /km", or how long a session with steps is: "45 min".
    private var summary: String? {
        var parts: [String] = []
        if !session.timeline.isEmpty {
            parts.append(RunFormat.intervalLength(session.timeline, unit: unit))
        } else if let meters = session.targetMeters, meters > 0 {
            parts.append(RunFormat.distance(meters, unit: unit, rounding: .toNearestOrAwayFromZero))
        } else if let seconds = session.targetSeconds, seconds > 0 {
            parts.append("\(Int((seconds / 60).rounded())) min")
        }
        if let pace = session.target.pace {
            let fast = RunFormat.pace(pace.lowerBound, unit: unit, withUnit: false)
            let slow = RunFormat.pace(pace.upperBound, unit: unit, withUnit: false)
            parts.append(fast == slow ? "\(fast) /\(unit.symbol)" : "\(fast)–\(slow) /\(unit.symbol)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

#Preview {
    WatchRootView()
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
}
