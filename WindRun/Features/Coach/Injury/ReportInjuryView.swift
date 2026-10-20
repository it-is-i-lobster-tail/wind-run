//
//  ReportInjuryView.swift
//  Wind Run
//

import SwiftUI

/// Report injury (AD-13): how bad it is and, optionally, where. The coach never diagnoses; the
/// level decides what the plan does next. An Intense report goes on to the medical question.
struct ReportInjuryView: View {
    @Environment(\.dismiss) private var dismiss

    let origin: InjuryOrigin
    let runID: UUID?
    let actions: CoachActions
    /// Opens the recovery plan once the runner says they're cleared to keep training.
    let openRecoveryPlan: (UUID) -> Void

    @State private var level: InjuryLevel?
    @State private var area: InjuryArea?
    /// Set after an Intense report is saved, to ask the medical question.
    @State private var intenseReportID: UUID?

    private var openReports: [InjuryReport] { actions.state()?.openInjuries ?? [] }

    var body: some View {
        NavigationStack {
            Group {
                if let intenseReportID {
                    clearance(reportID: intenseReportID)
                } else {
                    report
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: The report

    private var report: some View {
        Form {
            if !openReports.isEmpty {
                OpenInjuriesSection(reports: openReports) { report, newLevel in
                    actions.perform { state, runs, now, calendar in
                        CoachEngine.answerInjury(.level(newLevel), reportID: report.id, state: state, runs: runs, now: now, calendar: calendar)
                    }
                }
            }

            Section {
                ForEach(InjuryLevel.allCases, id: \.self) { choice in
                    Button {
                        level = choice
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(choice.name)
                                    .font(.headline)
                                Text(choice.detail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
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
                    .accessibilityAddTraits(level == choice ? .isSelected : [])
                }
            } header: {
                Text(openReports.isEmpty ? "How bad is it?" : "Something new: how bad is it?")
            } footer: {
                Text(InjuryReport.helpText)
            }

            Section {
                Picker("Where", selection: $area) {
                    Text("Rather not say").tag(InjuryArea?.none)
                    ForEach(InjuryArea.allCases, id: \.self) { Text($0.name.capitalizedFirst).tag(InjuryArea?.some($0)) }
                }
            } footer: {
                Text("Optional. It only changes which routes and sessions the coach suggests.")
            }

            Section {
                EmptyView()
            } footer: {
                Text(SafetyText.safetyLine)
            }
        }
        .navigationTitle("Report injury")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Report", action: save)
                    .disabled(level == nil)
            }
        }
    }

    private func save() {
        guard let level else { return }
        let before = Set(openReports.map(\.id))
        let update = actions.perform { state, runs, now, calendar in
            CoachEngine.reportInjury(level: level, area: area, origin: origin, runID: runID, state: state, runs: runs, now: now, calendar: calendar)
        }
        let newReport = update?.state.injuries.last { !before.contains($0.id) }
        if level == .intense, let newReport {
            intenseReportID = newReport.id
        } else {
            dismiss()
        }
    }

    // MARK: AD-13b's medical question

    private func clearance(reportID: UUID) -> some View {
        Form {
            Section {
                ForEach(ClearanceAnswer.allCases, id: \.self) { answer in
                    Button(answer.name) {
                        actions.perform { state, runs, now, calendar in
                            CoachEngine.answerInjury(.clearance(answer), reportID: reportID, state: state, runs: runs, now: now, calendar: calendar)
                        }
                        dismiss()
                        if answer == .yes { openRecoveryPlan(reportID) }
                    }
                }
            } header: {
                Text("Are you medically cleared to keep training?")
            } footer: {
                Text("If you're not sure, your plan pauses until a doctor or physio says you can train. You can answer again at any time.")
            }
        }
        .navigationTitle("Report injury")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Later") { dismiss() }
            }
        }
    }
}

/// Reports that are still open, with a way to move each to another level (AD-13e).
private struct OpenInjuriesSection: View {
    let reports: [InjuryReport]
    let changeLevel: (InjuryReport, InjuryLevel) -> Void

    var body: some View {
        Section {
            ForEach(reports) { report in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(report.areaName.capitalizedFirst)
                        Text("Reported \(report.reportedAt.formatted(.dateTime.month().day()))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu(report.level.name) {
                        ForEach(InjuryLevel.allCases, id: \.self) { level in
                            Button(level.name) { changeLevel(report, level) }
                                .disabled(level == report.level)
                        }
                    }
                }
            }
        } header: {
            Text("Already reported")
        } footer: {
            Text("Better or worse? Change its level and the plan follows.")
        }
    }
}
