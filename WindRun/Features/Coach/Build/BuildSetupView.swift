//
//  BuildSetupView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// Coach setup on one form: where the runner is, the event and its date, run days and easy weeks, with the
/// timeline under it redrawn on every change (Brendon, 2026-10-28).
struct BuildSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var model: BuildSetupModel
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
            .navigationTitle("Build distance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    onStart(model.settings, model.answers)
                    dismiss()
                } label: {
                    Text("Start my plan").frame(maxWidth: .infinity)
                }
                .prominentAccentButton()
                .font(.headline)
                .controlSize(.extraLarge)
                .disabled(!model.canStart)
                .padding()
            }
            .task {
                model.fill(recent: await RecentRunsReader.recentRuns(in: modelContext))
            }
        }
    }

    // MARK: Sections

    private var whereYouAre: some View {
        Section {
            NumberRow(title: "Weekly mileage now", value: $model.currentDistance, unit: unit.symbol)
            NumberRow(title: "Weekly climb now", value: $model.currentClimb, unit: model.climbSymbol, whole: true)
        } header: {
            Text("Where you are")
        } footer: {
            Text(model.filledFromRuns
                ? "Filled in from your last 4 weeks of runs in Wind Run and Apple Health. Change it if it's off."
                : "Your usual week of running lately, and how much it climbs.")
        }
    }

    private var whereYouAreGoing: some View {
        Section {
            Picker("Event", selection: $model.event) {
                ForEach(GoalEvent.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            if model.event == .custom {
                NumberRow(title: "Distance", value: $model.customDistance, unit: unit.symbol)
            }
            NumberRow(title: "Event climb", value: $model.eventClimb, unit: model.climbSymbol, whole: true)
            NumberRow(title: "Peak week", value: $model.peakDistance, unit: unit.symbol)
            if model.settings.goal.peakWeekClimbMeters > 0 || model.settings.goal.climbMeters > 0 {
                NumberRow(title: "Peak week climb", value: $model.peakClimb, unit: model.climbSymbol, whole: true)
            }
            DatePicker("Goal date", selection: $model.goalDate, in: model.goalDateRange, displayedComponents: .date)
        } header: {
            Text("Where you're going")
        } footer: {
            Text("The peak week is 1.5 times the event's distance and climb. Change it if you want to build to more or less. Leave climb at 0 for a flat race.")
        }
    }

    private var runDays: some View {
        Section {
            HStack(spacing: 6) {
                ForEach(Weekday.mondayFirst, id: \.self) { day in
                    DayChip(day: day, on: model.settings.runDays.contains(day)) { model.toggle(day) }
                }
            }
        } header: {
            Text("Run days")
        } footer: {
            let count = model.settings.runDays.count
            Text("\(count) \(count == 1 ? "run" : "runs") a week. Only the week's total matters, so you can change this any time.")
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
            }
        } header: {
            Text("Easy weeks")
        } footer: {
            Text(model.plansEasyWeeks
                ? "An easy week is 25% under the week before it. Your event week is always one."
                : "Tap a week in the timeline to make it an easy week. Your event week is always one.")
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

/// A number the runner types, with its unit after it.
struct NumberRow: View {
    let title: String
    @Binding var value: Double
    let unit: String
    /// Whole numbers only, for climb.
    var whole = false

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField(title, value: $value, format: .number.precision(.fractionLength(0 ... (whole ? 0 : 1))))
                    .keyboardType(whole ? .numberPad : .decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 100)
                Text(unit)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension Weekday {
    /// The week as the run-day chips show it, Monday first.
    static let mondayFirst: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
}
