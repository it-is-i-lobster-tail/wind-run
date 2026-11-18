//
//  WorkoutEndPage.swift
//  Wind Run
//

import SwiftUI

/// The warm-up or cooldown: how it ends, and a way to take it out. Each change goes straight into the
/// workout. Opening it for a part the workout doesn't have adds that part, as it starts.
struct WorkoutEndPage: View {
    @Environment(\.dismiss) private var dismiss

    let part: WorkoutPart
    let unit: DistanceUnit
    /// Sets the part, or nil to take it out.
    let apply: (IntervalGoal?) -> Void

    @State private var goal: IntervalGoal?
    @State private var ending: WorkoutEnding

    init(part: WorkoutPart, goal: IntervalGoal, unit: DistanceUnit, apply: @escaping (IntervalGoal?) -> Void) {
        self.part = part
        self.unit = unit
        self.apply = apply
        _goal = State(initialValue: goal)
        _ending = State(initialValue: WorkoutEnding(goal))
    }

    private var name: String { part == .warmup ? "Warm-up" : "Cooldown" }

    var body: some View {
        Form {
            WorkoutEndFields(
                goal: $goal,
                ending: $ending,
                unit: unit,
                question: "How does it end?",
                defaultSeconds: 5 * 60,
                trace: name
            ) { ending in
                switch (part, ending) {
                case (.warmup, .manual):
                    "Tap Next on the run screen, your Lock Screen or your Apple Watch when you're warmed up, and the main workout starts."
                case (.warmup, _):
                    "Your main workout starts automatically when you reach this."
                case (_, .manual):
                    "Runs until you finish the run."
                default:
                    "You'll hear when you reach this. Then finish the run whenever you like."
                }
            }

            Section {
                Button(role: .destructive) {
                    Trace.tap(name, "Remove \(name.lowercased())")
                    apply(nil)
                    dismiss()
                } label: {
                    Text("Remove \(name.lowercased())")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .traceScreen(name)
        // Added as it opens, so Back keeps a part just added.
        .onAppear { if let goal { apply(goal) } }
        // While a box is empty the part keeps its last time or distance.
        .onChange(of: goal) { _, goal in
            if let goal { apply(goal) }
        }
    }
}

// MARK: - How a part ends

/// How a part ends: after a time, after a distance, or when the runner taps Next.
enum WorkoutEnding: String, CaseIterable, Identifiable {
    case time
    case distance
    case manual

    var id: Self { self }

    init(_ goal: IntervalGoal) {
        switch goal {
        case .time: self = .time
        case .distance: self = .distance
        case .open: self = .manual
        }
    }

    var name: String {
        switch self {
        case .time: "Time"
        case .distance: "Distance"
        case .manual: "Manual"
        }
    }
}

/// A sheet's question over its first section, in the body's size, as the sheets ask it.
struct WorkoutSheetQuestion: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.primary)
            .textCase(nil)
            .padding(.bottom, 4)
    }
}

/// How a part ends, as sections of a form: Time, Distance or Manual, then minutes and seconds, or a distance
/// in kilometers or miles. Writes nil while what's typed isn't a time or distance yet.
struct WorkoutEndFields: View {
    @Binding var goal: IntervalGoal?
    @Binding var ending: WorkoutEnding
    let unit: DistanceUnit
    /// The ways this part can end. One way hides the choice.
    var endings: [WorkoutEnding] = WorkoutEnding.allCases
    var question: String?
    /// What a time starts at when the runner switches to it.
    var defaultSeconds: TimeInterval = 10 * 60
    /// What a distance starts at in each unit when the runner switches to it.
    var defaultMeters: (DistanceUnit) -> Double = { $0.meters }
    let trace: String
    let explanation: (WorkoutEnding) -> String

    @State private var minutes = ""
    @State private var seconds = ""
    @State private var amount = ""
    /// The distance in meters as the workout has it, kept while the box still shows it, so opening the page
    /// never rounds it.
    @State private var exactMeters: Double?
    @State private var isFilled = false

    var body: some View {
        if endings.count > 1 || question != nil {
            Section {
                if endings.count > 1 {
                    Picker("Ends", selection: $ending.traced(trace, "Ends") { $0.rawValue }) {
                        ForEach(endings) { ending in
                            Text(ending.name).tag(ending)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            } header: {
                if let question {
                    WorkoutSheetQuestion(text: question)
                }
            }
        }

        Section {
            switch ending {
            case .time:
                HStack(spacing: LayoutMetrics.sectionSpacing) {
                    NumberBox(title: "Minutes", text: $minutes, allowsDecimal: false)
                    NumberBox(title: "Seconds", text: $seconds, allowsDecimal: false)
                }
                .padding(.vertical, 6)
            case .distance:
                NumberBox(title: unit.name, text: $amount, allowsDecimal: true)
                    .padding(.vertical, 6)
            case .manual:
                Label("Ends when you tap Next", systemImage: "hand.tap")
            }
        } footer: {
            Text(explanation(ending))
        }
        .onAppear(perform: fill)
        .onChange(of: ending) { update() }
        .onChange(of: minutes) { update() }
        .onChange(of: seconds) { update() }
        .onChange(of: amount) { update() }
    }

    /// The boxes start from the part as it is, and from sensible amounts for the ways it doesn't end.
    private func fill() {
        guard !isFilled else { return }
        isFilled = true
        var time = defaultSeconds
        var meters = defaultMeters(unit)
        switch goal {
        case .time(let value): time = value
        case .distance(let value): meters = value
        case .open, nil: break
        }
        let whole = Int(time.rounded())
        minutes = "\(whole / 60)"
        seconds = "\(whole % 60)"
        exactMeters = meters
        amount = WorkoutDistance.amount(meters, in: unit)
    }

    private func update() {
        guard isFilled else { return }
        goal = Self.goal(ending: ending, minutes: minutes, seconds: seconds, amount: amount, exactMeters: exactMeters, unit: unit)
    }

    /// What the boxes read as: a time from the minutes and seconds, a distance in `unit` (the exact meters
    /// while the box still shows them), or nil while it's zero or doesn't read as a number.
    static func goal(
        ending: WorkoutEnding,
        minutes: String,
        seconds: String,
        amount: String,
        exactMeters: Double?,
        unit: DistanceUnit
    ) -> IntervalGoal? {
        switch ending {
        case .time:
            let total = (Int(minutes) ?? 0) * 60 + (Int(seconds) ?? 0)
            return total > 0 ? .time(TimeInterval(total)) : nil
        case .distance:
            if let exactMeters, amount == WorkoutDistance.amount(exactMeters, in: unit) {
                return .distance(meters: exactMeters)
            }
            let value = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
            return value > 0 ? .distance(meters: value * unit.meters) : nil
        case .manual:
            return .open
        }
    }
}

/// A caption over a filled box to type a number in, as the warm-up sheet shows minutes and seconds.
private struct NumberBox: View {
    let title: String
    @Binding var text: String
    let allowsDecimal: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("0", text: $text)
                .keyboardType(allowsDecimal ? .decimalPad : .numberPad)
                .font(.title3.monospacedDigit())
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.fill.tertiary, in: .rect(cornerRadius: LayoutMetrics.cardCornerRadius))
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
