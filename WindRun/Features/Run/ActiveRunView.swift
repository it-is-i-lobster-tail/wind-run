//
//  ActiveRunView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// The screen you look at mid-run: big numbers and very little else.
struct ActiveRunView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    let recorder: RunRecorder

    @State private var isConfirmingDiscard = false

    var body: some View {
        if let run = recorder.run {
            VStack(spacing: LayoutMetrics.sectionSpacing) {
                if recorder.locationDenied {
                    Label("Location is off, so distance can't be measured.", systemImage: "location.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: LayoutMetrics.sectionSpacing * 1.5) {
                        Metric(
                            value: RunFormat.duration(run.activeDuration(at: context.date)),
                            label: "Time",
                            size: 76
                        )
                        HStack {
                            Metric(
                                value: RunFormat.distance(run.distanceMeters, unit: unit, withUnit: false),
                                label: unit.symbol,
                                size: 44
                            )
                            .frame(maxWidth: .infinity)
                            Metric(
                                value: RunFormat.pace(run.pace(at: context.date), unit: unit, withUnit: false),
                                label: "/\(unit.symbol)",
                                size: 44
                            )
                            .frame(maxWidth: .infinity)
                        }
                        if let heartRate = recorder.heartRate {
                            Metric(
                                value: RunFormat.heartRate(heartRate.beatsPerMinute, withUnit: false),
                                label: "bpm",
                                size: 44
                            )
                        }
                    }
                }

                Spacer()

                controls(for: run)
            }
            .padding()
            .confirmationDialog("Discard this run?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard run", role: .destructive) {
                    recorder.discard()
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private func controls(for run: Run) -> some View {
        GlassEffectContainer(spacing: LayoutMetrics.sectionSpacing) {
            HStack(spacing: LayoutMetrics.sectionSpacing) {
                if run.status == .paused {
                    RoundControl(title: "Discard", systemImage: "trash") {
                        isConfirmingDiscard = true
                    }
                    RoundControl(title: "Resume", systemImage: "play.fill", prominent: true) {
                        recorder.resume()
                    }
                    RoundControl(title: "Finish", systemImage: "flag.checkered") {
                        recorder.finish()
                        dismiss()
                    }
                } else {
                    RoundControl(title: "Pause", systemImage: "pause.fill", prominent: true) {
                        recorder.pause()
                    }
                }
            }
        }
        .animation(.snappy, value: run.status)
        .padding(.bottom)
    }
}

private struct Metric: View {
    let value: String
    let label: String
    let size: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText())
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct RoundControl: View {
    let title: String
    let systemImage: String
    var prominent = false
    let action: () -> Void

    private var size: CGFloat { prominent ? 96 : 72 }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(prominent ? .largeTitle : .title2)
                .foregroundStyle(prominent ? .onAccent : .primary)
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(
            prominent ? .regular.tint(.accentColor).interactive() : .regular.interactive(),
            in: .circle
        )
        .accessibilityLabel(title)
    }
}

#Preview("Active run") {
    let container = WindRunSchema.makeContainer(inMemory: true)
    let recorder = RunRecorder(modelContext: container.mainContext)
    recorder.start()
    return ActiveRunView(recorder: recorder)
        .modelContainer(container)
}
