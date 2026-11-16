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
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    WatchRunScreen(
                        display: display(for: run, at: context.date),
                        readings: readings(at: context.date)
                    ) {
                        Trace.tap("Watch run", "Next step", ["step": (recorder.steps?.index ?? 0) + 1])
                        recorder.nextStep()
                    }
                }
                .watchRunBackground()
                controls(for: run)
                    .watchRunBackground()
            }
            .tabViewStyle(.verticalPage)
            // A run ends with Finish or Discard, never by closing the screen and leaving GPS on.
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func display(for run: Run, at date: Date) -> WatchRunDisplay {
        WatchRunDisplay(WatchRunDisplay.Input(
            status: run.status,
            isAutoPaused: recorder.isAutoPaused,
            elapsed: run.activeDuration(at: date),
            meters: run.distanceMeters,
            unit: unit,
            steps: recorder.steps,
            coach: run.coachWorkout?.target
        ))
    }

    /// The runner's display screen as the run reads at `date`.
    private func readings(at date: Date) -> DisplayScreenReadings {
        let snapshot = recorder.snapshot(at: date, unit: unit) ?? RunSnapshot(elapsed: 0, meters: 0, unit: unit)
        return DisplayScreen.current.readings(snapshot)
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
                // Timed and distance steps move on by themselves; this cuts one short. An open step has
                // its own Next step button on the run screen.
                if let steps = recorder.steps, let step = steps.current, step.goal != .open {
                    Button("End step", systemImage: "forward.end.fill") {
                        Trace.tap("Watch run", "End step", ["step": steps.index + 1])
                        recorder.nextStep()
                    }
                    .tint(.gray)
                }
            }
        }
        .buttonStyle(.borderedProminent)
    }
}

extension View {
    /// Black, with a restrained teal glow along the top edge.
    func watchRunBackground() -> some View {
        containerBackground(for: .tabView) {
            ZStack(alignment: .top) {
                Color.black
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.45), Color.accentColor.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 44)
            }
            .ignoresSafeArea()
        }
    }
}
