//
//  IntakeStepView.swift
//  Wind Run
//

import SwiftUI

/// The answers for one setup question, as sections of the setup form.
struct IntakeStepView: View {
    @Bindable var model: CoachIntakeModel
    let step: IntakeStep

    private var unit: DistanceUnit { model.intake.distanceUnit }

    var body: some View {
        switch step {
        case .terms:
            // Normally accepted before Coach opens; here in case the stored acceptance went missing.
            Section {
                Toggle("I'm healthy enough to run, and I accept Wind Run's terms.", isOn: Binding(
                    get: { model.intake.termsAcceptedAt != nil },
                    set: { accepted in
                        if accepted { TermsAcceptance.accept() }
                        model.intake.termsAcceptedAt = accepted ? .now : nil
                    }
                ))
            } footer: {
                Text("Draft terms, pending legal review.")
            }
        case .goal: goal
        case .finished:
            Section {
                ChoiceRows(choices: FinishedDistance.allCases, selection: $model.intake.finished, title: \.name)
            } footer: {
                Text("For your \(model.intake.goal.distance.name.lowercased()).")
            }
        case .finishedHalf:
            Section { YesNoRows(answer: $model.intake.finishedHalf, no: "No") }
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
        case .schedule: schedule
        case .body: body(unit: unit)
        // Not asked at setup any more: age, why you run, the 30-minute question, other training, the level (on the
        // goal check), heart rate (on by default, in plan settings) and race details (asked 2 weeks out).
        case .age, .reasons, .runs30, .otherTraining, .level, .heartRate, .eventDetails:
            EmptyView()
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
                    DurationWheels(seconds: $model.intake.goal.targetSeconds, showsHours: model.intake.goal.distance >= .tenK)
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
        if let band = model.intake.history, band.asksMonths {
            Section("About how many months?") {
                let months = band.months(answer: model.intake.monthsRunning)
                Stepper(
                    "\(Int(months)) \(months == 1 ? "month" : "months")",
                    value: Binding(
                        get: { months },
                        set: { model.intake.monthsRunning = $0 }
                    ),
                    in: band.monthRange
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

    // MARK: IN-16

    @ViewBuilder
    private func body(unit: DistanceUnit) -> some View {
        Section {
            BodyFields(heightCentimeters: $model.intake.heightCentimeters, weightKilograms: $model.intake.weightKilograms, unit: unit)
        } footer: {
            Text(BodyFields.footnote)
        }
    }
}

/// A time that can be left out, like a goal time or a cut-off.
struct OptionalDuration: View {
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

/// Height in feet and inches, stored as centimeters. Nothing is given until the feet are.
struct FeetAndInchesField: View {
    @Binding var centimeters: Double?

    @State private var feet = ""
    @State private var inches = ""

    var body: some View {
        HStack {
            Text("Height")
            Spacer()
            part($feet, unit: "ft", placeholder: "–", name: "Feet")
            part($inches, unit: "in", placeholder: "0", name: "Inches")
        }
        .onAppear {
            guard let parts = centimeters.map({ Self.feetAndInches($0) }) else { return }
            feet = String(parts.feet)
            inches = String(parts.inches)
        }
    }

    private func part(_ text: Binding<String>, unit: String, placeholder: String, name: String) -> some View {
        HStack(spacing: 4) {
            TextField(placeholder, text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(minWidth: 28)
                .fixedSize()
                .accessibilityLabel(name)
                .onChange(of: text.wrappedValue) {
                    centimeters = Self.centimeters(feet: feet, inches: inches)
                }
            Text(unit)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    /// Whole feet and the inches left over, rounded to the nearest inch.
    static func feetAndInches(_ centimeters: Double) -> (feet: Int, inches: Int) {
        let total = Int((centimeters / 2.54).rounded())
        return (total / 12, total % 12)
    }

    /// Nil until the feet are given. Empty inches count as 0.
    static func centimeters(feet: String, inches: String) -> Double? {
        guard let feet = Int(feet), feet > 0 else { return nil }
        let inches = Int(inches) ?? 0
        return Double(feet * 12 + inches) * 2.54
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
                ), showsHours: current.meters >= RaceDistance.tenK.meters)
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

/// The heart-rate switch (IN-17) in plan settings: one yes or no, since the app finds the source on its own, then
/// the source found and the Show only choice. Setup doesn't ask: heart rate is on by default. The answers stay on the
/// device.
struct HeartRateSettingsSections: View {
    @Binding var settings: HeartRateSettings
    /// The source found on the latest run with heart rate, or nil before one.
    var detected: HeartRateDevice?

    var body: some View {
        Section {
            Toggle("Use heart rate", isOn: $settings.enabled)
        } footer: {
            Text("\(HeartRateSettings.question) \(HeartRateSettings.sourceNote)")
        }
        if settings.enabled {
            Section {
                LabeledContent("Source", value: detected.flatMap { $0 == .off ? nil : $0.name } ?? "Found on your next run")
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

/// IN-18: the optional race details. Every answer can be left out.
struct EventDetailsSections: View {
    @Binding var details: EventDetails?
    let unit: DistanceUnit
    let now: Date

    private func binding<Value>(_ keyPath: WritableKeyPath<EventDetails, Value>) -> Binding<Value> {
        Binding(
            get: { (details ?? EventDetails(answeredAt: now))[keyPath: keyPath] },
            set: {
                var updated = details ?? EventDetails(answeredAt: now)
                updated[keyPath: keyPath] = $0
                details = updated
            }
        )
    }

    var body: some View {
        Section {
            Picker("Course", selection: binding(\.course)) {
                Text("Not sure").tag(RaceCourse?.none)
                ForEach(RaceCourse.allCases, id: \.self) { Text($0.name).tag(RaceCourse?.some($0)) }
            }
            Picker("Start wave", selection: binding(\.startWave)) {
                Text("Skip").tag(StartWave?.none)
                ForEach(StartWave.allCases, id: \.self) { Text($0.name).tag(StartWave?.some($0)) }
            }
            Toggle("I know the start time", isOn: Binding(
                get: { details?.startMinutes != nil },
                set: { binding(\.startMinutes).wrappedValue = $0 ? 9 * 60 : nil }
            ))
            if let minutes = details?.startMinutes {
                DatePicker("Start time", selection: Binding(
                    get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: now) ?? now },
                    set: {
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: $0)
                        binding(\.startMinutes).wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                    }
                ), displayedComponents: .hourAndMinute)
            }
            OptionalNumberField(title: unit == .miles ? "Altitude (ft)" : "Altitude (m)", value: Binding(
                get: { details?.altitudeMeters.map { unit == .miles ? $0 / 0.3048 : $0 } },
                set: { binding(\.altitudeMeters).wrappedValue = $0.map { unit == .miles ? $0 * 0.3048 : $0 } }
            ))
        } footer: {
            Text("The course, start time and altitude help set your race pace and heat warnings. I'll ask again 2 weeks before the race.")
        }
    }
}
