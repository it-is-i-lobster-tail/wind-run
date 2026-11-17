//
//  WorkoutGoalViews.swift
//  Wind Run
//

import SwiftUI

/// How far to run, in whole kilometers or miles, before the "When you're ready" page.
struct DistanceGoalView: View {
    let choice: WorkoutChoice
    let unit: DistanceUnit
    let next: (_ meters: Double) -> Void

    static let range = 1...100

    @State private var amount: Int

    init(choice: WorkoutChoice, unit: DistanceUnit, next: @escaping (_ meters: Double) -> Void) {
        self.choice = choice
        self.unit = unit
        self.next = next
        _amount = State(initialValue: Self.startingAmount(lastMeters: choice.lastGoal(), unit: unit))
    }

    /// Last time's distance in this unit, or 5 km or 3 mi the first time.
    static func startingAmount(lastMeters: Double?, unit: DistanceUnit) -> Int {
        guard let lastMeters else { return unit == .kilometers ? 5 : 3 }
        let amount = Int((lastMeters / unit.meters).rounded())
        return min(max(amount, range.lowerBound), range.upperBound)
    }

    var body: some View {
        WorkoutGoalPage(question: "How far?", answer: WorkoutFormat.distance(Double(amount) * unit.meters, unit: unit), isValid: true) {
            Picker("Distance", selection: $amount) {
                ForEach(Self.range, id: \.self) { number in
                    Text("\(number) \(unit.symbol)").tag(number)
                }
            }
            .pickerStyle(.wheel)
        } next: {
            let meters = Double(amount) * unit.meters
            Trace.tap("Distance goal", "Next", ["amount": amount, "unit": unit.symbol])
            choice.saveGoal(meters)
            next(meters)
        }
        .navigationTitle(choice.name)
        .traceScreen("Distance goal")
    }
}

/// How long to run, in hours and minutes, before the "When you're ready" page.
struct TimeGoalView: View {
    let choice: WorkoutChoice
    let next: (_ seconds: TimeInterval) -> Void

    @State private var seconds: Double?

    init(choice: WorkoutChoice, next: @escaping (_ seconds: TimeInterval) -> Void) {
        self.choice = choice
        self.next = next
        _seconds = State(initialValue: Self.startingSeconds(last: choice.lastGoal()))
    }

    /// Last time's time to the minute, or 30 minutes the first time.
    static func startingSeconds(last: Double?) -> Double {
        guard let last else { return 30 * 60 }
        let minutes = min(max((last / 60).rounded(), 1), 9 * 60 + 59)
        return minutes * 60
    }

    var body: some View {
        let total = seconds ?? 0
        WorkoutGoalPage(question: "How long?", answer: WorkoutFormat.time(total), isValid: total >= 60) {
            DurationWheels(seconds: $seconds, showsSeconds: false)
        } next: {
            Trace.tap("Time goal", "Next", ["minutes": Int(total / 60)])
            choice.saveGoal(total)
            next(total)
        }
        .navigationTitle(choice.name)
        .traceScreen("Time goal")
    }
}

/// A question, the wheels that answer it, and Next.
private struct WorkoutGoalPage<Wheels: View>: View {
    let question: String
    let answer: String
    let isValid: Bool
    @ViewBuilder let wheels: Wheels
    let next: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.sectionSpacing * 1.5) {
                VStack(spacing: LayoutMetrics.compactSpacing) {
                    Text(question)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(isValid ? answer : "––")
                        .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .accessibilityHidden(true)
                }
                .padding(.top, LayoutMetrics.sectionSpacing * 2)

                wheels
                    .frame(maxWidth: 320)

                Button(action: next) {
                    Text("Next")
                        .frame(maxWidth: 280)
                }
                .prominentAccentButton()
                .controlSize(.large)
                .disabled(!isValid)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal)
        }
        .clearsFloatingBar()
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Distance") {
    NavigationStack {
        DistanceGoalView(choice: .distanceRun, unit: .kilometers) { _ in }
    }
}

#Preview("Time") {
    NavigationStack {
        TimeGoalView(choice: .timedRun) { _ in }
    }
}
