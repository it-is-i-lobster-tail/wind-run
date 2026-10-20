//
//  CoachRunStart.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// What a coached run needs when it starts: the session it does, its stop line, the heart-rate
/// cue, and the day's heat question.
@MainActor
enum CoachRunStart {
    /// The planned session a stored session copies, with the plan's state.
    static func session(of workout: CoachWorkout, in context: ModelContext) -> (CoachState, PlannedSession)? {
        guard let plan = workout.week?.plan, let id = workout.sessionID,
              let state = CoachService(context: context).state(of: plan),
              let (week, position) = CoachEngine.locate(id, in: state)
        else { return nil }
        return (state, state.weeks[week].plan.sessions[position])
    }

    /// The in-run stop line, with its heat part when today's heat answer or the run's length calls for it.
    static func stopLine(for workout: CoachWorkout, in context: ModelContext) -> String {
        guard let (state, session) = session(of: workout, in: context) else { return SafetyText.stopLine }
        return CoachEngine.stopLine(for: session, state: state, now: .now, calendar: .current)
    }

    /// Gives the recorder the heart-rate cue for this session, when the runner's device-local
    /// settings allow coaching by heart rate. Call it before the recorder starts.
    static func attachHeartRateCue(to recorder: RunRecorder, for workout: CoachWorkout, in context: ModelContext) {
        let settings = CoachHeartRateStore.load()
        guard settings.canCoach, let (state, session) = session(of: workout, in: context) else { return }
        let zones = CoachEngine.heartRateZones(age: state.assessment.age, settings: settings)
        let parts = HeartRateCue.parts(for: session, zones: zones, device: settings.device, thresholdPace: state.paces.thresholdPace)
        guard !parts.isEmpty else { return }
        var tracker = HeartRateCueTracker(parts: parts, device: settings.device)
        recorder.spokenCue = { elapsed, meters, beatsPerMinute in
            tracker.update(elapsed: elapsed, meters: meters, beatsPerMinute: beatsPerMinute) ? HeartRateCue.text : nil
        }
    }

    // MARK: Heat (AD-16)

    /// The day the heat question was last asked at the start of a run, so it's asked once a day.
    static let heatAskedKey = "coachHeatAskedDate"

    /// Whether to ask how hot it will be before this run: an easy coached run, on a day with no
    /// heat answer yet and the question not yet asked.
    static func asksHeat(before workout: CoachWorkout, in context: ModelContext, defaults: UserDefaults = .standard) -> Bool {
        guard let (state, session) = session(of: workout, in: context),
              session.kind.isRun, session.effort == .easy
        else { return false }
        let calendar = Calendar.current
        if let asked = defaults.object(forKey: heatAskedKey) as? Date, calendar.isDateInToday(asked) { return false }
        return !state.readiness.contains { $0.heat != nil && calendar.isDateInToday($0.date) }
    }

    /// Stores the answer with the session, or nothing when it was skipped.
    static func recordHeat(_ heat: HeatAnswer?, for workout: CoachWorkout, in context: ModelContext, inbox: CoachInbox, defaults: UserDefaults = .standard) {
        defaults.set(Date.now, forKey: heatAskedKey)
        guard let heat, let plan = workout.week?.plan, let sessionID = workout.sessionID else { return }
        CoachActions(context: context, plan: plan, inbox: inbox).perform { state, runs, now, calendar in
            CoachEngine.submitReadiness(.goodToGo, heat: heat, sessionID: sessionID, state: state, runs: runs, now: now, calendar: calendar)
        }
    }
}

extension View {
    /// Asks the day's heat question before starting a coached run, when it hasn't been answered
    /// today. The run starts after the answer or "Skip"; closing the sheet cancels the start.
    func coachHeatCheck(_ workout: Binding<CoachWorkout?>, start: @escaping (CoachWorkout) -> Void) -> some View {
        modifier(CoachHeatCheck(workout: workout, start: start))
    }
}

private struct CoachHeatCheck: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Environment(CoachInbox.self) private var inbox

    @Binding var workout: CoachWorkout?
    let start: (CoachWorkout) -> Void

    /// The run to start once the sheet has closed.
    @State private var starting: CoachWorkout?

    func body(content: Content) -> some View {
        content
            .sheet(item: $workout, onDismiss: startIfAnswered) { workout in
                HeatQuestionView { heat in
                    CoachRunStart.recordHeat(heat, for: workout, in: modelContext, inbox: inbox)
                    starting = workout
                    self.workout = nil
                }
                .presentationDetents([.medium, .large])
            }
    }

    private func startIfAnswered() {
        guard let run = starting else { return }
        starting = nil
        start(run)
    }
}

/// "How hot will it be when you run?" with the engine's choices, or Skip.
private struct HeatQuestionView: View {
    let answer: (HeatAnswer?) -> Void

    var body: some View {
        let prompt = CoachPrompts.heat
        NavigationStack {
            Form {
                Section {
                    ForEach(prompt.choices, id: \.value) { choice in
                        Button {
                            answer(HeatAnswer(rawValue: choice.value))
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(choice.label)
                                if let detail = choice.detail {
                                    Text(detail)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text(prompt.text)
                } footer: {
                    Text("It helps the coach keep hot runs safe. Asked once a day.")
                }
            }
            .navigationTitle("Before you go")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Skip") { answer(nil) }
                }
            }
        }
    }
}
