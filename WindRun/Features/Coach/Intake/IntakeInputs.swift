//
//  IntakeInputs.swift
//  Wind Run
//

import SwiftUI

/// A list of answers where one can be picked, shown as rows with a check mark.
struct ChoiceRows<Choice: Hashable>: View {
    let choices: [Choice]
    @Binding var selection: Choice?
    let title: (Choice) -> String

    var body: some View {
        ForEach(choices, id: \.self) { choice in
            Button {
                selection = choice
            } label: {
                HStack {
                    Text(title(choice))
                        .foregroundStyle(.primary)
                    Spacer()
                    if selection == choice {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(.rect)
            }
            .foregroundStyle(.primary)
            .accessibilityAddTraits(selection == choice ? .isSelected : [])
        }
    }
}

/// Yes or no, where no answer yet is allowed.
struct YesNoRows: View {
    @Binding var answer: Bool?
    var yes = "Yes"
    var no = "Not yet"

    var body: some View {
        ChoiceRows(choices: [true, false], selection: $answer) { $0 ? yes : no }
    }
}

/// Hours, minutes and seconds on wheels, for goal times and race results.
struct DurationWheels: View {
    @Binding var seconds: Double?
    var showsHours = true

    private var parts: (hours: Int, minutes: Int, seconds: Int) {
        let total = Int((seconds ?? 0).rounded())
        return (total / 3600, (total % 3600) / 60, total % 60)
    }

    var body: some View {
        HStack(spacing: 0) {
            if showsHours {
                wheel(0...9, value: parts.hours, label: "h", name: "Hours") { set(hours: $0) }
            }
            wheel(0...59, value: parts.minutes, label: "min", name: "Minutes") { set(minutes: $0) }
            wheel(0...59, value: parts.seconds, label: "s", name: "Seconds") { set(seconds: $0) }
        }
        .frame(height: 140)
    }

    private func wheel(_ range: ClosedRange<Int>, value: Int, label: String, name: String, set: @escaping (Int) -> Void) -> some View {
        Picker(name, selection: Binding(get: { value }, set: set)) {
            ForEach(range, id: \.self) { number in
                Text(label == "h" ? "\(number) \(label)" : String(format: "%02d \(label)", number)).tag(number)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private func set(hours: Int? = nil, minutes: Int? = nil, seconds newSeconds: Int? = nil) {
        let current = parts
        let total = (hours ?? current.hours) * 3600 + (minutes ?? current.minutes) * 60 + (newSeconds ?? current.seconds)
        seconds = total > 0 ? Double(total) : nil
    }
}

/// A pace per kilometer or mile on wheels, stored as seconds per kilometer.
struct PaceWheels: View {
    @Binding var secondsPerKilometer: Double?
    let unit: DistanceUnit

    private var perUnit: Int {
        Int(((secondsPerKilometer ?? 390) * unit.meters / 1_000).rounded())
    }

    var body: some View {
        HStack(spacing: 0) {
            Picker("Pace minutes", selection: Binding(get: { perUnit / 60 }, set: { set(minutes: $0) })) {
                ForEach(3...20, id: \.self) { Text("\($0) min").tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
            Picker("Pace seconds", selection: Binding(get: { perUnit % 60 }, set: { set(seconds: $0) })) {
                ForEach(Array(stride(from: 0, to: 60, by: 5)), id: \.self) { Text(String(format: "%02d s", $0)).tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(maxWidth: .infinity)
            .clipped()
            Text("/\(unit.symbol)")
                .foregroundStyle(.secondary)
        }
        .frame(height: 140)
    }

    private func set(minutes: Int? = nil, seconds: Int? = nil) {
        let current = perUnit
        let rounded = (current % 60) / 5 * 5
        let total = (minutes ?? current / 60) * 60 + (seconds ?? rounded)
        secondsPerKilometer = Double(total) * 1_000 / unit.meters
    }
}

/// A distance in the runner's unit, or a time in minutes: every distance answer also accepts minutes.
struct AmountField: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    @Binding var amount: RunAmount?
    let unit: DistanceUnit

    @State private var usesMinutes = false
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading) {
                    Text(title)
                    field
                    unitPicker
                }
            } else {
                HStack {
                    Text(title)
                    Spacer()
                    field
                        .frame(width: 80)
                    unitPicker
                        .frame(width: 110)
                }
            }
        }
        .onAppear(perform: load)
    }

    private var field: some View {
        TextField("0", text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
            .focused($isFocused)
            .accessibilityLabel(title)
            .onChange(of: text) { update() }
    }

    private var unitPicker: some View {
        Picker("\(title) in", selection: $usesMinutes) {
            Text(unit.symbol).tag(false)
            Text("min").tag(true)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("\(title) in")
        .onChange(of: usesMinutes) { update() }
    }

    private func load() {
        switch amount {
        case .distance(let meters) where meters > 0:
            usesMinutes = false
            text = format(meters / unit.meters)
        case .time(let seconds) where seconds > 0:
            usesMinutes = true
            text = format(seconds / 60)
        default:
            // An empty answer shows the placeholder, so typing starts from nothing.
            text = ""
        }
    }

    private func update() {
        let value = Double(text.replacingOccurrences(of: ",", with: "."))
        guard let value, value > 0 else {
            amount = nil
            return
        }
        amount = usesMinutes ? .time(seconds: value * 60) : .distance(meters: value * unit.meters)
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// A row of weekday buttons that can each be on or off. At accessibility text sizes the days
/// stack in one column with their full names.
struct WeekdayPicker: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var days: Set<Weekday>

    /// Monday first, the way most running plans read.
    private let order: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 6) {
                ForEach(order, id: \.self) { button(for: $0, title: $0.name) }
            }
        } else {
            HStack(spacing: 6) {
                ForEach(order, id: \.self) { button(for: $0, title: String($0.shortName.prefix(2))) }
            }
        }
    }

    private func button(for day: Weekday, title: String) -> some View {
        let isOn = days.contains(day)
        return Button {
            if isOn { days.remove(day) } else { days.insert(day) }
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 40)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(isOn ? Color.accentColor : Color.secondary.opacity(VisualOpacity.subtle), in: .rect(cornerRadius: LayoutMetrics.compactCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.name)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
