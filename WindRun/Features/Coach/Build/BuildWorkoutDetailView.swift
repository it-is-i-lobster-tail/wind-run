//
//  BuildWorkoutDetailView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// One planned run: its distance and climb, with a button to run it.
struct BuildWorkoutDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @AppStorage(HeartRateMonitor.storageKey) private var measuresHeartRate = false

    let workout: CoachWorkout

    @State private var recorder: RunRecorder?

    var body: some View {
        // A re-plan can drop this run while it's open; its row is gone then.
        if workout.isDeleted || workout.modelContext == nil {
            ContentUnavailableView(
                "Run replanned",
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
                CoachSessionBanner(target: workout.target, unit: unit)

                Text(explanation)

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
                    .prominentAccentButton()
                }
            }
            .padding()
        }
        .clearsFloatingBar()
        // The banner already names the run, so the title gives its day.
        .navigationTitle((workout.scheduledDate ?? .now).formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: isRecording) {
            if let recorder {
                ActiveRunView(recorder: recorder)
            }
        }
    }

    private var explanation: String {
        let climb = workout.detail.isEmpty ? "" : " \(workout.detail)"
        switch workout.kind {
        case BuildSessionKind.long.rawValue:
            return "Your longest run of the week, at an easy pace you could chat at.\(climb) Walking breaks are fine."
        case BuildSessionKind.event.rawValue:
            return "Your event. Start easy and walk when you need to.\(climb)"
        default:
            return "An easy run at a pace you could chat at.\(climb) Run it any day you like: only the week's total matters."
        }
    }

    private var isRecording: Binding<Bool> {
        Binding(
            get: { recorder?.run != nil },
            set: { isPresented in
                if !isPresented {
                    recorder = nil
                    BuildRunStart.runFinished(in: modelContext)
                }
            }
        )
    }

    private func start() {
        let recorder = RunRecorder(modelContext: modelContext)
        BuildRunStart.attachCues(to: recorder, for: workout)
        recorder.start(coachWorkout: workout, measuresHeartRate: measuresHeartRate)
        self.recorder = recorder
    }
}
