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

    static let range = 1...100

    /// A race distance, to the meter.
    struct Race: Hashable {
        let name: String
        /// What VoiceOver says.
        let spokenName: String
        let meters: Double
    }

    /// Race distances to the meter, so a half marathon's goal buzz comes at 21.1 km, not at 21.
    static let races = [
        Race(name: "5K", spokenName: "5K", meters: 5_000),
        Race(name: "10K", spokenName: "10K", meters: 10_000),
        Race(name: "Half", spokenName: "Half marathon", meters: 21_097.5),
        Race(name: "Marathon", spokenName: "Marathon", meters: 42_195),
    ]

    @State private var meters: Double

    init(choice: WorkoutChoice, unit: DistanceUnit, next: @escaping (_ meters: Double) -> Void) {
        self.choice = choice
        self.unit = unit
        self.next = next
        _meters = State(initialValue: Self.startingMeters(lastMeters: choice.lastGoal(), unit: unit))
    }

    /// Last time's distance in whole units of this unit, or 5 km or 3 mi the first time.
    static func startingAmount(lastMeters: Double?, unit: DistanceUnit) -> Int {
        guard let lastMeters else { return unit == .kilometers ? 5 : 3 }
        let amount = Int((lastMeters / unit.meters).rounded())
        return min(max(amount, range.lowerBound), range.upperBound)
    }

    /// Where the picker opens: last time's race distance as it was, anything else to the whole unit.
    static func startingMeters(lastMeters: Double?, unit: DistanceUnit) -> Double {
        if let lastMeters, let race = race(at: lastMeters) { return race.meters }
        return Double(startingAmount(lastMeters: lastMeters, unit: unit)) * unit.meters
    }

    /// The race at this distance, if it's one.
    static func race(at meters: Double) -> Race? {
        races.first { abs($0.meters - meters) < 1 }
    }

    /// The wheel's whole units. Turning it leaves a race distance for the whole number.
    private var wholeUnits: Binding<Int> {
        Binding(
            get: { min(max(Int((meters / unit.meters).rounded()), Self.range.lowerBound), Self.range.upperBound) },
            set: { meters = Double($0) * unit.meters }
        )
    }

    var body: some View {
        WorkoutGoalPage(question: "How far?", answer: WorkoutFormat.distance(meters, unit: unit), isValid: true) {
            VStack(spacing: LayoutMetrics.compactSpacing) {
                raceChips
                Picker("Distance", selection: wholeUnits) {
                    ForEach(Self.range, id: \.self) { number in
                        Text("\(number) \(unit.symbol)").tag(number)
                    }
                }
                .pickerStyle(.wheel)
            }
        } next: {
            Trace.tap("Distance goal", "Next", [
                "amount": meters / unit.meters,
                "unit": unit.symbol,
                "race": Self.race(at: meters)?.name ?? "none",
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
            ForEach(Self.races, id: \.self) { race in
                let isPicked = Self.race(at: meters) == race
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
