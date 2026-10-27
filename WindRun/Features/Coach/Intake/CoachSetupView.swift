//
//  CoachSetupView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// Coach setup: the questions a few at a time, then the goal check. Saved answers, Apple Health and logged runs
/// fill in what they can, and only the screens they don't answer are shown.
struct CoachSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var model: CoachIntakeModel
    @State private var isCheckingGoal = false
    let onStart: (CoachUpdate) -> Void

    init(flavor: CoachGoal, unit: DistanceUnit, saved: SavedCoachAnswers? = nil, onStart: @escaping (CoachUpdate) -> Void) {
        _model = State(initialValue: CoachIntakeModel(flavor: flavor, unit: unit, saved: saved))
        self.onStart = onStart
    }

    var body: some View {
        NavigationStack {
            Form {
                // The title is the section's header, not a row: a row is masked to the card's
                // rounded corners even with a clear background, which cut off the corner glyphs.
                Section {
                } header: {
                    Text(model.screen.title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }

                if model.screen == .runningLately, model.hasRunData {
                    Section {
                        Text("Filled in from your runs. Change anything that's off.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(model.steps, id: \.self) { step in
                    if model.steps.count > 1 {
                        Section {
                        } header: {
                            Text(step.title)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .textCase(nil)
                        }
                    }

                    IntakeStepView(model: model, step: step)

                    if let skipText = step.skipText, !model.intake.isAnswered(step) {
                        Section {
                            Text(skipText)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .animation(.default, value: model.screen)
            .navigationTitle(model.screen == .terms ? "Before you start" : "Step \(model.questionNumber) of \(model.questionCount)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                controls
            }
            .navigationDestination(isPresented: $isCheckingGoal) {
                GoalCheckView(model: model) { update in
                    onStart(update)
                    dismiss()
                }
            }
            .task { await fillIn() }
        }
    }

    private var controls: some View {
        // Wide, extra-large buttons that split the row, so they're easy to hit on the move.
        HStack(spacing: LayoutMetrics.compactSpacing) {
            if !model.isFirstScreen {
                Button { model.back() } label: {
                    Text("Back").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            Button {
                let last = model.isLastScreen
                model.next()
                CoachAnswerStore(context: modelContext).save(model.saved)
                if last {
                    model.settleShownAnswer()
                    isCheckingGoal = true
                }
            } label: {
                Text(model.isLastScreen ? "Check my goal" : "Next").frame(maxWidth: .infinity)
            }
            .prominentAccentButton()
            .disabled(!model.canContinue)
        }
        .font(.headline)
        .controlSize(.extraLarge)
        .padding()
    }

    /// Reads logged runs and Apple Health once, when setup opens.
    private func fillIn() async {
        let store = CoachAnswerStore(context: modelContext)
        let runs = store.loggedWorkouts()
        let health = await SetupHealthReader.read(skipping: store.healthWorkoutIDs(), overlapping: runs)
        var body = health.body
        // The weight the runner gave Wind Run for calories comes before Health's.
        if let weight = BodyWeight.kilograms() {
            body.weightKilograms = weight
        }
        model.fill(body: body, workouts: runs + health.workouts)
    }
}

/// The goal check: the coach's message, a later race day when the build needs more weeks, and the way to start.
/// Every goal starts with one tap; only a past race date or a Severe injury's pause holds it.
struct GoalCheckView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var model: CoachIntakeModel
    let onStart: (CoachUpdate) -> Void

    @State private var check: GoalCheck?

    var body: some View {
        Form {
            if let check {
                Section {
                    Label(check.verdict.label, systemImage: icon(for: check.verdict))
                        .font(.headline)
                        .foregroundStyle(tint(for: check.verdict))
                    Text(check.message)
                } header: {
                    Text("\(model.intake.goal.flavor.name): \(model.intake.goal.distance.name)")
                }

                if let feasibility = check.feasibility, check.verdict != .refused {
                    Section("When you could be ready") {
                        LabeledContent("Earliest", value: feasibility.earliestDate.formatted(date: .abbreviated, time: .omitted))
                        LabeledContent("More likely", value: feasibility.likelyDate.formatted(date: .abbreviated, time: .omitted))
                    }
                }

                if let forecast = check.forecast {
                    Section("Your race time today") {
                        LabeledContent("About", value: CoachFormat.clock(forecast.central))
                        LabeledContent("Range", value: "\(CoachFormat.clock(forecast.low))–\(CoachFormat.clock(forecast.high))")
                    }
                }

                Section {
                    LevelRows(
                        level: Binding(
                            get: { model.level },
                            set: { model.intake.level = $0; recheck() }
                        ),
                        recommended: model.assessment.levels.preset,
                        stepBackEveryThird: model.assessment.recoveryTier.stepsBackEveryThird
                    )
                } header: {
                    Text("How fast do you want to build?")
                } footer: {
                    Text(CommitmentLevel.pickerFootnote)
                }

                if !check.alternatives.isEmpty {
                    Section("Want more time?") {
                        ForEach(check.alternatives, id: \.self) { alternative in
                            Button {
                                model.choose(alternative.goal, from: check)
                                recheck()
                            } label: {
                                Text(alternative.label)
                            }
                        }
                    }
                }

                Section {
                    if check.verdict != .refused {
                        Button("Start my plan") { start(insisted: false) }
                            .font(.headline)
                    }
                } footer: {
                    Text(SafetyText.safetyLine)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Your goal")
        .navigationBarTitleDisplayMode(.inline)
        .task { recheck() }
    }

    private func recheck() {
        check = model.checkGoal()
    }

    private func start(insisted: Bool) {
        CoachHeartRateStore.save(model.heartRate)
        if model.heartRate.enabled {
            Task { _ = await HeartRateMonitor.turnOn() }
        }
        model.remember()
        CoachAnswerStore(context: modelContext).save(model.saved)
        AppOpens.clearLongBreak()
        let service = CoachService(context: modelContext, unit: model.intake.distanceUnit)
        let (_, update) = service.startPlan(
            intake: model.intake,
            goal: model.intake.goal,
            level: model.level,
            insisted: insisted,
            savedGoal: model.savedGoal,
            savedGoalEarliest: model.savedGoalEarliest
        )
        onStart(update)
    }

    private func icon(for verdict: GoalVerdict) -> String {
        switch verdict {
        case .green: "checkmark.circle.fill"
        case .amber: "exclamationmark.circle.fill"
        case .red: "flag.checkered"
        case .refused: "pause.circle.fill"
        }
    }

    /// Red is kept for heart rate and Discard. A big goal is the accent like any other goal; only a
    /// goal on hold is orange.
    private func tint(for verdict: GoalVerdict) -> Color {
        switch verdict {
        case .green, .amber, .red: .accentColor
        case .refused: .orange
        }
    }
}
