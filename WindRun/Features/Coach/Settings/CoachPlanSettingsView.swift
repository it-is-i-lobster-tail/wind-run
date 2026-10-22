//
//  CoachPlanSettingsView.swift
//  Wind Run
//

import SwiftUI

/// Plan settings: the level, run days and times, height and weight, heart rate, and stopping the plan.
/// Heart-rate settings are kept on this device, apart from the plan.
struct CoachPlanSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let actions: CoachActions
    let editRecovery: (CoachSheet) -> Void

    @State private var level: CommitmentLevel
    @State private var runDays: Set<Weekday>
    @State private var weekdayMaxSeconds: Double?
    @State private var weekendMaxSeconds: Double?
    @State private var longRunDay: Weekday?
    @State private var heightCentimeters: Double?
    @State private var weightKilograms: Double?
    @State private var heartRate = CoachHeartRateStore.load()
    @State private var confirmsStop = false

    private let assessment: RunnerAssessment?
    private let recoveries: [InjuryReport]
    /// For the heart-rate numbers, which also learn from the runner's runs. Worked out here, never stored.
    private let state: CoachState?
    private let runs: [LoggedRun]

    init(actions: CoachActions, editRecovery: @escaping (CoachSheet) -> Void) {
        self.actions = actions
        self.editRecovery = editRecovery
        let state = actions.state()
        self.state = state
        runs = state == nil ? [] : actions.service.loggedRuns()
        assessment = state?.assessment
        _level = State(initialValue: state?.level ?? .gentle)
        _runDays = State(initialValue: state?.intake.runDays ?? [])
        _weekdayMaxSeconds = State(initialValue: state?.intake.weekdayMaxSeconds)
        _weekendMaxSeconds = State(initialValue: state?.intake.weekendMaxSeconds)
        _longRunDay = State(initialValue: state?.intake.longRunDay)
        _heightCentimeters = State(initialValue: state?.intake.heightCentimeters)
        _weightKilograms = State(initialValue: state?.intake.weightKilograms)
        recoveries = (state?.openInjuries ?? []).filter { $0.recoveryPlan != nil || $0.returnPlan != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !recoveries.isEmpty {
                    Section {
                        ForEach(recoveries) { report in
                            Button {
                                dismiss()
                                editRecovery(report.returnPlan != nil ? .returnPlan(reportID: report.id) : .recoveryPlan(reportID: report.id))
                            } label: {
                                LabeledContent("Recovery for \(report.areaName)", value: "Change")
                            }
                        }
                    } footer: {
                        Text("Make your recovery faster or slower.")
                    }
                }

                levelSection

                Section {
                    WeekdayPicker(days: $runDays)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                } header: {
                    Text("Run days")
                } footer: {
                    Text("Pick every day you could run. The coach puts rest days in for you.")
                }
                Section("Longest time for a run") {
                    MinutesStepper(title: "On a weekday", seconds: $weekdayMaxSeconds, range: 20...240)
                    MinutesStepper(title: "On a weekend", seconds: $weekendMaxSeconds, range: 20...300)
                }
                if !runDays.isEmpty {
                    Section("Best day for your long run") {
                        Picker("Long run", selection: $longRunDay) {
                            Text("Any").tag(Weekday?.none)
                            ForEach(runDays.sorted(), id: \.self) { Text($0.name).tag(Weekday?.some($0)) }
                        }
                    }
                }

                // Setup asks these once; after that they're changed here (Brendon, 2026-10-22).
                Section {
                    BodyFields(heightCentimeters: $heightCentimeters, weightKilograms: $weightKilograms, unit: .current)
                } header: {
                    Text("Height and weight")
                } footer: {
                    Text(BodyFields.footnote)
                }

                HeartRateSettingsSections(settings: $heartRate)
                if heartRate.device != .off, let state {
                    HeartRateNumbersSection(state: state, runs: runs, settings: $heartRate)
                }

                Section {
                    // Not the red destructive style: red is kept for heart rate and Discard.
                    Button("Stop this plan") { confirmsStop = true }
                } footer: {
                    Text("Your runs stay in your history. You can start a new plan at any time.")
                }
            }
            .navigationTitle("Plan settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(runDays.isEmpty)
                }
            }
            .confirmationDialog("Stop this plan?", isPresented: $confirmsStop, titleVisibility: .visible) {
                Button("Stop plan", action: stop)
                Button("Keep my plan", role: .cancel) {}
            } message: {
                Text("The coach stops planning your weeks.")
            }
        }
    }

    private var levelSection: some View {
        Section {
            LevelRows(
                level: $level,
                recommended: assessment?.levels.preset,
                stepBackEveryThird: assessment?.recoveryTier.stepsBackEveryThird ?? false
            )
        } header: {
            Text("Level")
        } footer: {
            Text(CommitmentLevel.pickerFootnote)
        }
    }

    private func save() {
        let previous = CoachHeartRateStore.load()
        CoachHeartRateStore.save(heartRate)
        if heartRate.device != .off, previous.device == .off {
            Task { _ = await HeartRateMonitor.turnOn() }
        }

        guard let state = actions.state() else {
            dismiss()
            return
        }
        if level != state.level {
            let level = level
            actions.perform { state, runs, now, calendar in
                CoachEngine.changeLevel(level, state: state, runs: runs, now: now, calendar: calendar)
            }
        }
        let scheduleChanged = runDays != state.intake.runDays
            || weekdayMaxSeconds != state.intake.weekdayMaxSeconds
            || weekendMaxSeconds != state.intake.weekendMaxSeconds
            || longRunDay != state.intake.longRunDay
        if scheduleChanged {
            let (days, weekday, weekend, long) = (runDays, weekdayMaxSeconds, weekendMaxSeconds, longRunDay.flatMap { runDays.contains($0) ? $0 : nil })
            actions.perform { state, runs, now, calendar in
                CoachEngine.changeSchedule(runDays: days, weekdayMaxSeconds: weekday, weekendMaxSeconds: weekend, longRunDay: long, state: state, runs: runs, now: now, calendar: calendar)
            }
        }
        if heightCentimeters != state.intake.heightCentimeters || weightKilograms != state.intake.weightKilograms {
            let (height, weight) = (heightCentimeters, weightKilograms)
            actions.perform { state, _, now, _ in
                CoachEngine.changeBody(heightCentimeters: height, weightKilograms: weight, state: state, now: now)
            }
            // The next setup starts from these too.
            let answers = CoachAnswerStore(context: modelContext)
            if var saved = answers.load() {
                saved.intake.heightCentimeters = height
                saved.intake.weightKilograms = weight
                saved.intake.markAnswered(.body, at: .now)
                saved.savedAt = .now
                answers.save(saved)
            }
        }
        dismiss()
    }

    private func stop() {
        actions.perform { state, _, now, _ in
            CoachEngine.stopPlan(state: state, now: now)
        }
        dismiss()
    }
}

/// The runner's heart-rate numbers, worked out on this device from their age or a lab-tested
/// maximum (PZ-11, PZ-12). Nothing here is stored with the plan.
private struct HeartRateNumbersSection: View {
    let state: CoachState
    let runs: [LoggedRun]
    @Binding var settings: HeartRateSettings

    var body: some View {
        let zones = RunHeartRate.zones(age: state.assessment.age, settings: settings, runs: runs, state: state, calendar: .current)
        Section {
            LabeledContent("Easy and long runs", value: "Up to \(Int(zones.easyCeiling)) bpm")
            LabeledContent("Tempo", value: "\(Int(zones.thresholdBand.lowerBound))–\(Int(zones.thresholdBand.upperBound)) bpm")
            LabeledContent(zones.maxObserved ? "Maximum" : "Maximum, estimated", value: "\(Int(zones.max)) bpm")
            OptionalNumberField(title: "Lab-tested maximum (bpm)", value: $settings.labMax)
        } header: {
            Text("Your heart-rate numbers")
        } footer: {
            Text(zones.maxObserved
                ? "From your races and all-out runs. A lab-tested maximum replaces it only when it's lower. These numbers stay on this device."
                : "Estimated from your age until your races and all-out runs show more. A lab-tested maximum replaces the estimate only when it's lower. These numbers stay on this device.")
        }
    }
}
