//
//  IntakeStepView.swift
//  Wind Run
//

import SwiftUI

/// The answers for one setup question, as sections of the setup form.
struct IntakeStepView: View {
    @Bindable var model: CoachIntakeModel

    private var unit: DistanceUnit { model.intake.distanceUnit }

    var body: some View {
        switch model.step {
        case .goal: goal
        case .finished:
            Section {
                ChoiceRows(choices: FinishedDistance.allCases, selection: $model.intake.finished, title: \.name)
            } footer: {
                Text("For your \(model.intake.goal.distance.name.lowercased()).")
            }
        case .age:
            Section {
                Picker("Age", selection: $model.age) {
                    Text("Choose").tag(Int?.none)
                    ForEach(18...100, id: \.self) { Text("\($0)").tag(Int?.some($0)) }
                }
                .pickerStyle(.wheel)
            } footer: {
                Text("Coach mode is for adults.")
            }
        case .runs30:
            Section { YesNoRows(answer: $model.intake.runs30Minutes) }
        case .nonStop:
            Section {
                ChoiceRows(choices: NonStopBand.allCases, selection: $model.intake.longestNonStop, title: \.name)
            }
        case .dailyFunction:
            Section {
                ChoiceRows(choices: DailyFunction.allCases, selection: $model.intake.dailyFunction, title: \.name)
            }
        case .briskWalk:
            Section { YesNoRows(answer: $model.intake.walksBriskly30, no: "No") }
        case .history: history
        case .lastFourWeeks:
            RecentRunningSections(recent: $model.intake.lastFourWeeks, unit: unit)
        case .beforeBreak:
            RecentRunningSections(recent: $model.intake.beforeBreak, unit: unit)
        case .easyPace: easyPace
        case .otherTraining:
            OtherTrainingSections(activities: $model.intake.otherTraining, physicalWork: $model.intake.physicalWork)
        case .schedule: schedule
        case .level: level
        case .body: body(unit: unit)
        case .heartRate: heartRate
        case .reasons: reasons
        }
    }

    // MARK: IN-1

    @ViewBuilder
    private var goal: some View {
        Section {
            Picker("Goal", selection: $model.intake.goal.flavor) {
                ForEach(CoachGoal.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            .onChange(of: model.intake.goal.flavor) { _, flavor in
                if !flavor.distances.contains(model.intake.goal.distance) {
                    model.intake.goal.distance = flavor.distances.first ?? .fiveK
                }
                if flavor == .event, model.intake.goal.eventDate == nil {
                    model.intake.goal.eventDate = model.calendar.date(byAdding: .weekOfYear, value: 16, to: model.calendar.startOfDay(for: model.now))
                }
            }
            Picker("Distance", selection: $model.intake.goal.distance) {
                ForEach(model.intake.goal.flavor.distances, id: \.self) { Text($0.name).tag($0) }
            }
        } footer: {
            Text(model.intake.goal.flavor.summary)
        }

        switch model.intake.goal.flavor {
        case .buildDistance:
            if model.intake.goal.distance == .fiveK || model.intake.goal.distance == .tenK {
                Section {
                    Toggle("Run-walk is fine", isOn: $model.intake.goal.runWalk)
                } footer: {
                    Text("Finish the distance with planned walk breaks instead of running it all.")
                }
            }
        case .speedWork:
            Section("Target") {
                Toggle("Strong first time, no set time", isOn: $model.intake.goal.strongFirstTime)
                if !model.intake.goal.strongFirstTime {
                    DurationWheels(seconds: $model.intake.goal.targetSeconds, showsHours: model.intake.goal.distance.isHalfOrLonger)
                }
            }
        case .event:
            Section {
                // Race day is today or later, up to 52 weeks out (RC-12).
                DatePicker(
                    "Race day",
                    selection: Binding(
                        get: { model.intake.goal.eventDate ?? model.now },
                        set: { model.intake.goal.eventDate = $0 }
                    ),
                    in: model.raceDayRange,
                    displayedComponents: .date
                )
                OptionalDuration(title: "Goal time", seconds: $model.intake.goal.targetSeconds, showsHours: true)
                OptionalDuration(title: "Course cut-off", seconds: $model.intake.goal.cutoffSeconds, showsHours: true)
            } header: {
                Text("Race")
            } footer: {
                if model.intake.goal.eventDate == nil {
                    Text("Pick your race day to continue.")
                }
            }
        }
    }

    // MARK: IN-5

    @ViewBuilder
    private var history: some View {
        Section {
            ChoiceRows(choices: RunningHistory.allCases, selection: $model.intake.history, title: \.name)
        }
        if model.intake.history?.asksMonths == true {
            Section("About how many months?") {
                Stepper(
                    "\(Int(model.intake.monthsRunning ?? model.intake.history?.lowMonths ?? 0)) months",
                    value: Binding(
                        get: { model.intake.monthsRunning ?? model.intake.history?.lowMonths ?? 0 },
                        set: { model.intake.monthsRunning = $0 }
                    ),
                    in: 0...12
                )
            }
        }
        Section {
            Toggle("A break of 4 weeks or more lately", isOn: Binding(
                get: { model.intake.breakBeganWeeksAgo != nil },
                set: { model.intake.breakBeganWeeksAgo = $0 ? 4 : nil }
            ))
            if let weeks = model.intake.breakBeganWeeksAgo {
                Stepper("It began \(Int(weeks)) weeks ago", value: Binding(
                    get: { weeks },
                    set: { model.intake.breakBeganWeeksAgo = $0 }
                ), in: 4...104)
            }
        }
        Section("Tick any") {
            Toggle("Raced in the last 12 months", isOn: $model.intake.racedLastYear)
            Toggle("Did interval or tempo sessions in the last 12 months", isOn: $model.intake.sessionsLastYear)
            Toggle("Have done them for a year or more", isOn: $model.intake.sessionsForAYearOrMore)
        }
    }

    // MARK: IN-7

    @ViewBuilder
    private var easyPace: some View {
        Section {
            Toggle("Not sure", isOn: Binding(
                get: { model.intake.easyPace == nil },
                set: { model.intake.easyPace = $0 ? nil : 390 }
            ))
            if model.intake.easyPace != nil {
                PaceWheels(secondsPerKilometer: $model.intake.easyPace, unit: unit)
            }
        } footer: {
            Text("Easy means you could talk in full sentences.")
        }
        RaceResultSection(result: $model.intake.race, unit: unit, now: model.now)
    }

    // MARK: IN-12

    @ViewBuilder
    private var schedule: some View {
        Section {
            WeekdayPicker(days: $model.intake.runDays)
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        } footer: {
            Text("Pick every day you could run. The coach puts rest days in for you.")
        }
        Section("Longest time for a run") {
            MinutesStepper(title: "On a weekday", seconds: $model.intake.weekdayMaxSeconds, range: 20...240)
            MinutesStepper(title: "On a weekend", seconds: $model.intake.weekendMaxSeconds, range: 20...300)
        }
        if !model.intake.runDays.isEmpty {
            Section("Best day for your long run") {
                Picker("Long run", selection: $model.intake.longRunDay) {
                    Text("Any").tag(Weekday?.none)
                    ForEach(model.intake.runDays.sorted(), id: \.self) { Text($0.name).tag(Weekday?.some($0)) }
                }
            }
        }
    }

    // MARK: IN-13

    @ViewBuilder
    private var level: some View {
        let assessment = model.assessment
        Section {
            ForEach(CommitmentLevel.allCases, id: \.self) { level in
                let allowed = assessment.levels.allows(level)
                Button {
                    model.intake.level = level
                } label: {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(level.name)
                                .font(.headline)
                            Text(level.summary(stepBackEveryThird: assessment.recoveryTier.stepsBackEveryThird))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if !allowed, let locked = assessment.levels.lockedMessage {
                                Text(locked)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if model.level == level {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(.rect)
                }
                .foregroundStyle(.primary)
                .disabled(!allowed)
                .opacity(allowed ? 1 : VisualOpacity.standard)
                .accessibilityAddTraits(model.level == level ? .isSelected : [])
            }
        } footer: {
            Text(CommitmentLevel.pickerFootnote)
        }
    }

    // MARK: IN-16

    @ViewBuilder
    private func body(unit: DistanceUnit) -> some View {
        Section {
            if unit == .miles {
                OptionalNumberField(title: "Height (in)", value: Binding(
                    get: { model.intake.heightCentimeters.map { $0 / 2.54 } },
                    set: { model.intake.heightCentimeters = $0.map { $0 * 2.54 } }
                ))
                OptionalNumberField(title: "Weight (lb)", value: Binding(
                    get: { model.intake.weightKilograms.map { $0 / 0.453_592 } },
                    set: { model.intake.weightKilograms = $0.map { $0 * 0.453_592 } }
                ))
            } else {
                OptionalNumberField(title: "Height (cm)", value: $model.intake.heightCentimeters)
                OptionalNumberField(title: "Weight (kg)", value: $model.intake.weightKilograms)
            }
        } footer: {
            Text("Optional. It only helps the first weeks build at the right pace.")
        }
    }

    // MARK: IN-17

    private var heartRate: some View {
        HeartRateSettingsSections(settings: $model.heartRate)
    }

    // MARK: IN-19

    @ViewBuilder
    private var reasons: some View {
        Section {
            ForEach(RunReason.allCases, id: \.self) { reason in
                Toggle(reason.rawValue.capitalized, isOn: Binding(
                    get: { model.intake.reasons.contains(reason) },
                    set: { isOn in
                        if isOn { model.intake.reasons.insert(reason) } else { model.intake.reasons.remove(reason) }
                    }
                ))
            }
        } footer: {
            Text("Optional. It only changes how the coach words things.")
        }
    }
}

/// A time that can be left out, like a goal time or a cut-off.
private struct OptionalDuration: View {
    let title: String
    @Binding var seconds: Double?
    var showsHours: Bool

    var body: some View {
        Toggle(title, isOn: Binding(
            get: { seconds != nil },
            set: { seconds = $0 ? (seconds ?? 3_600) : nil }
        ))
        if seconds != nil {
            DurationWheels(seconds: $seconds, showsHours: showsHours)
        }
    }
}

/// Minutes in steps of 5, or "No limit".
struct MinutesStepper: View {
    let title: String
    @Binding var seconds: Double?
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: Binding(
            get: { Int((seconds ?? 0) / 60) },
            set: { seconds = $0 < range.lowerBound ? nil : Double($0 * 60) }
        ), in: (range.lowerBound - 5)...range.upperBound, step: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(seconds.map { CoachFormat.minutes($0) } ?? "No limit")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A number that can be left empty.
struct OptionalNumberField: View {
    let title: String
    @Binding var value: Double?

    @State private var text = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("Not given", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .onChange(of: text) {
                    value = Double(text.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil }
                }
        }
        .onAppear {
            text = value.map { String(Int($0.rounded())) } ?? ""
        }
    }
}

/// "In the last 4 weeks:" and the same answers for the weeks before a break (IN-6).
private struct RecentRunningSections: View {
    @Binding var recent: RecentRunning?
    let unit: DistanceUnit

    private var value: RecentRunning {
        recent ?? RecentRunning(runsPerWeek: 0, weeklyLow: .distance(meters: 0))
    }

    private func update(_ change: (inout RecentRunning) -> Void) {
        var copy = value
        change(&copy)
        recent = copy
    }

    var body: some View {
        Section {
            Stepper("Runs a week: \(value.runsPerWeek)", value: Binding(
                get: { value.runsPerWeek },
                set: { runs in update { $0.runsPerWeek = runs } }
            ), in: 0...7)
            if value.runsPerWeek >= 5 {
                Toggle("For 3 months or more", isOn: Binding(
                    get: { value.fiveRunsForThreeMonths ?? false },
                    set: { yes in update { $0.fiveRunsForThreeMonths = yes } }
                ))
            }
        }
        if value.runsPerWeek > 0 {
            Section {
                AmountField(title: "At least", amount: Binding(
                    get: { recent?.weeklyLow },
                    set: { amount in update { $0.weeklyLow = amount ?? .distance(meters: 0) } }
                ), unit: unit)
                AmountField(title: "At most", amount: Binding(
                    get: { value.weeklyHigh },
                    set: { amount in update { $0.weeklyHigh = amount } }
                ), unit: unit)
            } header: {
                Text("A week of running")
            } footer: {
                Text("A range is fine. Distance or minutes both work.")
            }
            Section {
                AmountField(title: "Longest run", amount: Binding(
                    get: { value.longest },
                    set: { amount in update { $0.longest = amount } }
                ), unit: unit)
            } footer: {
                Text("Leave it empty if you're not sure.")
            }
            Section {
                Stepper("Hard sessions a week: \(value.hardSessionsPerWeek)", value: Binding(
                    get: { value.hardSessionsPerWeek },
                    set: { count in update { $0.hardSessionsPerWeek = count } }
                ), in: 0...5)
            } footer: {
                Text("Intervals, tempo runs, hills or races.")
            }
        }
    }
}

/// "A recent race or all-out effort?" (IN-7, optional)
private struct RaceResultSection: View {
    @Binding var result: RaceResult?
    let unit: DistanceUnit
    let now: Date

    var body: some View {
        Section {
            Toggle("A recent race or all-out effort", isOn: Binding(
                get: { result != nil },
                set: { result = $0 ? RaceResult(date: now, meters: RaceDistance.fiveK.meters, seconds: 30 * 60) : nil }
            ))
            if let current = result {
                Picker("Distance", selection: Binding(
                    get: { RaceDistance.allCases.first { abs($0.meters - current.meters) < 1 } ?? .fiveK },
                    set: { distance in result?.meters = distance.meters }
                )) {
                    ForEach(RaceDistance.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                DurationWheels(seconds: Binding(
                    get: { result?.seconds },
                    set: { result?.seconds = $0 ?? 0 }
                ), showsHours: current.meters > RaceDistance.tenK.meters)
                DatePicker("Date", selection: Binding(
                    get: { current.date },
                    set: { result?.date = $0 }
                ), in: ...now, displayedComponents: .date)
                Toggle("Official chip time", isOn: Binding(
                    get: { current.official },
                    set: { result?.official = $0 }
                ))
                Picker("Course", selection: Binding(
                    get: { current.course },
                    set: { result?.course = $0 }
                )) {
                    ForEach(CourseProfile.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                Toggle("On a treadmill", isOn: Binding(
                    get: { current.treadmill },
                    set: { result?.treadmill = $0 }
                ))
            }
        } footer: {
            Text("Optional. A recent result sets your paces more precisely.")
        }
    }
}

/// "What other training do you do?" (IN-10)
private struct OtherTrainingSections: View {
    @Binding var activities: [OtherActivity]?
    @Binding var physicalWork: Bool?

    var body: some View {
        Section {
            Button {
                activities = []
            } label: {
                HStack {
                    Text("None")
                        .foregroundStyle(.primary)
                    Spacer()
                    if activities?.isEmpty == true {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
            ForEach(ActivityKind.allCases, id: \.self) { kind in
                Toggle(kind.name, isOn: Binding(
                    get: { activities?.contains { $0.kind == kind } ?? false },
                    set: { isOn in
                        var list = activities ?? []
                        if isOn {
                            list.append(OtherActivity(kind: kind, sessionsPerWeek: 1, minutes: 45))
                        } else {
                            list.removeAll { $0.kind == kind }
                        }
                        activities = list
                    }
                ))
            }
        }

        ForEach(activities ?? []) { activity in
            Section(activity.kind.name) {
                ActivityDetail(activity: Binding(
                    get: { activities?.first { $0.id == activity.id } ?? activity },
                    set: { updated in
                        guard let index = activities?.firstIndex(where: { $0.id == activity.id }) else { return }
                        activities?[index] = updated
                    }
                ))
            }
        }

        Section {
            Picker("Physical job or shift work", selection: $physicalWork) {
                Text("Not answered").tag(Bool?.none)
                Text("Yes").tag(Bool?.some(true))
                Text("No").tag(Bool?.some(false))
            }
        }
    }
}

private struct ActivityDetail: View {
    @Binding var activity: OtherActivity

    var body: some View {
        Stepper("\(activity.sessionsPerWeek) a week", value: $activity.sessionsPerWeek, in: 1...14)
        Stepper("\(Int(activity.minutes)) min each", value: $activity.minutes, in: 10...240, step: 5)
        VStack(alignment: .leading) {
            Text("Effort: \(activity.effort) out of 10")
            Slider(value: Binding(
                get: { Double(activity.effort) },
                set: { activity.effort = Int($0.rounded()) }
            ), in: 0...10, step: 1)
        }
        Toggle("Works the legs", isOn: $activity.worksLegs)
        Toggle("New or doubled in the last 8 weeks", isOn: $activity.newOrDoubled)
        if activity.kind == .legStrength {
            Toggle("Heavy (8 reps or fewer)", isOn: $activity.heavy)
        }
    }
}

/// The heart-rate question (IN-17), on intake and in plan settings. The answers stay on the device.
struct HeartRateSettingsSections: View {
    @Binding var settings: HeartRateSettings

    var body: some View {
        Section {
            Text(HeartRateSettings.question)
                .foregroundStyle(.secondary)
            Picker("Heart rate", selection: $settings.device) {
                ForEach(HeartRateDevice.allCases, id: \.self) { Text($0.name).tag($0) }
            }
            if let text = settings.device.screenText {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        if settings.device != .off {
            Section {
                Picker("Use heart rate for coaching", selection: $settings.useForCoaching) {
                    Text("On").tag(true)
                    Text("Show only").tag(false)
                }
            } footer: {
                Text("\(HeartRateSettings.showOnlyHint) \(HeartRateSettings.privacyNote)")
            }
        }
    }
}
