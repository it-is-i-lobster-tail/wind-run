//
//  WatchRootView.swift
//  Wind Run Watch
//

import SwiftData
import SwiftUI

struct WatchRootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @Query(sort: \Run.startDateValue, order: .reverse) private var runs: [Run]

    @State private var recorder: RunRecorder?

    private var lastRun: Run? {
        runs.first { $0.status == .complete }
    }

    var body: some View {
        NavigationStack {
            List {
                Button(action: startRun) {
                    Label("Run", systemImage: "figure.run")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12).fill(Color.accentColor)
                )

                ComingSoonRow(title: "Intervals", systemImage: "repeat")
                ComingSoonRow(title: "Coach", systemImage: "flag.checkered")

                if let lastRun {
                    Section("Last run") {
                        VStack(alignment: .leading) {
                            Text(RunFormat.distance(lastRun.distanceMeters, unit: unit))
                                .font(.headline.monospacedDigit())
                            Text(RunFormat.duration(lastRun.activeDuration()))
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        WatchSettingsView()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
            .navigationTitle("Wind Run")
        }
        .fullScreenCover(isPresented: isRecording) {
            if let recorder {
                WatchActiveRunView(recorder: recorder)
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

private struct ComingSoonRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text("Soon")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WatchRootView()
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
}
