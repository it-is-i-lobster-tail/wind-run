//
//  WatchWorkoutGoalViews.swift
//  Wind Run Watch
//

import SwiftUI

struct WatchWorkoutGoalView: View {
    let unit: DistanceUnit
    let start: (RunGoal) -> Void

    private let choice: WorkoutChoice
    @State private var amount: Double
    @State private var showsPresets = false
    @FocusState private var isGoalFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var goalSize: CGFloat = 36

    init(goal: RunGoal, unit: DistanceUnit, start: @escaping (RunGoal) -> Void) {
        self.unit = unit
        self.start = start
        switch goal {
        case .distance(let meters):
            choice = .distanceRun
            _amount = State(initialValue: meters)
        case .time(let seconds):
            choice = .timedRun
            _amount = State(initialValue: seconds)
        }
    }

    private var isDistance: Bool { choice.type == .distance }

    private var goalText: String {
        isDistance ? WorkoutFormat.distance(amount, unit: unit) : WorkoutFormat.time(amount)
    }

    var body: some View {
        let choices = amounts
        let range = 0...(choices.count - 1)
        let selection = Binding(
            get: { choices.firstIndex(of: amount) ?? range.lowerBound },
            set: { amount = choices[$0.clamped(to: range)] }
        )

        ScrollView {
            VStack(spacing: 2) {
                goalValue(selection: selection, range: range)
                GlassEffectContainer(spacing: 3) {
                    HStack(spacing: 4) {
                        adjustment(-1, selection: selection, range: range)
                        Button { showsPresets = true } label: {
                            ViewThatFits(in: .horizontal) {
                                Text("Presets")
                                    .font(.footnote.weight(.semibold))
                                    .fixedSize(horizontal: true, vertical: false)
                                Text("Presets")
                                    .font(.caption2.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                            }
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(.capsule)
                            .glassEffect(.regular.interactive())
                        }
                        adjustment(1, selection: selection, range: range)
                    }
                    .buttonStyle(.plain)
                }
            }
            .scenePadding(.horizontal)
        }
        .defaultFocus($isGoalFocused, true)
        .safeAreaBar(edge: .bottom, spacing: 4) {
            Button {
                start(isDistance ? .distance(meters: amount) : .time(seconds: amount))
            } label: {
                Label("Start", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.accentColor)
            .foregroundStyle(.onAccent)
            .scenePadding(.horizontal)
            .padding(.bottom, 12)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationTitle(choice.name)
        .sheet(isPresented: $showsPresets, onDismiss: { isGoalFocused = true }) {
            presetList
        }
        .onChange(of: unit) { _, unit in
            if isDistance {
                amount = DistanceGoalOptions.startingMeters(lastMeters: amount, unit: unit)
            }
        }
    }

    private func goalValue(selection: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Text(goalText)
            .font(.system(size: goalSize, weight: .bold, design: .rounded).monospacedDigit())
            .minimumScaleFactor(0.52)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .contentTransition(.numericText(value: amount))
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: amount)
            .focusable()
            .focused($isGoalFocused)
            .digitalCrownRotation(detent: selection, from: range.lowerBound, through: range.upperBound, by: 1)
            .accessibilityLabel(isDistance ? "Distance goal" : "Time goal")
            .accessibilityValue(goalText)
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: selection.wrappedValue += 1
                case .decrement: selection.wrappedValue -= 1
                @unknown default: break
                }
            }
    }

    private func adjustment(_ step: Int, selection: Binding<Int>, range: ClosedRange<Int>) -> some View {
        let increases = step > 0
        let canAdjust = range.contains(selection.wrappedValue + step)
        return Button {
            selection.wrappedValue += step
            isGoalFocused = true
        } label: {
            Image(systemName: increases ? "plus" : "minus")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.circle)
                .glassEffect(.regular.interactive(canAdjust), in: .circle)
        }
        .disabled(!canAdjust)
        .opacity(canAdjust ? 1 : 0.45)
        .accessibilityLabel(increases ? "Increase goal" : "Decrease goal")
    }

    private var amounts: [Double] {
        if isDistance {
            let wholeDistances = DistanceGoalOptions.range.map { Double($0) * unit.meters }
            return Set(wholeDistances + DistanceGoalOptions.races.map(\.meters)).sorted()
        }
        return (1...TimeGoalOptions.maxMinutes).map { Double($0 * 60) }
    }

    private var presets: [Double] {
        if isDistance {
            let shortDistances = [1, 3, 5].map { Double($0) * unit.meters }
            return Set(shortDistances + DistanceGoalOptions.races.map(\.meters)).sorted()
        }
        return [15, 30, 45, 60, 90, 120].map { Double($0 * 60) }
    }

    private var presetList: some View {
        List {
            Section("Presets") {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        amount = preset
                        showsPresets = false
                    } label: {
                        HStack {
                            Text(presetName(preset))
                            Spacer(minLength: 0)
                            if preset == amount {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .accessibilityAddTraits(preset == amount ? .isSelected : [])
                }
            }
        }
    }

    private func presetName(_ preset: Double) -> String {
        if isDistance {
            return DistanceGoalOptions.race(at: preset)?.spokenName ?? WorkoutFormat.distance(preset, unit: unit)
        }
        return WorkoutFormat.time(preset)
    }
}
