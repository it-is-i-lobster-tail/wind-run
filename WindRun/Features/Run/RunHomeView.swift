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

    @Query(sort: \Run.startDateValue, order: .reverse) private var allRuns: [Run]
    @State private var recorder: RunRecorder?

    private var finishedRuns: [Run] {
        allRuns.filter { $0.status == .complete }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: LayoutMetrics.sectionSpacing * 2) {
                    StartButton(action: startRun)
                        .padding(.top, LayoutMetrics.sectionSpacing * 2)

                    history
                }
                .padding(.horizontal)
            }
            .navigationTitle("Run")
            .navigationDestination(for: Run.self) { run in
                RunDetailView(run: run)
            }
        }
        .fullScreenCover(isPresented: isRecording) {
            if let recorder {
                ActiveRunView(recorder: recorder)
            }
        }
    }

    @ViewBuilder
    private var history: some View {
        if finishedRuns.isEmpty {
            EmptyStateView(
                title: "No runs yet",
                systemImage: "figure.run",
                description: "Your runs stay on this device."
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
                if !isPresented { recorder = nil }
            }
        )
    }

    private func startRun() {
        let recorder = RunRecorder(modelContext: modelContext)
        recorder.start()
        self.recorder = recorder
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
}

#Preview("Run home - Empty") {
    RunHomeView()
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
}
