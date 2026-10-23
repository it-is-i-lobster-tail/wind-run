//
//  IntervalEditorView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// Builds a new interval workout or changes a saved one. A new one starts as warm up, repeats and cool
/// down, so most workouts are a few taps from it. Nothing is stored until Save.
struct IntervalEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    let editing: IntervalEditing
    let saved: (IntervalPlan) -> Void

    @State private var draft: IntervalDraft
    private let original: IntervalDraft

    init(editing: IntervalEditing, saved: @escaping (IntervalPlan) -> Void) {
        self.editing = editing
        self.saved = saved
        let draft = editing.plan.map(IntervalDraft.init) ?? .starter()
        self.original = draft
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(draft.suggestedName, text: $draft.name)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                } header: {
                    Text("Name")
                } footer: {
                    if let problem = draft.problem, draft != original {
                        Text(problem)
                    }
                }

                Section {
                    ForEach($draft.blocks) { $block in
                        if block.isRepeat {
                            NavigationLink {
                                IntervalRepeatEditor(block: $block, unit: unit)
                            } label: {
                                IntervalRepeatRow(block: block, unit: unit)
                            }
                        } else {
                            NavigationLink {
                                IntervalStepEditor(step: onlyStep(of: $block), unit: unit)
                            } label: {
                                IntervalStepRow(step: block.steps.first ?? .new(.work), unit: unit)
                            }
                        }
                    }
                    .onMove { draft.blocks.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { draft.blocks.remove(atOffsets: $0) }

                    IntervalAddStepMenu(
                        add: { draft.blocks.append(.single($0)) },
                        addRepeat: { draft.blocks.append(.newRepeat()) }
                    )
                } header: {
                    Text("Steps")
                } footer: {
                    Text("Tap a step to change it. Hold and drag to move it, or swipe to delete it.")
                }

                if !draft.timeline.isEmpty {
                    Section {
                        IntervalTimelineBar(timeline: draft.timeline)
                            .listRowBackground(Color.clear)
                    } footer: {
                        Text(IntervalSummary.length(draft.timeline))
                    }
                }
            }
            .navigationTitle(editing.plan == nil ? "New workout" : "Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!draft.canSave)
                }
            }
            // Swiping the sheet away would lose the changes, so it takes Cancel once there are some.
            .interactiveDismissDisabled(draft != original)
        }
    }

    /// The step of a block that holds just one.
    private func onlyStep(of block: Binding<IntervalDraft.Block>) -> Binding<IntervalDraft.Step> {
        Binding(
            get: { block.wrappedValue.steps.first ?? .new(.work) },
            set: { block.wrappedValue.steps = [$0] }
        )
    }

    private func save() {
        let plan = draft.save(replacing: editing.plan, in: modelContext)
        dismiss()
        saved(plan)
    }
}

/// Steps repeated: how many times, and the steps each time through.
struct IntervalRepeatEditor: View {
    @Binding var block: IntervalDraft.Block
    let unit: DistanceUnit

    var body: some View {
        Form {
            Section {
                Stepper(value: $block.repeatCount, in: IntervalBlock.repeatRange) {
                    Text("\(block.repeatCount) times")
                        .monospacedDigit()
                }
            }

            Section {
                ForEach($block.steps) { $step in
                    NavigationLink {
                        IntervalStepEditor(step: $step, unit: unit)
                    } label: {
                        IntervalStepRow(step: step, unit: unit)
                    }
                }
                .onMove { block.steps.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { block.steps.remove(atOffsets: $0) }

                IntervalAddStepMenu(add: { block.steps.append($0) }, addRepeat: nil)
            } header: {
                Text("Each time through")
            }
        }
        .navigationTitle("Repeat")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One step: what it is, and when it ends.
struct IntervalStepEditor: View {
    @Binding var step: IntervalDraft.Step
    let unit: DistanceUnit

    private enum Ending: Hashable {
        case time
        case distance
        case open
    }

    private var ending: Binding<Ending> {
        Binding(
            get: {
                switch step.goal {
                case .time: .time
                case .distance: .distance
                case .open: .open
                }
            },
            set: { ending in
                switch ending {
                case .time: step.goal = .time(IntervalDraft.Step.new(step.choice).goal.seconds ?? 180)
                // A track lap, or a quarter mile.
                case .distance: step.goal = .distance(meters: unit == .miles ? 402.336 : 400)
                case .open: step.goal = .open
                }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker("Step", selection: $step.choice) {
                    ForEach(IntervalStepChoice.allCases) { choice in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(choice.name)
                                Text(choice.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: choice.systemImage)
                        }
                        .tag(choice)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Step")
            }

            Section {
                Picker("Ends", selection: ending) {
                    Text("Time").tag(Ending.time)
                    Text("Distance").tag(Ending.distance)
                    Text("Tap Next").tag(Ending.open)
                }
                .pickerStyle(.segmented)

                switch step.goal {
                case .time(let seconds):
                    // The coach's minutes-and-seconds wheels; a step never needs an hour.
                    DurationWheels(seconds: Binding(get: { seconds }, set: { step.goal = IntervalDraft.clamped(.time($0 ?? 0)) }), showsHours: false)
                case .distance(let meters):
                    DistanceWheels(meters: Binding(get: { meters }, set: { step.goal = .distance(meters: $0) }), unit: unit)
                case .open:
                    Text("Runs until you tap Next in the app, on your Lock Screen or on your Apple Watch.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Ends")
            }
        }
        .navigationTitle(step.choice.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension IntervalGoal {
    var seconds: TimeInterval? {
        if case .time(let seconds) = self { seconds } else { nil }
    }
}

/// Whole kilometers and meters, or whole miles and hundredths, on wheels.
private struct DistanceWheels: View {
    @Binding var meters: Double
    let unit: DistanceUnit

    /// The parts of a unit the second wheel offers: 50 m steps, or 0.05 mi steps.
    private var partStep: Int { unit == .miles ? 5 : 50 }
    private var partsPerUnit: Int { unit == .miles ? 100 : 1_000 }

    /// The distance in parts: meters, or hundredths of a mile, rounded to the wheel's step.
    private var parts: Int {
        let exact = meters / unit.meters * Double(partsPerUnit)
        return Int((exact / Double(partStep)).rounded()) * partStep
    }

    var body: some View {
        HStack(spacing: 0) {
            wheel(0...(unit == .miles ? 26 : 42), value: parts / partsPerUnit, label: unit.symbol, name: unit.name) {
                set($0 * partsPerUnit + parts % partsPerUnit)
            }
            wheel(Array(stride(from: 0, to: partsPerUnit, by: partStep)), value: parts % partsPerUnit, label: unit == .miles ? "" : "m", name: unit == .miles ? "Hundredths" : "Meters", format: { partFormat($0) }) {
                set(parts / partsPerUnit * partsPerUnit + $0)
            }
        }
        .frame(height: 140)
    }

    private func partFormat(_ part: Int) -> String {
        unit == .miles ? String(format: ".%02d", part) : "\(part) m"
    }

    private func set(_ parts: Int) {
        let value = Double(parts) / Double(partsPerUnit) * unit.meters
        meters = min(max(value, IntervalDraft.distanceRange.lowerBound), IntervalDraft.distanceRange.upperBound)
    }
}

private func wheel<Values: RandomAccessCollection>(
    _ values: Values,
    value: Int,
    label: String,
    name: String,
    format: ((Int) -> String)? = nil,
    set: @escaping (Int) -> Void
) -> some View where Values.Element == Int {
    Picker(name, selection: Binding(get: { value }, set: set)) {
        ForEach(Array(values), id: \.self) { number in
            Text(format?(number) ?? "\(number) \(label)").tag(number)
        }
    }
    .pickerStyle(.wheel)
    .frame(maxWidth: .infinity)
    .clipped()
}

/// Adds a step, or a set of repeats where repeats can go.
struct IntervalAddStepMenu: View {
    let add: (IntervalDraft.Step) -> Void
    let addRepeat: (() -> Void)?

    var body: some View {
        Menu {
            ForEach(IntervalStepChoice.allCases) { choice in
                Button(choice.name, systemImage: choice.systemImage) { add(.new(choice)) }
            }
            Menu("Until you tap Next", systemImage: "hand.tap") {
                ForEach(IntervalStepChoice.allCases) { choice in
                    Button(choice.name, systemImage: choice.systemImage) { add(.new(choice, open: true)) }
                }
            }
            if let addRepeat {
                Divider()
                Button("Repeats", systemImage: "repeat", action: addRepeat)
            }
        } label: {
            Label("Add step", systemImage: "plus.circle.fill")
        }
    }
}

/// A step in the builder: its name and how long it lasts.
struct IntervalStepRow: View {
    let step: IntervalDraft.Step
    let unit: DistanceUnit

    var body: some View {
        Label {
            HStack {
                Text(step.choice.name)
                Spacer()
                Text(step.goal == .open ? "Until Next" : RunFormat.goal(step.goal, unit: unit))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: step.choice.systemImage)
                .foregroundStyle(step.choice == .work ? Color.accentColor : .secondary)
        }
    }
}

/// A set of repeats in the builder: how many times, and its steps in short.
struct IntervalRepeatRow: View {
    let block: IntervalDraft.Block
    let unit: DistanceUnit

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(block.repeatCount) ×")
                    .monospacedDigit()
                Text(block.steps.isEmpty ? "No steps yet" : block.steps.map { IntervalSummary.step($0.choice, goal: $0.goal, unit: unit) }.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "repeat")
                .foregroundStyle(Color.accentColor)
        }
    }
}

#Preview("New workout") {
    IntervalEditorView(editing: .new) { _ in }
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
}
