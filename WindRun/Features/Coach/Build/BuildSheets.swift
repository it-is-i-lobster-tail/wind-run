//
//  BuildSheets.swift
//  Wind Run
//

import SwiftData
import SwiftUI

typealias BuildPerform = (@escaping (BuildPlanState, [CoachRun], Date, Calendar) -> BuildPlanState) -> Void

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

    init(report: BuildInjury, perform: @escaping BuildPerform) {
        self.report = report
        self.perform = perform
        _settings = State(initialValue: report.recovery ?? (report.level == .severe ? .severe : .intense))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $settings.restWeeks, in: 0 ... 8) {
                        LabeledContent("No running", value: weeks(settings.restWeeks))
                    }
                    Stepper(value: $settings.reducedWeeks, in: 1 ... 8) {
                        LabeledContent("Easier running", value: weeks(settings.reducedWeeks))
                    }
                    Stepper(value: $settings.reducedShare, in: RecoverySettings.shareRange, step: RecoverySettings.shareStep) {
                        LabeledContent("Of your week before", value: "\(Int((settings.reducedShare * 100).rounded()))%")
                    }
                } header: {
                    Text(report.level == .severe ? "Coming back" : "Your recovery")
                } footer: {
                    Text("Your week before is your running before the injury. After these weeks the plan builds again, never adding more than 10% a week. Make it faster or slower whenever you like; it's your call.")
                }
            }
            .navigationTitle(report.level == .severe ? "Back to running" : "Recovery weeks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
    }

    private func weeks(_ count: Int) -> String {
        "\(count) \(count == 1 ? "week" : "weeks")"
    }

    private func save() {
        let (settings, id) = (RecoverySettings(restWeeks: settings.restWeeks, reducedWeeks: settings.reducedWeeks, reducedShare: settings.reducedShare), report.id)
        perform { state, runs, now, calendar in
            BuildEngine.startRecovery(settings, reportID: id, state: state, runs: runs, now: now, calendar: calendar)
        }
        dismiss()
    }
}

/// Plan settings: run days, easy weeks, the peak week, heart rate, and stopping the plan. Finished runs stay as
/// they are; the rest of the week is shared over the new run days.
struct BuildPlanSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    let plan: CoachPlan

    @State private var settings: BuildSettings
    @State private var heartRate = CoachHeartRateStore.load()
    @State private var confirmsStop = false
    /// The plan as it was when settings opened, for the preview and to see what changed.
    private let original: BuildPlanState?

    private var service: BuildService { BuildService(context: modelContext) }

    init(plan: CoachPlan, state: BuildPlanState?) {
        self.plan = plan
        original = state
        _settings = State(initialValue: state?.settings ?? SavedBuildAnswers().settings(recent: nil, now: .now, calendar: .current))
    }

    private var climbStep: Double { unit == .miles ? 0.3048 : 1 }
    private var climbSymbol: String { unit == .miles ? "ft" : "m" }

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
                            DayChip(day: day, on: settings.runDays.contains(day)) { toggle(day) }
                        }
                    }
                } header: {
                    Text("Run days")
                } footer: {
                    Text("Runs you've done this week stay. What's left of the week is shared over your new days.")
                }

                Section {
                    NumberRow(
                        title: "Peak week",
                        value: Binding(get: { settings.goal.peakWeekMeters / unit.meters }, set: { settings.goal.peakWeekMeters = max(0, $0) * unit.meters }),
                        unit: unit.symbol
                    )
                    NumberRow(
                        title: "Peak week climb",
                        value: Binding(get: { settings.goal.peakWeekClimbMeters / climbStep }, set: { settings.goal.peakWeekClimbMeters = max(0, $0) * climbStep }),
                        unit: climbSymbol,
                        whole: true
                    )
                } header: {
                    Text("Peak week")
                } footer: {
                    Text("Later weeks build toward it, never more than 10% a week.")
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
                            guard number < preview.calendar.count else { return }
                            settings.easyWeeks = settings.easyWeeks.toggling(number, through: preview.calendar.count)
                        })
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Easy weeks")
                } footer: {
                    Text(settings.easyWeeks.isAutomatic
                        ? "An easy week is 25% under the week before it. Your event week is always one."
                        : "Tap a week ahead to make it an easy week. Your event week is always one.")
                }

                HeartRateSettingsSections(settings: $heartRate)

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
                        .disabled(settings.runDays.isEmpty)
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

    private func toggle(_ day: Weekday) {
        var days = Set(settings.runDays)
        if days.contains(day) {
            guard days.count > 1 else { return }
            days.remove(day)
        } else {
            days.insert(day)
        }
        settings.runDays = days.sorted()
    }

    private func save() {
        let previous = CoachHeartRateStore.load()
        CoachHeartRateStore.save(heartRate)
        if heartRate.enabled, !previous.enabled {
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
        if settings.goal.peakWeekMeters != before.goal.peakWeekMeters || settings.goal.peakWeekClimbMeters != before.goal.peakWeekClimbMeters {
            let peak = WeekVolume(meters: settings.goal.peakWeekMeters, climb: settings.goal.peakWeekClimbMeters)
            service.perform(on: plan) { state, runs, now, calendar in
                BuildEngine.changePeak(peak, state: state, runs: runs, now: now, calendar: calendar)
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

/// A run-day chip: the day's first letter, filled in the accent when it's a run day.
struct DayChip: View {
    let day: Weekday
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(day.shortName.prefix(1))
                .font(.subheadline.weight(.semibold))
                .frame(width: 38, height: 38)
                .foregroundStyle(on ? Color.onAccent : Color.primary)
                .background(Circle().fill(on ? AnyShapeStyle(.tint) : AnyShapeStyle(.fill.tertiary)))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(day.name)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
