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
                // A structured run opens on its steps; the plain numbers are one swipe away.
                if let steps = recorder.steps {
                    stepPage(steps, run: run)
                }
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
                if let heartRate = recorder.heartRate {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                        Text(RunFormat.heartRate(heartRate.beatsPerMinute))
                            .foregroundStyle(.secondary)
                    }
                    .font(.title3.monospacedDigit())
                    .accessibilityElement(children: .combine)
                }
                if recorder.footstepCount != nil {
                    Text(RunFormat.cadence(recorder.cadence))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if recorder.isAutoPaused {
                    Text("Auto-paused")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }

    /// Where the runner is in the steps: the step, what's left of it big, and a button to move on.
    /// Walk breaks end on this button, so the coach gets the real break times. An open last step, such
    /// as a cool down, has no button: it runs until the run is finished.
    private func stepPage(_ steps: StepTracker, run: Run) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = run.activeDuration(at: context.date)
            VStack(alignment: .leading, spacing: 2) {
                if let step = steps.current {
                    Text("Step \(steps.index + 1) of \(steps.timeline.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(step.isWalk ? "Walk" : step.kind.name)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(step.kind == .work && !step.isWalk ? Color.accentColor : .primary)
                    Text(remaining(steps, elapsed: elapsed, meters: run.distanceMeters))
                        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    if steps.runsUntilFinish {
                        Text("Finish when you're done")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Button(stepButtonTitle(step)) { recorder.nextStep() }
                            .buttonStyle(.borderedProminent)
                            .tint(.accentColor)
                            .foregroundStyle(.onAccent)
                    }
                } else {
                    Text("All steps done")
                        .font(.headline)
                    Text(RunFormat.duration(elapsed))
                        .font(.system(size: 40, weight: .semibold, design: .rounded).monospacedDigit())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }

    /// Time or distance left in the step, or the time in an open one.
    private func remaining(_ steps: StepTracker, elapsed: TimeInterval, meters: Double) -> String {
        switch steps.remaining(elapsed: elapsed, meters: meters) {
        case .time(let seconds): RunFormat.duration(seconds)
        case .distance(let left): RunFormat.distance(left, unit: unit)
        case .open, nil: RunFormat.duration(steps.elapsedInStep(elapsed))
        }
    }

    private func stepButtonTitle(_ step: PlannedIntervalStep) -> String {
        if case .open = step.goal { return step.isWalk ? "Run again" : "Next step" }
        return "End step"
    }

    private func controls(for run: Run) -> some View {
        VStack {
            if run.status == .paused {
                Button("Resume", systemImage: "play.fill") { recorder.resume() }
                    .tint(.accentColor)
                    .foregroundStyle(.onAccent)
                Button("Finish", systemImage: "flag.checkered") {
                    recorder.finish()
                    // The coach lives on the iPhone, so a coached run goes there to count.
                    if run.kind == .coached, let record = WatchRunRecord(run) {
                        SettingsSync.shared.sendRun(record)
                    }
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
                    .foregroundStyle(.onAccent)
            }
        }
        .buttonStyle(.borderedProminent)
    }
}
