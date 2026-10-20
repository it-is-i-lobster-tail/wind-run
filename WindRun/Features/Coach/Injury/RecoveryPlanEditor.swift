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

    init(reportID: UUID, actions: CoachActions) {
        self.reportID = reportID
        self.actions = actions
        let current = actions.state()?.injuries.first { $0.id == reportID }?.recoveryPlan
        _settings = State(initialValue: current ?? .standard)
        isNew = current == nil
    }

    private var preview: [RecoveryWeekPreview] {
        guard let state = actions.state() else { return [] }
        return CoachEngine.previewRecovery(settings, reportID: reportID, state: state)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $settings.restWeeks, in: 0...8) {
                        LabeledContent("No running", value: CoachFormat.weeks(settings.restWeeks))
                    }
                    Stepper(value: $settings.reducedWeeks, in: 1...8) {
                        LabeledContent("Easy running", value: CoachFormat.weeks(settings.reducedWeeks))
                    }
                    PercentStepper(title: "Of your usual week", share: $settings.reducedShare)
                } header: {
                    Text("Your recovery")
                } footer: {
                    Text("The usual week is your running before the injury. Make it faster or slower whenever you like; it's your call.")
                }

                RampSection(step: $settings.rampStep)

                Section("Week by week") {
                    let weeks = preview
                    if weeks.isEmpty {
                        ForEach(RecoveryOutline.weeks(rest: settings.restWeeks, reduced: settings.reducedWeeks, share: settings.reducedShare, step: settings.rampStep), id: \.self) { Text($0) }
                    } else {
                        ForEach(weeks, id: \.weekNumber) { week in
                            LabeledContent(week.label, value: volumeText(week))
                        }
                    }
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

    private func volumeText(_ week: RecoveryWeekPreview) -> String {
        guard week.volume > 0, let state = actions.state() else { return "" }
        return CoachFormat.amount(week.volume, in: state.volumeUnit, unit: unit)
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

    let reportID: UUID
    let actions: CoachActions

    @State private var settings: ReturnSettings
    private let isNew: Bool

    init(reportID: UUID, actions: CoachActions) {
        self.reportID = reportID
        self.actions = actions
        let report = actions.state()?.injuries.first { $0.id == reportID }
        _settings = State(initialValue: report?.returnPlan ?? ReturnSettings.suggested(for: report))
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

                Section("Week by week") {
                    ForEach(RecoveryOutline.weeks(rest: 0, reduced: settings.weeks, share: settings.share, step: settings.rampStep), id: \.self) { Text($0) }
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

/// A plain outline of the weeks a recovery gives, by share of the usual week.
enum RecoveryOutline {
    static func weeks(rest: Int, reduced: Int, share: Double, step: Double?) -> [String] {
        var lines: [String] = []
        for _ in 0..<max(0, rest) {
            lines.append("Week \(lines.count + 1): no running")
        }
        for _ in 0..<max(1, reduced) {
            lines.append("Week \(lines.count + 1): \(CoachFormat.percent(share))")
        }
        if let step, step > 0 {
            var level = share + step
            while level < 0.995, lines.count < 30 {
                lines.append("Week \(lines.count + 1): \(CoachFormat.percent(level))")
                level += step
            }
        }
        lines.append("Week \(lines.count + 1): back to your usual week")
        return lines
    }
}

extension ReturnSettings {
    /// AD-14c's starting point until the engine provides its own: two return weeks, 50% of the usual
    /// week after a pause of 4 weeks or less and 30% after a longer one, jog/walk for runners who
    /// couldn't run 30 minutes non-stop before.
    static func suggested(for report: InjuryReport?, now: Date = .now, calendar: Calendar = .current) -> ReturnSettings {
        let pauseStart = report?.lastRunBeforePause ?? report?.pauseStart ?? report?.reportedAt ?? now
        let days = calendar.dateComponents([.day], from: pauseStart, to: now).day ?? 0
        let form: ReturnForm = report?.baseline.ranThirtyMinutesNonStop == false ? .jogWalk : .jogging
        return ReturnSettings(weeks: 2, form: form, share: days <= 28 ? 0.5 : 0.3, rampStep: 0.25)
    }
}
