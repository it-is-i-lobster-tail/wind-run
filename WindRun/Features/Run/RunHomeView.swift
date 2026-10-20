//
//  RunHomeView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// The plain run: one button to start, and the runs you've done.
struct RunHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage(HeartRateMonitor.storageKey) private var measuresHeartRate = false

    @Query(sort: \Run.startDateValue, order: .reverse) private var allRuns: [Run]
    @Query private var coachPlans: [CoachPlan]
    @State private var recorder: RunRecorder?
    @State private var finishedRun: Run?
    @State private var coach = CoachRouter()
    /// Set while the day's heat question is asked before a coached run starts.
    @State private var askingHeat: CoachWorkout?

    private var coachPlan: CoachPlan? {
        guard TermsAcceptance.isCurrent() else { return nil }
        return coachPlans.active
    }

    private var finishedRuns: [Run] {
        allRuns.filter { $0.status == .complete }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LayoutMetrics.sectionSpacing * 2) {
                    StartButton { startRun() }
                        .padding(.top, LayoutMetrics.sectionSpacing * 2)

                    if !todaysSessions.isEmpty {
                        TodayCard(workouts: todaysSessions, unit: unit, start: startCoached)
                    }

                    history
                }
                .padding(.horizontal)
            }
            .clearsFloatingBar()
            .navigationTitle("Run")
            .navigationDestination(for: Run.self) { run in
                RunDetailView(run: run, openCoach: coachPlan.map { _ in coach.open })
            }
        }
        .fullScreenCover(isPresented: isRecording, onDismiss: checkIn) {
            if let recorder {
                ActiveRunView(recorder: recorder)
            }
        }
        .coachSheets(coach, plan: coachPlan)
        .coachHeatCheck($askingHeat) { startRun($0) }
    }

    @ViewBuilder
    private var history: some View {
        if finishedRuns.isEmpty {
            EmptyStateView(
                title: "No runs yet",
                systemImage: "figure.run",
                description: "Only you can see your runs."
            )
        } else {
            VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
                Text("Recent")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                ForEach(finishedRuns) { run in
                    NavigationLink(value: run) {
                        RunRow(run: run, unit: unit)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
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

    /// With a coach plan, a finished run goes to the coach, which asks how it went.
    private func checkIn() {
        defer { finishedRun = nil }
        guard coachPlan != nil, let run = finishedRun, run.status == .complete else { return }
        coach.open(.runCheckIn(runID: run.runID))
    }

    /// Today's runs from the coach that are still to do.
    private var todaysSessions: [CoachWorkout] {
        guard let coachPlan, let state = CoachService(context: modelContext).state(of: coachPlan) else { return [] }
        let workouts = coachPlan.weeks.flatMap(\.workouts)
        return CoachEngine.todaysSessions(state, now: .now, calendar: .current)
            .filter { $0.kind.isRun && $0.status.isPlanned }
            .compactMap { session in workouts.first { $0.sessionID == session.id && !$0.isDone } }
    }

    /// Today's coach session, after the day's heat question when it's due.
    private func startCoached(_ workout: CoachWorkout) {
        if CoachRunStart.asksHeat(before: workout, in: modelContext) {
            askingHeat = workout
        } else {
            startRun(workout)
        }
    }

    /// A plain run, or the coach's session when one is given.
    private func startRun(_ workout: CoachWorkout? = nil) {
        let recorder = RunRecorder(modelContext: modelContext)
        if let workout {
            CoachRunStart.attachHeartRateCue(to: recorder, for: workout, in: modelContext)
            recorder.start(coachWorkout: workout, measuresHeartRate: measuresHeartRate)
        } else {
            recorder.start(measuresHeartRate: measuresHeartRate)
        }
        self.recorder = recorder
    }
}

/// Today's coach session under the start button, to run it with its targets.
private struct TodayCard: View {
    let workouts: [CoachWorkout]
    let unit: DistanceUnit
    let start: (CoachWorkout) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            Text("Today from your coach")
                .font(.headline)
                .foregroundStyle(.secondary)
            ForEach(workouts) { workout in
                AdaptiveRow {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.title)
                            .font(.body.weight(.semibold))
                        Text(CoachFormat.targetSummary(workout.target, unit: unit))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    Spacer(minLength: 0)
                    Button("Start") { start(workout) }
                        .buttonStyle(.glassProminent)
                        .accessibilityLabel("Start \(workout.title)")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
    }
}

private struct StartButton: View {
    private static let size: CGFloat = 180

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: "figure.run")
                    .font(.system(size: 44, weight: .semibold))
                Text("Start")
                    .font(.title2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(width: Self.size, height: Self.size)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(.accentColor).interactive(), in: .circle)
        .accessibilityLabel("Start run")
    }
}

#Preview("Run home - With runs") {
    RunHomeView()
        .modelContainer(WindRunSeed.containerWithRuns())
        .environment(CoachInbox())
}

#Preview("Run home - Empty") {
    RunHomeView()
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
        .environment(CoachInbox())
}
