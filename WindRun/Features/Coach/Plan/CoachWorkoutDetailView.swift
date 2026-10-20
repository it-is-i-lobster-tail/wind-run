//
//  CoachWorkoutDetailView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// One planned session: what it asks for and why, with a button to run it.
struct CoachWorkoutDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage(HeartRateMonitor.storageKey) private var measuresHeartRate = false

    let workout: CoachWorkout
    /// Opens a coach screen over the plan, such as the check-in after the run.
    var openCoach: (CoachSheet) -> Void = { _ in }

    @State private var recorder: RunRecorder?
    @State private var finishedRun: Run?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LayoutMetrics.sectionSpacing) {
                CoachSessionBanner(target: workout.target, unit: unit)

                if !workout.detail.isEmpty {
                    Text(workout.detail)
                }
                if !workout.notes.isEmpty {
                    Text(workout.notes)
                        .foregroundStyle(.secondary)
                }

                if let intervalPlan = workout.intervalPlan {
                    IntervalPlanCard(plan: intervalPlan, unit: unit)
                }

                if workout.isDone {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                } else {
                    Button(action: start) {
                        Label("Start run", systemImage: "figure.run")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, LayoutMetrics.compactSpacing)
                    }
                    .buttonStyle(.glassProminent)
                }
            }
            .padding()
        }
        .clearsFloatingBar()
        .navigationTitle(workout.title)
        .navigationBarTitleDisplayMode(.inline)
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

    private func start() {
        let recorder = RunRecorder(modelContext: modelContext)
        recorder.start(coachWorkout: workout, measuresHeartRate: measuresHeartRate)
        self.recorder = recorder
    }
}
