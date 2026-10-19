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

    @State private var recorder: RunRecorder?

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
        .fullScreenCover(isPresented: isRecording) {
            if let recorder {
                ActiveRunView(recorder: recorder)
            }
        }
    }

    private var isRecording: Binding<Bool> {
        Binding(
            get: { recorder?.run != nil },
            set: { isPresented in
                if !isPresented { recorder = nil }
            }
        )
    }

    private func start() {
        let recorder = RunRecorder(modelContext: modelContext)
        recorder.start(coachWorkout: workout, measuresHeartRate: measuresHeartRate)
        self.recorder = recorder
    }
}
