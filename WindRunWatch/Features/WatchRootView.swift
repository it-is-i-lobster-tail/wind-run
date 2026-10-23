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
    @Query(sort: \Run.startDateValue, order: .reverse) private var runs: [Run]
    /// Today's coach sessions as the iPhone last sent them.
    @AppStorage(SettingsSync.coachTodayKey) private var coachToday: Data?

    @State private var recorder: RunRecorder?

    private var lastRun: Run? {
        runs.first { $0.status == .complete }
    }

    var body: some View {
        NavigationStack {
            List {
                Button { startRun() } label: {
                    Label("Run", systemImage: "figure.run")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12).fill(Color.accentColor)
                )

                if !todaysSessions.isEmpty {
                    Section("Today from your coach") {
                        ForEach(todaysSessions) { session in
                            Button { startRun(session) } label: {
                                WatchSessionRow(session: session, unit: unit)
                            }
                            .accessibilityLabel("Start \(session.title)")
                        }
                    }
                }

                ComingSoonRow(title: "Intervals", systemImage: "repeat")

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

                NavigationLink {
                    WatchSettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .navigationTitle("Wind Run")
        }
        .fullScreenCover(isPresented: isRecording) {
            if let recorder {
                WatchActiveRunView(recorder: recorder)
            }
        }
        // First open: ask about settings that stay off until the runner says yes, like heart rate.
        .presentsPrompts()
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
        let done = Set(runs.filter { $0.status == .complete }.compactMap { $0.coachWorkout?.sessionID })
        return WatchCoachSession.decode(coachToday).filter { session in
            Calendar.current.isDateInToday(session.date) && !done.contains(session.sessionID)
        }
    }

    /// A plain run, or one of today's coach sessions with its steps.
    private func startRun(_ session: WatchCoachSession? = nil) {
        let recorder = RunRecorder(modelContext: modelContext)
        if let session {
            recorder.start(coachWorkout: session.makeWorkout(in: modelContext), measuresHeartRate: measuresHeartRate)
        } else {
            recorder.start(measuresHeartRate: measuresHeartRate)
        }
        self.recorder = recorder
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
    }

    /// "40 min · 4:50–5:05 /km", or the step count for a session with steps.
    private var summary: String? {
        var parts: [String] = []
        let steps = session.timeline.count
        if steps > 0 {
            parts.append("\(steps) steps")
        } else if let meters = session.targetMeters, meters > 0 {
            parts.append(RunFormat.distance(meters, unit: unit))
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
