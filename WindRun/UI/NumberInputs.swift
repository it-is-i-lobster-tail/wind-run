//
//  NumberInputs.swift
//  Wind Run
//

import SwiftUI

/// Hours, minutes and seconds on wheels, for interval steps.
struct DurationWheels: View {
    @Binding var seconds: Double?
    var showsHours = true
    var showsSeconds = true
    /// The most the hours wheel offers.
    var maxHours = 9

    private var parts: (hours: Int, minutes: Int, seconds: Int) {
        Self.parts(of: seconds)
    }

    /// The wheels' hours, minutes and seconds for a time, to the nearest second. No time is all zeros.
    static func parts(of seconds: Double?) -> (hours: Int, minutes: Int, seconds: Int) {
        let total = Int((seconds ?? 0).rounded())
        return (total / 3600, (total % 3600) / 60, total % 60)
    }

    /// The time the wheels show, or nil when they're all at zero.
    static func total(hours: Int, minutes: Int, seconds: Int) -> Double? {
        let total = hours * 3600 + minutes * 60 + seconds
        return total > 0 ? Double(total) : nil
    }

    var body: some View {
        HStack(spacing: 0) {
            if showsHours {
                // A longer time than the wheel goes to shows at its end rather than blank.
                wheel(0...maxHours, value: min(parts.hours, maxHours), label: "h", spoken: "hour", name: "Hours") { set(hours: $0) }
            }
            wheel(0...59, value: parts.minutes, label: "min", spoken: "minute", name: "Minutes") { set(minutes: $0) }
            if showsSeconds {
                wheel(0...59, value: parts.seconds, label: "s", spoken: "second", name: "Seconds") { set(seconds: $0) }
            }
        }
        .frame(height: 140)
    }

    /// "5 min" on the wheel, read as "5 minutes".
    private func wheel(_ range: ClosedRange<Int>, value: Int, label: String, spoken: String, name: String, set: @escaping (Int) -> Void) -> some View {
        Picker(name, selection: Binding(get: { value }, set: set)) {
            ForEach(range, id: \.self) { number in
                Text("\(number) \(label)")
                    .accessibilityLabel("\(number) \(spoken)\(number == 1 ? "" : "s")")
                    .tag(number)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private func set(hours: Int? = nil, minutes: Int? = nil, seconds newSeconds: Int? = nil) {
        let current = parts
        seconds = Self.total(hours: hours ?? current.hours, minutes: minutes ?? current.minutes, seconds: newSeconds ?? current.seconds)
    }
}

/// A number that can be left empty.
struct OptionalNumberField: View {
    let title: String
    @Binding var value: Double?

    @State private var text = ""
    /// What the field was filled with from `value`, which isn't the runner typing, so isn't saved back.
    @State private var filledText: String?

    var body: some View {
        HStack {
            Text(title)
                .accessibilityHidden(true)
            Spacer()
            TextField("Not given", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(title)
                .onChange(of: text) {
                    // Saving the shown value back would round it, and give it a new date.
                    guard text != filledText else { return }
                    filledText = nil
                    value = Self.number(in: text)
                }
        }
        .onAppear {
            let shown = value.map(Self.text(for:)) ?? ""
            filledText = shown
            text = shown
        }
    }

    /// "72.6", or "185" for a whole number: one decimal at most, as a runner would type it.
    nonisolated static func text(for value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }

    /// What's typed as a number above 0, with a comma or a dot for the decimal point.
    nonisolated static func number(in text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil }
    }
}
