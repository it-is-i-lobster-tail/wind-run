//
//  WorkoutGoalViews.swift
//  Wind Run
//

import SwiftUI

/// How far to run, in whole kilometers or miles or as a race distance, before the "When you're ready" page.
struct DistanceGoalView: View {
    let choice: WorkoutChoice
    let unit: DistanceUnit
    let next: (_ meters: Double) -> Void

    @State private var meters: Double

    init(choice: WorkoutChoice, unit: DistanceUnit, next: @escaping (_ meters: Double) -> Void) {
        self.choice = choice
        self.unit = unit
        self.next = next
        _meters = State(initialValue: DistanceGoalOptions.startingMeters(lastMeters: choice.lastGoal(), unit: unit))
    }

    /// The wheel's whole units. Turning it leaves a race distance for the whole number.
    private var wholeUnits: Binding<Int> {
        Binding(
            get: { DistanceGoalOptions.startingAmount(lastMeters: meters, unit: unit) },
            set: { meters = Double($0) * unit.meters }
        )
    }

    var body: some View {
        WorkoutGoalPage(question: "How far?", answer: WorkoutFormat.distance(meters, unit: unit), isValid: true) {
            VStack(spacing: LayoutMetrics.compactSpacing) {
                raceChips
                Picker("Distance", selection: wholeUnits) {
                    ForEach(DistanceGoalOptions.range, id: \.self) { number in
                        Text("\(number) \(unit.symbol)").tag(number)
                    }
                }
                .pickerStyle(.wheel)
            }
        } next: {
            Trace.tap("Distance goal", "Next", [
                "amount": meters / unit.meters,
                "unit": unit.symbol,
                "race": DistanceGoalOptions.race(at: meters)?.name ?? "none",
            ])
            choice.saveGoal(meters)
            next(meters)
        }
        .navigationTitle(choice.name)
        .traceScreen("Distance goal")
    }

    /// 5K, 10K, Half and Marathon, the one picked filled in.
    private var raceChips: some View {
        HStack(spacing: LayoutMetrics.compactSpacing) {
            ForEach(DistanceGoalOptions.races, id: \.self) { race in
                let isPicked = DistanceGoalOptions.race(at: meters) == race
                Button {
                    Trace.tap("Distance goal", race.name)
                    meters = race.meters
                } label: {
                    Text(race.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .tint(isPicked ? .accentColor : .secondary)
                .accessibilityAddTraits(isPicked ? .isSelected : [])
                .accessibilityLabel(race.spokenName)
            }
        }
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
        _seconds = State(initialValue: TimeGoalOptions.startingSeconds(last: choice.lastGoal()))
    }

    var body: some View {
        let total = seconds ?? 0
        WorkoutGoalPage(question: "How long?", answer: WorkoutFormat.time(total), isValid: total >= 60) {
            DurationWheels(seconds: $seconds, showsSeconds: false, maxHours: TimeGoalOptions.maxHours)
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

    /// The answer's size, following the runner's text size.
    @ScaledMetric(relativeTo: .largeTitle) private var answerSize = 56
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.sectionSpacing * 1.5) {
                VStack(spacing: LayoutMetrics.compactSpacing) {
                    Text(question)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    // The wheels say the same to VoiceOver, so this isn't read twice.
                    Text(isValid ? answer : "––")
                        .font(.system(size: answerSize, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        // Rolls to the new number as the wheels turn.
                        .animation(reduceMotion ? nil : .snappy, value: answer)
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
