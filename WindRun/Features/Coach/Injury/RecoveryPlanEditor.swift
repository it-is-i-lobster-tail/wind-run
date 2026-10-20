//
//  RecoveryPlanEditor.swift
//  Wind Run
//

import SwiftUI

/// The recovery plan after an Intense report (AD-14b): weeks off, weeks of reduced running, then a
/// step-by-step build back to the usual week. The runner can make it faster or slower at any time.
struct RecoveryPlanEditor: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    let reportID: UUID
    let actions: CoachActions

    @State private var settings: RecoveryPlanSettings
    private let isNew: Bool
    private let isLadder: Bool

    init(reportID: UUID, actions: CoachActions) {
        self.reportID = reportID
        self.actions = actions
        let report = actions.state()?.injuries.first { $0.id == reportID }
        _settings = State(initialValue: report?.recoveryPlan ?? .standard)
        isNew = report?.recoveryPlan == nil
        isLadder = report?.baseline.isLadder ?? false
    }

    private var state: CoachState? { actions.state() }
    private var report: InjuryReport? { state?.injuries.first { $0.id == reportID } }

    var body: some View {
        NavigationStack {
            Form {
                if let report, let state {
                    Section {
                        Text(InjuryCoach.recoveryOffer(report, state: state))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section {
                    Stepper(value: $settings.restWeeks, in: 0...8) {
                        LabeledContent("No running", value: CoachFormat.weeks(settings.restWeeks))
                    }
                    if isLadder {
                        Stepper(value: $settings.ladderStepsBack, in: 0...5) {
                            LabeledContent("Restart", value: settings.ladderStepsBack == 0 ? "Same step" : "\(InjuryCoach.stepsBackName(settings.ladderStepsBack)) back")
                        }
                    } else {
                        Stepper(value: $settings.reducedWeeks, in: 1...8) {
                            LabeledContent("Easy running", value: CoachFormat.weeks(settings.reducedWeeks))
                        }
                        PercentStepper(title: "Of your usual week", share: $settings.reducedShare)
                    }
                } header: {
                    Text("Your recovery")
                } footer: {
                    Text("The usual week is your running before the injury. Make it faster or slower whenever you like; it's your call.")
                }

                if !isLadder {
                    RampSection(step: $settings.rampStep)
                }

                if let state {
                    PreviewSection(weeks: InjuryCoach.previewRecovery(settings, reportID: reportID, state: state), unit: unit)
                }
            }
            .navigationTitle("Recovery plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isNew ? "Later" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Start" : "Save", action: save)
                }
            }
        }
    }

    private func save() {
        let settings = settings
        actions.perform { state, runs, now, calendar in
            CoachEngine.setRecoveryPlan(settings, reportID: reportID, state: state, runs: runs, now: now, calendar: calendar)
        }
        dismiss()
    }
}

/// How the runner comes back after a Severe pause (AD-14c): return weeks of easy jogging or
/// jog/walk at reduced running, then a build back to the usual week. Faster or slower is up to them.
struct ReturnEditor: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    let reportID: UUID
    let actions: CoachActions

    @State private var settings: ReturnSettings
    private let isNew: Bool

    init(reportID: UUID, actions: CoachActions) {
        self.reportID = reportID
        self.actions = actions
        let state = actions.state()
        let report = state?.injuries.first { $0.id == reportID }
        // The engine's AD-14c defaults: the share by the pause's length, the form by whether they ran 30 minutes non-stop.
        let seeded = report?.returnPlan
            ?? state.map { InjuryCoach.defaultReturn(reportID: reportID, state: $0, now: .now, calendar: .current) }
            ?? ReturnSettings(form: .jogging, share: 0.5, rampStep: 0.25)
        _settings = State(initialValue: seeded)
        isNew = report?.returnPlan == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $settings.weeks, in: 1...6) {
                        LabeledContent("Return weeks", value: CoachFormat.weeks(settings.weeks))
                    }
                    Picker("Running", selection: $settings.form) {
                        ForEach(ReturnForm.allCases, id: \.self) { Text($0.name).tag($0) }
                    }
                    PercentStepper(title: "Of your usual week", share: $settings.share)
                } header: {
                    Text("Coming back")
                } footer: {
                    Text(settings.form == .jogWalk
                        ? "Jog/walk sessions last 20 to 30 minutes: 2 minutes jogging and 2 walking, then 3 and 1. Make it faster or slower whenever you like; it's your call."
                        : "Easy jogging at a pace you could chat at. Make it faster or slower whenever you like; it's your call.")
                }

                RampSection(step: $settings.rampStep)

                if let state = actions.state() {
                    PreviewSection(weeks: InjuryCoach.previewReturn(settings, reportID: reportID, state: state, now: .now, calendar: .current), unit: unit)
                }
            }
            .navigationTitle("Back to running")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isNew ? "Later" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Start" : "Save", action: save)
                }
            }
        }
    }

    private func save() {
        let settings = settings
        actions.perform { state, runs, now, calendar in
            CoachEngine.setReturn(settings, reportID: reportID, state: state, runs: runs, now: now, calendar: calendar)
        }
        dismiss()
    }
}

/// The weeks a recovery or return gives, from the engine's preview. A capped week is held below its
/// share to stay inside the weekly limits.
private struct PreviewSection: View {
    let weeks: [RecoveryWeekPreview]
    let unit: DistanceUnit

    var body: some View {
        Section {
            ForEach(weeks, id: \.weekNumber) { week in
                LabeledContent {
                    VStack(alignment: .trailing, spacing: 2) {
                        if week.volume > 0 {
                            Text(CoachFormat.amount(week.volume, in: week.volumeUnit, unit: unit))
                        }
                        if week.capped {
                            Text("Held to the limit")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                } label: {
                    Text(week.label)
                }
            }
        } header: {
            Text("Week by week")
        } footer: {
            if weeks.contains(where: \.capped) {
                Text("Weeks held to the limit stay a little under their share, so you never build faster than the plan's safety limits allow.")
            }
        }
    }
}

/// The build back after reduced running: a step each week, or straight back to the usual week.
private struct RampSection: View {
    @Binding var step: Double?

    var body: some View {
        Section {
            Toggle("Build back step by step", isOn: Binding(
                get: { step != nil },
                set: { step = $0 ? 0.25 : nil }
            ))
            if let current = step {
                Stepper(value: Binding(
                    get: { current },
                    set: { step = min(max($0, RecoveryPlanSettings.rampRange.lowerBound), RecoveryPlanSettings.rampRange.upperBound) }
                ), in: RecoveryPlanSettings.rampRange, step: RecoveryPlanSettings.rampIncrement) {
                    LabeledContent("Each week", value: "+\(CoachFormat.percent(current))")
                }
            }
        } footer: {
            Text(step == nil ? "Straight back to your usual week after the reduced weeks." : "Each week adds this much until you're back to your usual week.")
        }
    }
}

/// A share of the usual week, 10% to 90% in steps of 10.
private struct PercentStepper: View {
    let title: String
    @Binding var share: Double

    var body: some View {
        Stepper(value: Binding(
            get: { share },
            set: { share = (min(max($0, RecoveryPlanSettings.shareRange.lowerBound), RecoveryPlanSettings.shareRange.upperBound) * 10).rounded() / 10 }
        ), in: RecoveryPlanSettings.shareRange, step: RecoveryPlanSettings.shareStep) {
            LabeledContent(title, value: CoachFormat.percent(share))
        }
    }
}
