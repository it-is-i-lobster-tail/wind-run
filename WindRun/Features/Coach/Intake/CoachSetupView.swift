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

/// The realism check for the goal, with the coach's message, alternatives, and the way to start.
struct GoalCheckView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var model: CoachIntakeModel
    let onStart: (CoachUpdate) -> Void

    @State private var check: GoalCheck?
    @State private var isConfirmingInsist = false

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
                    Section("Other ways to get there") {
                        ForEach(check.alternatives, id: \.self) { alternative in
                            Button {
                                model.intake.goal = alternative.goal
                                recheck()
                            } label: {
                                Text(alternative.label)
                            }
                        }
                    }
                }

                Section {
                    switch check.verdict {
                    case .green, .amber:
                        Button("Start my plan") { start(insisted: false) }
                            .font(.headline)
                    case .red:
                        if check.canInsist {
                            Button("Train for it anyway") { isConfirmingInsist = true }
                        }
                    case .refused:
                        EmptyView()
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
        .confirmationDialog("I understand this isn't recommended.", isPresented: $isConfirmingInsist, titleVisibility: .visible) {
            Button("Train for it anyway") { start(insisted: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The plan keeps every safety limit and plans walk breaks from the start.")
        }
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
        let (_, update) = service.startPlan(intake: model.intake, goal: model.intake.goal, level: model.level, insisted: insisted)
        onStart(update)
    }

    private func icon(for verdict: GoalVerdict) -> String {
        switch verdict {
        case .green: "checkmark.circle.fill"
        case .amber: "exclamationmark.circle.fill"
        case .red: "xmark.circle.fill"
        case .refused: "hand.raised.fill"
        }
    }

    /// Red is kept for heart rate and Discard, so a goal that isn't recommended is orange too; its
    /// icon and words set it apart from a stretch.
    private func tint(for verdict: GoalVerdict) -> Color {
        switch verdict {
        case .green: .accentColor
        case .amber, .red, .refused: .orange
        }
    }
}
