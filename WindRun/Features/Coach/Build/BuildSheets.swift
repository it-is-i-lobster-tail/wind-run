//
//  BuildSheets.swift
//  Wind Run
//

import SwiftData
import SwiftUI

typealias BuildPerform = (@escaping BuildCall) -> Void

/// Report injury (AD-13): how bad it is and, optionally, where. The coach never diagnoses; the level decides what
/// the plan does next. An Intense report goes on to the medical question on the plan screen.
struct BuildReportInjuryView: View {
    @Environment(\.dismiss) private var dismiss

    let perform: BuildPerform
    var runID: UUID?

    @State private var level: InjuryLevel?
    @State private var area: InjuryArea?

    static let helpText = "Muscle soreness that starts hours after a new, longer, faster or hilly run and fades over 1-3 days is normal, not an injury."

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(InjuryLevel.allCases, id: \.self) { choice in
                        Button {
                            // How bad is a health detail, so only that one was picked.
                            Trace.tap("Report injury", "Picked how bad")
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
                    Text("How bad is it?")
                } footer: {
                    Text(Self.helpText)
                }

                Section {
                    Picker("Where", selection: $area) {
                        Text("Rather not say").tag(InjuryArea?.none)
                        ForEach(InjuryArea.allCases, id: \.self) { Text($0.name.capitalizedFirst).tag(InjuryArea?.some($0)) }
                    }
                } footer: {
                    Text("Optional. The coach only uses it in what it says to you.")
                }

                Section {
                    EmptyView()
                } footer: {
                    Text(SafetyText.safetyLine)
                }
            }
            .navigationTitle("Report injury")
            .navigationBarTitleDisplayMode(.inline)
            .traceScreen("Report injury")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Trace.tap("Report injury", "Cancel")
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Report") {
                        Trace.tap("Report injury", "Report")
                        save()
                    }
                        .disabled(level == nil)
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private func save() {
        guard let level else { return }
        let (area, runID) = (area, runID)
        perform { state, runs, now, calendar in
            BuildEngine.reportInjury(level: level, area: area, runID: runID, state: state, runs: runs, now: now, calendar: calendar)
        }
        dismiss()
    }
}

/// Recovery or return weeks after an injury: weeks off, then weeks at a share of the week before it. The runner
/// can make it faster or slower at any time.
struct RecoveryEditor: View {
    @Environment(\.dismiss) private var dismiss

    let report: BuildInjury
    let perform: BuildPerform

    @State private var settings: RecoverySettings
    @State private var confirmsDiscard = false
    private let opened: RecoverySettings

    init(report: BuildInjury, perform: @escaping BuildPerform) {
        self.report = report
        self.perform = perform
        let settings = report.recovery ?? (report.level == .severe ? .severe : .intense)
        opened = settings
        _settings = State(initialValue: settings)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $settings.restWeeks, in: 0 ... 8) {
                        LabeledContent("No running", value: CoachFormat.weeks(settings.restWeeks))
                    }
                    Stepper(value: $settings.reducedWeeks, in: 1 ... 8) {
                        LabeledContent("Easier running", value: CoachFormat.weeks(settings.reducedWeeks))
                    }
                    Stepper(value: $settings.reducedShare, in: RecoverySettings.shareRange, step: RecoverySettings.shareStep) {
                        LabeledContent("Of your week before", value: "\(CoachFormat.percent(settings.reducedShare))%")
                    }
                } header: {
                    Text(report.level == .severe ? "Coming back" : "Your recovery")
                } footer: {
                    Text("Your week before is your running before the injury. After these weeks the plan builds again, never adding more than 10% a week. Make it faster or slower whenever you like; it's your call.")
                }
            }
            .navigationTitle(report.level == .severe ? "Back to running" : "Recovery weeks")
            .navigationBarTitleDisplayMode(.inline)
            .traceScreen("Recovery weeks")
            .onChange(of: settings.restWeeks) { _, weeks in Trace.changed("Recovery weeks", "No running", to: weeks) }
            .onChange(of: settings.reducedWeeks) { _, weeks in Trace.changed("Recovery weeks", "Easier running", to: weeks) }
            .onChange(of: settings.reducedShare) { _, share in Trace.changed("Recovery weeks", "Of your week before", to: share) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Trace.tap("Recovery weeks", "Cancel")
                        if settings != opened { confirmsDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Trace.tap("Recovery weeks", "Save")
                        save()
                    }
                }
            }
            .guardsUnsavedChanges(settings != opened, asking: $confirmsDiscard, screen: "Recovery weeks") { dismiss() }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private func save() {
        let (settings, id) = (RecoverySettings(restWeeks: settings.restWeeks, reducedWeeks: settings.reducedWeeks, reducedShare: settings.reducedShare), report.id)
        perform { state, runs, now, calendar in
            BuildEngine.startRecovery(settings, reportID: id, state: state, runs: runs, now: now, calendar: calendar)
        }
        dismiss()
    }
}

/// Plan settings: run days, easy weeks, heart rate, and stopping the plan. Finished runs stay as
/// they are; the rest of the week is shared over the new run days.
struct BuildPlanSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    let plan: CoachPlan

    @State private var settings: BuildSettings
    @State private var heartRate = CoachHeartRateStore.load()
    @State private var confirmsStop = false
    @State private var confirmsDiscard = false
    private let openedHeartRate = CoachHeartRateStore.load()
    /// The plan as it was when settings opened, for the preview and to see what changed.
    private let original: BuildPlanState?

    private var service: BuildService { BuildService(context: modelContext) }

    init(plan: CoachPlan, state: BuildPlanState?) {
        self.plan = plan
        original = state
        _settings = State(initialValue: state?.settings ?? SavedBuildAnswers().settings(recent: nil, now: .now, calendar: .current))
    }

    private var hasChanges: Bool {
        settings != (original?.settings ?? settings) || heartRate != openedHeartRate
    }

    /// The weeks ahead with the changes so far.
    private var preview: BuildTimeline? {
        guard var state = original else { return nil }
        state.settings = settings
        return BuildEngine.outlook(state, now: .now, calendar: .current)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 6) {
                        ForEach(Weekday.mondayFirst, id: \.self) { day in
                            DayChip(day: day, on: settings.runDays.contains(day), canTurnOff: settings.runDays.count > 1) { toggle(day) }
                        }
                    }
                } header: {
                    Text("Run days")
                } footer: {
                    Text("Runs you've done this week stay. What's left of the week is shared over your new days.\(settings.runDays.count == 1 ? " A plan keeps at least one run day." : "")")
                }

                Section {
                    Picker("Easy weeks", selection: Binding(get: { settings.easyWeeks.isAutomatic }, set: { settings.easyWeeks = $0 ? .standard : .chosen([]) })) {
                        Text("Plan them for me").tag(true)
                        Text("I'll add them").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if case .every(let spacing) = settings.easyWeeks {
                        Stepper("Every \(spacing)\(spacing == 2 ? "nd" : spacing == 3 ? "rd" : "th") week", value: Binding(get: { spacing }, set: { settings.easyWeeks = .every($0) }), in: EasyWeekSchedule.spacing)
                    }
                    if let preview {
                        BuildTimelineChart(timeline: preview, unit: unit, onTapWeek: settings.easyWeeks.isAutomatic ? nil : { number in
                            Trace.tap("Plan settings", "Easy week", ["week": number])
                            toggleEasyWeek(number, count: preview.calendar.count)
                        })
                        .padding(.vertical, 4)
                        if !settings.easyWeeks.isAutomatic {
                            EasyWeekList(timeline: preview, schedule: settings.easyWeeks, from: currentWeek) { toggleEasyWeek($0, count: preview.calendar.count) }
                        }
                    }
                } header: {
                    Text("Easy weeks")
                } footer: {
                    Text(settings.easyWeeks.isAutomatic
                        ? "An easy week is 25% under the week before it. Your event week is always one."
                        : "Tap a week ahead, or choose from the list, to make it an easy week. Your event week is always one.")
                }

                HeartRateSettingsSections(settings: $heartRate)

                Section {
                    // Not the red destructive style: red is kept for heart rate and Discard.
                    Button("Stop this plan") {
                        Trace.tap("Plan settings", "Stop this plan")
                        confirmsStop = true
                    }
                } footer: {
                    Text("Your runs stay in your history. You can start a new plan at any time.")
                }
            }
            .navigationTitle("Plan settings")
            .navigationBarTitleDisplayMode(.inline)
            .traceScreen("Plan settings")
            .onChange(of: settings.easyWeeks.isAutomatic) { _, automatic in
                Trace.changed("Plan settings", "Easy weeks", to: automatic ? "Plan them for me" : "I'll add them")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Trace.tap("Plan settings", "Cancel", ["changed": hasChanges])
                        if hasChanges { confirmsDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Trace.tap("Plan settings", "Save", ["runDays": settings.runDays.count])
                        save()
                    }
                        .disabled(settings.runDays.isEmpty)
                }
            }
            .guardsUnsavedChanges(hasChanges, asking: $confirmsDiscard, screen: "Plan settings") { dismiss() }
            .confirmationDialog("Stop this plan?", isPresented: $confirmsStop, titleVisibility: .visible) {
                Button("Stop plan") {
                    Trace.tap("Plan settings", "Stop this plan?: Stop plan")
                    stop()
                }
                Button("Keep my plan", role: .cancel) {
                    Trace.tap("Plan settings", "Stop this plan?: Keep my plan")
                }
            } message: {
                Text("The coach stops planning your weeks.")
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    /// This week's number: weeks before it are over, so they stay as they were.
    private var currentWeek: Int {
        max(1, original?.planCalendar.number(on: .now, calendar: .current) ?? 1)
    }

    private func toggleEasyWeek(_ number: Int, count: Int) {
        guard number >= currentWeek, number < count else { return }
        settings.easyWeeks = settings.easyWeeks.toggling(number, through: count)
    }

    private func toggle(_ day: Weekday) {
        guard let days = settings.runDays(toggling: day) else { return }
        settings.runDays = days
    }

    private func save() {
        let wasOn = CoachHeartRateStore.load().enabled
        CoachHeartRateStore.save(heartRate)
        // The same switch as Heart rate in Settings, so turning it on asks Health the same way.
        if heartRate.enabled, !wasOn {
            Task { _ = await HeartRateMonitor.turnOn() }
        }
        guard let before = original?.settings else {
            dismiss()
            return
        }
        let settings = settings
        if settings.runDays != before.runDays {
            service.perform(on: plan) { state, runs, now, calendar in
                BuildEngine.changeRunDays(settings.runDays, state: state, runs: runs, now: now, calendar: calendar)
            }
        }
        if settings.easyWeeks != before.easyWeeks {
            service.perform(on: plan) { state, runs, now, calendar in
                BuildEngine.changeEasyWeeks(settings.easyWeeks, state: state, runs: runs, now: now, calendar: calendar)
            }
        }
        dismiss()
    }

    private func stop() {
        service.perform(on: plan) { state, _, now, _ in
            BuildEngine.stop(state, now: now)
        }
        dismiss()
    }
}

/// A run-day chip: the day's first letter, filled in the accent when it's a run day. The whole cell takes the tap,
/// at least 44 points tall, and the last run day stays on with a buzz to say so.
struct DayChip: View {
    let day: Weekday
    let on: Bool
    /// False for the only run day left, which can't be taken off.
    var canTurnOff = true
    let action: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var size = 38.0
    @State private var refused = 0

    var body: some View {
        Button {
            Trace.tap("Run days", day.name, ["wasOn": on])
            if on && !canTurnOff {
                refused += 1
            } else {
                action()
            }
        } label: {
            // Seven fit across a phone, so the circle grows with the text only so far.
            Text(day.shortName.prefix(1))
                .font(.subheadline.weight(.semibold))
                .frame(width: min(size, 44), height: min(size, 44))
                .foregroundStyle(on ? Color.onAccent : Color.primary)
                .background(Circle().fill(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary)))
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
        .sensoryFeedback(.warning, trigger: refused)
        .accessibilityLabel(day.name)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityHint(on && !canTurnOff ? "Your only run day, so it stays on." : "")
    }

    /// "3 runs a week. ...", under the chips in setup.
    static func footer(runs count: Int) -> String {
        count == 1
            ? "1 run a week, the fewest a plan can have. Only the week's total matters, so you can change this any time."
            : "\(count) runs a week. Only the week's total matters, so you can change this any time."
    }
}
