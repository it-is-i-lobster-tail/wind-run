//
//  BuildSetupView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// Coach setup on one form: where the runner is, the event and its date, run days and easy weeks, with the
/// timeline under it redrawn on every change (the owner, 2026-10-28).
struct BuildSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var model: BuildSetupModel
    @State private var confirmsDiscard = false
    let onStart: (BuildSettings, SavedBuildAnswers) -> Void

    init(saved: SavedBuildAnswers?, unit: DistanceUnit, onStart: @escaping (BuildSettings, SavedBuildAnswers) -> Void) {
        _model = State(initialValue: BuildSetupModel(saved: saved, unit: unit))
        self.onStart = onStart
    }

    private var unit: DistanceUnit { model.unit }

    var body: some View {
        NavigationStack {
            Form {
                whereYouAre
                whereYouAreGoing
                runDays
                easyWeeks
                timeline
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Build distance")
            .navigationBarTitleDisplayMode(.inline)
            .traceScreen("Coach setup")
            // The plan's choices, never the runner's distances, climb or dates.
            .onChange(of: model.event) { _, event in Trace.changed("Coach setup", "Event", to: event.rawValue) }
            .onChange(of: model.goalDate) { _, _ in Trace.changed("Coach setup", "Goal date", to: "changed") }
            .onChange(of: model.plansEasyWeeks) { _, plans in Trace.changed("Coach setup", "Easy weeks", to: plans ? "Plan them for me" : "I'll add them") }
            .onChange(of: model.easySpacing) { _, spacing in Trace.changed("Coach setup", "Easy week spacing", to: spacing) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Trace.tap("Coach setup", "Cancel", ["changed": model.hasChanges])
                        if model.hasChanges { confirmsDiscard = true } else { dismiss() }
                    }
                }
            }
            // A long form: a stray swipe down doesn't throw the answers away.
            .guardsUnsavedChanges(model.hasChanges, asking: $confirmsDiscard, screen: "Coach setup") { dismiss() }
            // A glass bar: the form scrolls under it.
            .safeAreaBar(edge: .bottom) {
                VStack(spacing: 6) {
                    if let problem = model.startProblem {
                        Text(problem)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        Trace.tap("Coach setup", "Start my plan", ["event": model.event.rawValue, "runDays": model.settings.runDays.count])
                        onStart(model.settings, model.answers)
                        dismiss()
                    } label: {
                        Text("Start my plan").frame(maxWidth: .infinity)
                    }
                    .prominentAccentButton()
                    .font(.headline)
                    .controlSize(.extraLarge)
                    .disabled(!model.canStart)
                }
                .padding()
            }
            .task {
                model.fill(recent: await RecentRunsReader.recentRuns(in: modelContext))
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    // MARK: Sections

    private var whereYouAre: some View {
        Section {
            NumberRow(title: "Weekly mileage now", value: $model.currentDistance, unit: unit.symbol)
            NumberRow(title: "Weekly climb now", value: $model.currentClimb, unit: model.climbSymbol, whole: true)
        } header: {
            Text("Where you are")
        } footer: {
            Text((model.filledFromRuns
                ? "Filled in from your last 4 weeks of runs in Wind Run and Apple Health. Change it if it's off."
                : "Your usual week of running lately, and how much it climbs.")
                + " Once your plan starts, the runs you record with Wind Run count toward each week.")
        }
    }

    private var whereYouAreGoing: some View {
        Section {
            Picker("Event", selection: $model.event) {
                ForEach(GoalEvent.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            // The event's own distance, shown but fixed; only a custom event takes a distance of its own.
            if model.event == .custom {
                NumberRow(title: "Distance", value: $model.customDistance, unit: unit.symbol, maxDigits: BuildSetupModel.customDistanceDigits)
            } else {
                LabeledContent("Distance", value: unit.weekly(model.settings.goal.meters))
            }
            NumberRow(title: "Event climb", value: $model.eventClimb, unit: model.climbSymbol, whole: true, maxDigits: BuildSetupModel.eventClimbDigits)
            DatePicker("Goal date", selection: $model.goalDate, in: model.goalDateRange, displayedComponents: .date)
        } header: {
            Text("Where you're going")
        } footer: {
            Text(model.event == .custom && model.settings.goal.meters <= 0 ? "Enter your event's distance. Leave climb at 0 for a flat race." : "Leave climb at 0 for a flat race.")
        }
    }

    private var runDays: some View {
        Section {
            HStack(spacing: 6) {
                ForEach(Weekday.mondayFirst, id: \.self) { day in
                    DayChip(day: day, on: model.settings.runDays.contains(day), canTurnOff: model.settings.runDays.count > 1) { model.toggle(day) }
                }
            }
            LongRunPicker(settings: $model.settings)
            CoachPaceSettings(settings: $model.settings, unit: unit)
        } header: {
            Text("Run days")
        } footer: {
            Text(DayChip.footer(runs: model.settings.runDays.count))
        }
    }

    private var easyWeeks: some View {
        Section {
            Picker("Easy weeks", selection: $model.plansEasyWeeks) {
                Text("Plan them for me").tag(true)
                Text("I'll add them").tag(false)
            }
            .pickerStyle(.segmented)
            if model.plansEasyWeeks {
                Stepper("Every \(ordinal(model.easySpacing)) week", value: $model.easySpacing, in: EasyWeekSchedule.spacing)
            } else {
                EasyWeekList(timeline: model.timeline, schedule: model.settings.easyWeeks) { model.toggleEasyWeek($0) }
            }
        } header: {
            Text("Easy weeks")
        } footer: {
            Text(model.plansEasyWeeks
                ? "An easy week is 25% under the week before it. Your event week is always one."
                : "Tap a week in the timeline, or choose from the list, to make it an easy week. Your event week is always one.")
        }
    }

    private var timeline: some View {
        let timeline = model.timeline
        let summary = BuildTimelineSummary(timeline: timeline, unit: unit, event: model.event, calendar: model.calendar)
        return Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.headline)
                    .font(.title3.weight(.bold))
                Text(summary.subheadline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            BuildTimelineChart(timeline: timeline, unit: unit, onTapWeek: model.plansEasyWeeks ? nil : { model.toggleEasyWeek($0) })
                .padding(.vertical, 4)
            ForEach(summary.rows, id: \.0) { row in
                LabeledContent(row.0, value: row.1)
            }
            if let note = summary.ambitiousNote {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ambitious goal").font(.headline)
                        Text(note)
                    }
                } icon: {
                    Image(systemName: "flag.checkered")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Your timeline")
        } footer: {
            Text(SafetyText.safetyLine)
        }
    }

    private func ordinal(_ number: Int) -> String {
        "\(number)" + (number == 2 ? "nd" : number == 3 ? "rd" : "th")
    }
}

/// A number the runner types, with its unit after it. The number reaches `value` as it's typed, so the timeline
/// follows along, and the field takes no more than `maxDigits` before the decimal point.
struct NumberRow: View {
    let title: String
    @Binding var value: Double
    let unit: String
    /// Whole numbers only, for climb.
    var whole = false
    var maxDigits: Int?

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, text: $text)
                    .focused($focused)
                    .keyboardType(whole ? .numberPad : .decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { text = formatted(value) }
        .onChange(of: text) { _, typed in
            let kept = Self.kept(typed, whole: whole, maxDigits: maxDigits)
            guard kept == typed else {
                text = kept
                return
            }
            // Only typing changes the number. The text shown when the row appears, or after numbers are filled
            // in from runs, isn't an edit, so it doesn't stop setup filling the number in.
            guard focused else { return }
            let typedValue = Double(kept.replacingOccurrences(of: ",", with: ".")) ?? 0
            if typedValue != value { value = typedValue }
        }
        // Numbers filled in from runs while the runner isn't typing, and a tidy number once they're done.
        .onChange(of: value) { _, value in
            if !focused { text = formatted(value) }
        }
        .onChange(of: focused) { _, focused in
            if !focused { text = formatted(value) }
        }
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... (whole ? 0 : 1))).grouping(.never))
    }

    /// What's typed with anything past the limits dropped: digits, one decimal point and one decimal place, and at
    /// most `maxDigits` before the point.
    static func kept(_ typed: String, whole: Bool, maxDigits: Int?) -> String {
        var integer = ""
        // The separator as typed, "." or ",", and the digits after it.
        var point: Character?
        var fraction = ""
        for character in typed {
            if character.isASCII, character.isNumber {
                if point == nil {
                    // A digit typed after a lone 0 (the field starts at 0) takes its place.
                    if integer == "0" {
                        integer = String(character)
                    } else if integer.count < (maxDigits ?? .max) {
                        integer.append(character)
                    }
                } else if fraction.isEmpty {
                    fraction.append(character)
                }
            } else if character == "." || character == ",", !whole, point == nil {
                point = character
            }
        }
        return integer + (point.map(String.init) ?? "") + fraction
    }
}

extension Weekday {
    /// The week as the run-day chips show it, Monday first.
    static let mondayFirst: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
}
