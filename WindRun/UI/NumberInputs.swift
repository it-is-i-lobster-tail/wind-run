//
//  NumberInputs.swift
//  Wind Run
//

import SwiftUI

/// Hours, minutes and seconds on wheels, for interval steps.
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
