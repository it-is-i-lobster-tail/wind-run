//
//  CoachWorkoutDetailView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// One planned session: what it asks for and why, with a button to run it.
struct CoachWorkoutDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CoachInbox.self) private var inbox
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage(HeartRateMonitor.storageKey) private var measuresHeartRate = false

    let workout: CoachWorkout
    /// Opens a coach screen over the plan, such as the check-in after the run.
    var openCoach: (CoachSheet) -> Void = { _ in }

    @State private var recorder: RunRecorder?
    @State private var finishedRun: Run?
    /// Set while the day's heat question is asked before the run starts.
    @State private var askingHeat: CoachWorkout?

    var body: some View {
        // A re-plan can drop this session while it's open; its row is gone then.
        if workout.isDeleted || workout.modelContext == nil {
            ContentUnavailableView(
                "Session replanned",
                systemImage: "calendar.badge.exclamationmark",
                description: Text("The coach changed this week. Go back to see the new plan.")
            )
        } else {
            details
        }
    }

    private var details: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                CoachSessionBanner(target: workout.target, unit: unit, stopLine: CoachRunStart.stopLine(for: workout, in: modelContext))

                if !workout.detail.isEmpty {
                    Text(workout.detail)
                }
                if !workout.notes.isEmpty {
                    Text(workout.notes)
                        .foregroundStyle(.secondary)
                }

                ForEach(CoachRunStart.advice(for: workout, in: modelContext, unit: unit), id: \.self) { advice in
                    Label(advice, systemImage: "speedometer")
                        .font(.subheadline)
                }

                if let intervalPlan = workout.intervalPlan {
                    IntervalPlanCard(plan: intervalPlan, unit: unit)
                }

                if workout.isDone {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                } else {
                    Button(action: tapStart) {
                        Label("Start run", systemImage: "figure.run")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, LayoutMetrics.compactSpacing)
                    }
                    .buttonStyle(.glassProminent)

                    if !moveDays.isEmpty {
                        Menu {
                            ForEach(moveDays, id: \.offset) { day in
                                Button(day.name) { move(to: day.offset) }
                            }
                        } label: {
                            Label("Move to another day", systemImage: "calendar")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, LayoutMetrics.compactSpacing)
                        }
                        .buttonStyle(.glass)
                    }
                }
            }
            .padding()
        }
        .clearsFloatingBar()
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
        .coachHeatCheck($askingHeat) { _ in start() }
        .fullScreenCover(isPresented: isRecording, onDismiss: checkIn) {
            if let recorder {
                ActiveRunView(recorder: recorder)
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

    /// After a finished run, the coach asks how it went.
    private func checkIn() {
        defer { finishedRun = nil }
        guard let run = finishedRun, run.status == .complete else { return }
        openCoach(.runCheckIn(runID: run.runID))
    }

    /// The days left this week the session can move to (AD-9). Race day never moves.
    private var moveDays: [(offset: Int, name: String)] {
        guard workout.kind != SessionKind.race.rawValue, workout.status == SessionStatus.planned.rawName,
              let weekStart = workout.week?.startDate else { return [] }
        let calendar = Calendar.current
        let today = calendar.dateComponents([.day], from: calendar.startOfDay(for: weekStart), to: calendar.startOfDay(for: .now)).day ?? 0
        return (max(0, today)...6).compactMap { offset in
            guard offset != workout.dayOffset, let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            let name = calendar.isDateInToday(date) ? "Today" : date.formatted(.dateTime.weekday(.wide))
            return (offset, name)
        }
    }

    private func move(to day: Int) {
        guard let plan = workout.week?.plan, let sessionID = workout.sessionID else { return }
        CoachActions(context: modelContext, plan: plan, inbox: inbox).perform { state, runs, now, calendar in
            CoachEngine.moveSession(sessionID, toDay: day, state: state, runs: runs, now: now, calendar: calendar)
        }
    }

    private func tapStart() {
        if CoachRunStart.asksHeat(before: workout, in: modelContext) {
            askingHeat = workout
        } else {
            start()
        }
    }

    private func start() {
        let recorder = RunRecorder(modelContext: modelContext)
        CoachRunStart.attachCues(to: recorder, for: workout, in: modelContext)
        recorder.start(coachWorkout: workout, measuresHeartRate: measuresHeartRate)
        self.recorder = recorder
    }
}
