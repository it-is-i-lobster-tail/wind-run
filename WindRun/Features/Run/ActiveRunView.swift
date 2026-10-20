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
    @State private var stopLine = SafetyText.stopLine
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if let run = recorder.run {
            VStack(spacing: LayoutMetrics.sectionSpacing) {
                if recorder.locationDenied {
                    Label("Location is off, so distance can't be measured.", systemImage: "location.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let workout = run.coachWorkout {
                    CoachSessionBanner(target: workout.target, unit: unit, stopLine: stopLine)
                        .task { stopLine = CoachRunStart.stopLine(for: workout, in: modelContext) }
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
                        if let steps = recorder.steps {
                            StepPanel(steps: steps, elapsed: run.activeDuration(at: context.date), meters: run.distanceMeters, unit: unit) {
                                recorder.nextStep()
                            }
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

/// Where the runner is in a structured run: the step, what's left of it, and a button to move on.
/// Walk breaks end on this button, so the coach gets the real break times.
private struct StepPanel: View {
    let steps: StepTracker
    let elapsed: TimeInterval
    let meters: Double
    let unit: DistanceUnit
    let next: () -> Void

    var body: some View {
        if let step = steps.current {
            VStack(spacing: LayoutMetrics.compactSpacing) {
                Text("Step \(steps.index + 1) of \(steps.timeline.count)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text(step.isWalk ? "Walk" : step.kind.name)
                    .font(.title2.weight(.semibold))
                if let remaining = remainingText {
                    Text(remaining)
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button(buttonTitle(for: step), action: next)
                    .buttonStyle(.glassProminent)
            }
            .accessibilityElement(children: .contain)
        } else {
            Text("All steps done")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private var remainingText: String? {
        switch steps.remaining(elapsed: elapsed, meters: meters) {
        case .time(let seconds): "\(RunFormat.duration(seconds)) left"
        case .distance(let left): "\(RunFormat.distance(left, unit: unit)) left"
        case .open: RunFormat.duration(steps.elapsedInStep(elapsed))
        case nil: nil
        }
    }

    private func buttonTitle(for step: PlannedIntervalStep) -> String {
        if case .open = step.goal { return step.isWalk ? "Run again" : "Next step" }
        return "End step"
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
                .foregroundStyle(prominent ? .white : .primary)
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
