//
//  CoachSetupView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// Coach setup: the engine's questions one screen at a time, then the goal check.
struct CoachSetupView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var model: CoachIntakeModel
    @State private var isCheckingGoal = false
    let onStart: (CoachUpdate) -> Void

    init(flavor: CoachGoal, unit: DistanceUnit, onStart: @escaping (CoachUpdate) -> Void) {
        _model = State(initialValue: CoachIntakeModel(flavor: flavor, unit: unit))
        self.onStart = onStart
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(model.step.title)
                        .font(.title2.weight(.semibold))
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                } footer: {
                    if !model.step.isRequired {
                        Text("Optional.")
                    }
                }

                IntakeStepView(model: model)

                if let skipText = model.step.skipText, !model.intake.isAnswered(model.step) {
                    Section {
                        Text(skipText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .animation(.default, value: model.position)
            .navigationTitle("Step \(model.position + 1) of \(model.steps.count)")
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
        }
    }

    private var controls: some View {
        HStack(spacing: LayoutMetrics.compactSpacing) {
            if model.position > 0 {
                Button("Back") { model.back() }
                    .buttonStyle(.glass)
            }
            Spacer()
            Button(model.isLastStep ? "Check my goal" : nextTitle) {
                if model.isLastStep {
                    model.settleShownAnswer()
                    isCheckingGoal = true
                } else {
                    model.next()
                }
            }
            .prominentAccentButton()
            .disabled(!model.canContinue)
        }
        .padding()
    }

    /// "Skip" when a skippable question has no answer yet.
    private var nextTitle: String {
        let step = model.step
        return step.canSkip && !model.intake.isAnswered(step) && step.isRequired ? "Skip" : "Next"
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
        if model.heartRate.device != .off {
            Task { _ = await HeartRateMonitor.turnOn() }
        }
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
