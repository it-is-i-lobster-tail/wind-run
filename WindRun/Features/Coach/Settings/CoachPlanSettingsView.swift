//
//  CoachPlanSettingsView.swift
//  Wind Run
//

import SwiftUI

/// Plan settings: the level, run days and times, heart rate, and stopping the plan.
/// Heart-rate settings are kept on this device, apart from the plan.
struct CoachPlanSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let actions: CoachActions
    let editRecovery: (CoachSheet) -> Void

    @State private var level: CommitmentLevel
    @State private var runDays: Set<Weekday>
    @State private var weekdayMaxSeconds: Double?
    @State private var weekendMaxSeconds: Double?
    @State private var longRunDay: Weekday?
    @State private var heartRate = CoachHeartRateStore.load()
    @State private var confirmsStop = false

    private let assessment: RunnerAssessment?
    private let recoveries: [InjuryReport]

    init(actions: CoachActions, editRecovery: @escaping (CoachSheet) -> Void) {
        self.actions = actions
        self.editRecovery = editRecovery
        let state = actions.state()
        assessment = state?.assessment
        _level = State(initialValue: state?.level ?? .gentle)
        _runDays = State(initialValue: state?.intake.runDays ?? [])
        _weekdayMaxSeconds = State(initialValue: state?.intake.weekdayMaxSeconds)
        _weekendMaxSeconds = State(initialValue: state?.intake.weekendMaxSeconds)
        _longRunDay = State(initialValue: state?.intake.longRunDay)
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

                HeartRateSettingsSections(settings: $heartRate)
                if heartRate.device != .off, let age = assessment?.age {
                    HeartRateNumbersSection(age: age, settings: $heartRate)
                }

                Section {
                    Button("Stop this plan", role: .destructive) { confirmsStop = true }
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
                Button("Stop plan", role: .destructive, action: stop)
            } message: {
                Text("The coach stops planning your weeks.")
            }
        }
    }

    @ViewBuilder
    private var levelSection: some View {
        Section {
            ForEach(CommitmentLevel.allCases, id: \.self) { choice in
                let allowed = assessment?.levels.allows(choice) ?? true
                Button {
                    level = choice
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(choice.name)
                                .font(.headline)
                            Text(choice.summary(stepBackEveryThird: assessment?.recoveryTier.stepsBackEveryThird ?? false))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if !allowed, let locked = assessment?.levels.lockedMessage {
                                Text(locked)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if level == choice {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .foregroundStyle(.primary)
                .disabled(!allowed)
                .opacity(allowed ? 1 : VisualOpacity.standard)
                .accessibilityAddTraits(level == choice ? .isSelected : [])
            }
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
    let age: Int
    @Binding var settings: HeartRateSettings

    var body: some View {
        let zones = CoachEngine.heartRateZones(age: age, settings: settings)
        Section {
            LabeledContent("Easy and long runs", value: "Up to \(Int(zones.easyCeiling)) bpm")
            LabeledContent("Tempo", value: "\(Int(zones.thresholdBand.lowerBound))–\(Int(zones.thresholdBand.upperBound)) bpm")
            LabeledContent(zones.maxObserved ? "Maximum" : "Maximum, estimated", value: "\(Int(zones.max)) bpm")
            OptionalNumberField(title: "Lab-tested maximum (bpm)", value: $settings.labMax)
        } header: {
            Text("Your heart-rate numbers")
        } footer: {
            Text("Estimated from your age. A lab-tested maximum replaces the estimate only when it's lower. These numbers stay on this device.")
        }
    }
}
