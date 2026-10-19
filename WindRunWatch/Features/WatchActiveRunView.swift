//
//  WatchActiveRunView.swift
//  Wind Run Watch
//

import SwiftData
import SwiftUI

struct WatchActiveRunView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    let recorder: RunRecorder

    var body: some View {
        if let run = recorder.run {
            TabView {
                metrics(for: run)
                controls(for: run)
            }
            .tabViewStyle(.verticalPage)
            // A run ends with Finish or Discard, never by closing the screen and leaving GPS on.
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func metrics(for run: Run) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 2) {
                Text(RunFormat.duration(run.activeDuration(at: context.date)))
                    .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(run.status == .paused ? .secondary : .primary)
                Text(RunFormat.distance(run.distanceMeters, unit: unit))
                    .font(.title3.monospacedDigit())
                Text(RunFormat.pace(run.pace(at: context.date), unit: unit))
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }

    private func controls(for run: Run) -> some View {
        VStack {
            if run.status == .paused {
                Button("Resume", systemImage: "play.fill") { recorder.resume() }
                    .tint(.accentColor)
                Button("Finish", systemImage: "flag.checkered") {
                    recorder.finish()
                    dismiss()
                }
                .tint(.gray)
                Button("Discard", systemImage: "trash", role: .destructive) {
                    recorder.discard()
                    dismiss()
                }
                .tint(.red)
            } else {
                Button("Pause", systemImage: "pause.fill") { recorder.pause() }
                    .tint(.accentColor)
            }
        }
        .buttonStyle(.borderedProminent)
    }
}
