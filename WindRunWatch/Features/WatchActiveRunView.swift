//
//  WatchActiveRunView.swift
//  Wind Run Watch
//

import SwiftData
import SwiftUI
import WatchKit

struct WatchActiveRunView: View {
    @Environment(\.dismiss) private var dismiss
    /// Always On with the wrist down.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    let recorder: RunRecorder
    @State private var confirmsDiscard = false

    var body: some View {
        if let run = recorder.run {
            TabView {
                // Ticks as each second of running time turns over, like the iPhone and the Lock Screen. With the
                // wrist down the screen redraws once a minute, and the elapsed time counts by itself.
                TimelineView(.periodic(from: run.clockStart(), by: isLuminanceReduced ? 60 : 1)) { context in
                    WatchRunScreen(
                        display: display(for: run, at: context.date),
                        readings: readings(for: run, at: context.date),
                        dimmed: isLuminanceReduced
                    ) {
                        Trace.tap("Watch run", "Next step", ["step": (recorder.steps?.index ?? 0) + 1])
                        recorder.nextStep()
                    }
                }
                .watchRunBackground(dimmed: isLuminanceReduced)
                controls(for: run)
                    .watchRunBackground(dimmed: isLuminanceReduced)
            }
            .tabViewStyle(.verticalPage)
            // A run ends with Finish or Discard, never by closing the screen and leaving GPS on.
            .toolbar(.hidden, for: .navigationBar)
            .confirmationDialog("Discard this \(run.sport.noun)?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Discard \(run.sport.noun.capitalized)", role: .destructive) {
                    Trace.tap("Watch run", "Discard confirmed")
                    WKInterfaceDevice.current().play(.failure)
                    recorder.discard()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {
                    Trace.tap("Watch run", "Discard cancelled")
                }
            } message: {
                Text("Its distance, time and route are deleted.")
            }
        }
    }

    private func display(for run: Run, at date: Date) -> WatchRunDisplay {
        WatchRunDisplay(WatchRunDisplay.Input(
            status: run.status,
            isAutoPaused: recorder.isAutoPaused,
            elapsed: run.activeDuration(at: date),
            meters: run.distanceMeters,
            unit: run.intervalPlan?.distanceUnit ?? unit,
            steps: recorder.steps,
            coach: run.coachWorkout?.target,
            goal: run.goal,
            goalReached: recorder.goalReached,
            gps: recorder.gpsSignal(at: date),
            locationOff: recorder.locationDenied || recorder.locationApproximate
        ))
    }

    /// The run's display screen as the run reads at `date`.
    private func readings(for run: Run, at date: Date) -> DisplayScreenReadings {
        let unit = run.intervalPlan?.distanceUnit ?? self.unit
        let snapshot = recorder.snapshot(at: date, unit: unit) ?? RunSnapshot(elapsed: 0, meters: 0, unit: unit)
        return recorder.displayScreen.readings(snapshot, clockRunsAt: isLuminanceReduced ? date : nil)
    }

    private func controls(for run: Run) -> some View {
        ScrollView {
            VStack {
                if run.status == .paused {
                    Button("Resume", systemImage: "play.fill") { recorder.resume() }
                        .tint(.accentColor)
                        .foregroundStyle(.onAccent)
                    Button("Finish", systemImage: "flag.checkered") {
                        recorder.finish()
                        WKInterfaceDevice.current().play(.success)
                        SettingsSync.shared.sendRun(run)
                        dismiss()
                    }
                    .tint(.gray)
                    // Set apart from Finish, and asked about first, so a stray tap can't delete the run.
                    Button("Discard", systemImage: "trash", role: .destructive) {
                        Trace.tap("Watch run", "Discard")
                        confirmsDiscard = true
                    }
                    .tint(.red)
                    .padding(.top, 10)
                } else {
                    Button("Pause", systemImage: "pause.fill") { recorder.pause() }
                        .tint(.accentColor)
                        .foregroundStyle(.onAccent)
                    // Timed and distance steps move on by themselves; this cuts one short. An open step has
                    // its own Next step button on the run screen.
                    if let steps = recorder.steps, let step = steps.current, step.goal != .open {
                        Button("Next step", systemImage: "forward.end.fill") {
                            Trace.tap("Watch run", "Next step", ["step": steps.index + 1])
                            recorder.nextStep()
                        }
                        .tint(.gray)
                    }
                }
                notes
            }
            .buttonStyle(.borderedProminent)
            .animation(.snappy, value: run.status)
        }
    }

    /// Why a number on the run screen is missing, when it is.
    @ViewBuilder private var notes: some View {
        if recorder.locationDenied {
            note("No GPS, so no distance. Allow Location for Wind Run in the watch's Settings > Privacy & Security > Location Services.")
        } else if recorder.locationApproximate {
            note("Precise Location is off, so no distance. Turn it on for Wind Run in the watch's Settings > Privacy & Security > Location Services.")
        }
        if recorder.heartRateStopped {
            note("Heart rate stopped. Another workout app may have taken over.")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
    }
}

extension View {
    /// Black, with a restrained teal glow along the top edge. Without the glow in Always On.
    func watchRunBackground(dimmed: Bool = false) -> some View {
        containerBackground(for: .tabView) {
            ZStack(alignment: .top) {
                Color.black
                if !dimmed {
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.45), Color.accentColor.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 44)
                }
            }
            .ignoresSafeArea()
        }
    }
}
