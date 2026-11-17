//
//  WorkoutBuilderView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// One of a workout's three parts, each changed on its own sheet.
enum WorkoutPart: String, Identifiable {
    case warmup
    case main
    case cooldown

    var id: Self { self }
}

/// "New Workout" and "Edit Workout": a name, then the three parts of a workout. The warm-up and cooldown
/// can be taken out; the main part is always there. Each part opens its own sheet. Nothing is stored until
/// Save.
struct WorkoutBuilderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers

    let editing: WorkoutEditing
    let saved: (IntervalPlan) -> Void

    @State private var draft: WorkoutDraft
    @State private var part: WorkoutPart?
    @State private var isConfirmingCancel = false
    private let original: WorkoutDraft
    /// A part's sheet to open straight away, for screenshots.
    private let opening: WorkoutPart?

    init(editing: WorkoutEditing, opening: WorkoutPart? = nil, saved: @escaping (IntervalPlan) -> Void) {
        self.editing = editing
        self.saved = saved
        self.opening = opening
        let draft = editing.plan.map { WorkoutDraft($0) } ?? .starter()
        self.original = draft
        _draft = State(initialValue: draft)
    }

    private var title: String { editing.plan == nil ? "New Workout" : "Edit Workout" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(draft.suggestedName(unit: unit), text: $draft.name)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        // Cut while typing, so what shows is what's saved.
                        .onChange(of: draft.name) { _, name in
                            if name.count > IntervalPlan.nameLimit { draft.name = String(name.prefix(IntervalPlan.nameLimit)) }
                        }
                } header: {
                    Text("Name")
                }

                Section {
                    endRow(.warmup, goal: draft.warmup)
                } header: {
                    Text("Warm-up")
                }

                Section {
                    mainRow
                } header: {
                    Text("Main workout")
                }

                Section {
                    endRow(.cooldown, goal: draft.cooldown)
                } header: {
                    Text("Cooldown")
                }

                Section {
                    IntervalTimelineBar(timeline: draft.timeline)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                } footer: {
                    Text("In all: \(RunFormat.intervalLength(draft.timeline, unit: unit))")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .traceScreen(editing.plan == nil ? "New workout" : "Edit workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        Trace.tap("Workout builder", "Cancel", ["changed": draft != original])
                        // Cancel sits beside Save, so a slip doesn't throw away the changes.
                        if draft != original {
                            isConfirmingCancel = true
                        } else {
                            dismiss()
                        }
                    }
                    .confirmationDialog("Discard your changes?", isPresented: $isConfirmingCancel, titleVisibility: .visible) {
                        Button("Discard Changes", role: .destructive) {
                            Trace.tap("Workout builder", "Discard your changes?: Discard Changes")
                            dismiss()
                        }
                        Button("Keep Editing", role: .cancel) {
                            Trace.tap("Workout builder", "Discard your changes?: Keep Editing")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Trace.tap("Workout builder", "Save", ["main": draft.main.type.rawValue])
                        save()
                    }
                }
            }
            // Swiping the sheet away would lose the changes, so it takes Cancel once there are some.
            .interactiveDismissDisabled(draft != original)
            .sheet(item: $part) { part in
                switch part {
                case .warmup, .cooldown:
                    WorkoutEndSheet(
                        part: part,
                        goal: (part == .warmup ? draft.warmup : draft.cooldown) ?? WorkoutDraft.defaultEnd,
                        isAdding: (part == .warmup ? draft.warmup : draft.cooldown) == nil,
                        unit: unit
                    ) { goal in
                        if part == .warmup { draft.warmup = goal } else { draft.cooldown = goal }
                    }
                case .main:
                    WorkoutMainSheet(main: draft.main, hasCooldown: draft.cooldown != nil, unit: unit) { draft.main = $0 }
                }
            }
            // Keyed on the part: the sheet can be built before the part to open on reaches it.
            .task(id: opening) {
                guard let opening else { return }
                // Wait for this sheet to finish sliding up, or the part's sheet over it never shows.
                try? await Task.sleep(for: .milliseconds(700))
                part = opening
            }
        }
    }

    // MARK: Rows

    /// The warm-up or cooldown, or a button to add it back.
    @ViewBuilder
    private func endRow(_ part: WorkoutPart, goal: IntervalGoal?) -> some View {
        let name = part == .warmup ? "Warm-up" : "Cooldown"
        Button {
            Trace.tap("Workout builder", goal == nil ? "Add \(part.rawValue)" : part.rawValue.capitalized)
            self.part = part
        } label: {
            if let goal {
                WorkoutPartRow(systemImage: part == .warmup ? "sunrise" : "wind", title: name, detail: Self.endDetail(goal, unit: unit))
            } else {
                Label("Add \(name.lowercased())", systemImage: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
        .tint(.primary)
    }

    /// The main part: its type and amount, or for intervals the repeats and each step.
    private var mainRow: some View {
        Button {
            Trace.tap("Workout builder", "Main workout")
            part = .main
        } label: {
            switch draft.main {
            case .time(let seconds):
                WorkoutPartRow(systemImage: WorkoutType.time.systemImage, title: "Timed run", detail: WorkoutDistance.text(of: .time(seconds), unit: unit))
            case .distance(let meters):
                WorkoutPartRow(systemImage: WorkoutType.distance.systemImage, title: "Distance run", detail: WorkoutDistance.text(meters, preferred: unit))
            case .free:
                WorkoutPartRow(systemImage: WorkoutType.free.systemImage, title: "Free run", detail: "Until you tap Next")
            case .intervals(let intervals):
                IntervalsPartRow(intervals: intervals, unit: unit)
            }
        }
        .tint(.primary)
    }

    /// "10 min", "1 km", or "Until you tap Next".
    static func endDetail(_ goal: IntervalGoal, unit: DistanceUnit) -> String {
        if case .open = goal { return "Until you tap Next" }
        return WorkoutDistance.text(of: goal, unit: unit)
    }

    private func save() {
        let plan = draft.save(replacing: editing.plan, unit: unit, in: modelContext)
        dismiss()
        saved(plan)
    }
}

/// A part of the workout in the builder: an icon, its name, how it ends, and a chevron to change it.
struct WorkoutPartRow: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: LayoutMetrics.sectionSpacing) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            PartChevron()
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Changes it")
    }
}

/// Intervals in the builder: "Repeat 4 times", then work and recover under a bar that shows they repeat.
private struct IntervalsPartRow: View {
    let intervals: WorkoutMain.Intervals
    let unit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: LayoutMetrics.sectionSpacing) {
                Image(systemName: "repeat")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                Text(intervals.repeats == 1 ? "Once" : "Repeat \(intervals.repeats) times")
                    .font(.headline)
                Spacer(minLength: 0)
                PartChevron()
            }
            Divider()
            HStack(spacing: 14) {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                VStack(spacing: 10) {
                    step("Work", intervals.work)
                    step("Recover", intervals.recovery)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Changes the intervals")
    }

    private func step(_ name: String, _ goal: IntervalGoal) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(WorkoutBuilderView.endDetail(goal, unit: unit))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}

private struct PartChevron: View {
    var body: some View {
        Image(systemName: "chevron.forward")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

// MARK: - Warm-up and cooldown

/// The warm-up or cooldown: how it ends, and a way to take it out.
struct WorkoutEndSheet: View {
    @Environment(\.dismiss) private var dismiss

    let part: WorkoutPart
    let isAdding: Bool
    let unit: DistanceUnit
    let done: (IntervalGoal?) -> Void

    @State private var goal: IntervalGoal?
    @State private var ending: WorkoutEnding

    init(part: WorkoutPart, goal: IntervalGoal, isAdding: Bool, unit: DistanceUnit, done: @escaping (IntervalGoal?) -> Void) {
        self.part = part
        self.isAdding = isAdding
        self.unit = unit
        self.done = done
        _goal = State(initialValue: goal)
        _ending = State(initialValue: WorkoutEnding(goal))
    }

    private var name: String { part == .warmup ? "Warm-up" : "Cooldown" }

    var body: some View {
        NavigationStack {
            Form {
                WorkoutEndFields(
                    goal: $goal,
                    ending: $ending,
                    unit: unit,
                    question: "How does it end?",
                    defaultSeconds: 10 * 60,
                    defaultMeters: { $0 == .miles ? 1_609.344 : 1_000 },
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

                if !isAdding {
                    Section {
                        Button(role: .destructive) {
                            Trace.tap(name, "Remove \(name.lowercased())")
                            done(nil)
                            dismiss()
                        } label: {
                            Text("Remove \(name.lowercased())")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .traceScreen(name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        Trace.tap(name, "Cancel")
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isAdding ? "Add" : "Done") {
                        Trace.tap(name, isAdding ? "Add" : "Done", ["ending": ending.rawValue])
                        done(goal)
                        dismiss()
                    }
                    .disabled(goal == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Main workout

/// The main part: a time, a distance, a free run, or intervals.
struct WorkoutMainSheet: View {
    @Environment(\.dismiss) private var dismiss

    let hasCooldown: Bool
    let unit: DistanceUnit
    let done: (WorkoutMain) -> Void

    @State private var type: WorkoutType
    // Each type keeps what was set on it, so trying another type and coming back loses nothing.
    @State private var time: IntervalGoal?
    @State private var timeEnding = WorkoutEnding.time
    @State private var distance: IntervalGoal?
    @State private var distanceEnding = WorkoutEnding.distance
    @State private var work: IntervalGoal?
    @State private var workEnding: WorkoutEnding
    @State private var recovery: IntervalGoal?
    @State private var recoveryEnding: WorkoutEnding
    @State private var repeats: Int

    init(main: WorkoutMain, hasCooldown: Bool, unit: DistanceUnit, done: @escaping (WorkoutMain) -> Void) {
        self.hasCooldown = hasCooldown
        self.unit = unit
        self.done = done
        _type = State(initialValue: main.type)
        var time = IntervalGoal.time(30 * 60)
        var distance = IntervalGoal.distance(meters: unit == .miles ? 3 * 1_609.344 : 5_000)
        var intervals = WorkoutMain.Intervals(work: .time(5 * 60), recovery: .time(2 * 60), repeats: 4)
        switch main {
        case .time(let seconds): time = .time(seconds)
        case .distance(let meters): distance = .distance(meters: meters)
        case .free: break
        case .intervals(let set): intervals = set
        }
        _time = State(initialValue: time)
        _distance = State(initialValue: distance)
        _work = State(initialValue: intervals.work)
        _workEnding = State(initialValue: WorkoutEnding(intervals.work))
        _recovery = State(initialValue: intervals.recovery)
        _recoveryEnding = State(initialValue: WorkoutEnding(intervals.recovery))
        _repeats = State(initialValue: intervals.repeats)
    }

    /// The main part as set, or nil while a number is missing.
    private var main: WorkoutMain? {
        switch type {
        case .time:
            if case .time(let seconds) = time { return .time(seconds) }
            return nil
        case .distance:
            if case .distance(let meters) = distance { return .distance(meters: meters) }
            return nil
        case .free:
            return .free
        case .intervals:
            guard let work, let recovery else { return nil }
            return .intervals(.init(work: work, recovery: recovery, repeats: repeats))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Main workout", selection: $type.traced("Main workout", "Type") { $0.rawValue }) {
                        Text("Time").tag(WorkoutType.time)
                        Text("Distance").tag(WorkoutType.distance)
                        Text("Free").tag(WorkoutType.free)
                        Text("Intervals").tag(WorkoutType.intervals)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    WorkoutSheetQuestion(text: "What's the main part?")
                }

                switch type {
                case .time:
                    WorkoutEndFields(goal: $time, ending: $timeEnding, unit: unit, endings: [.time], defaultSeconds: 30 * 60, trace: "Main time") { _ in
                        hasCooldown ? "Run for this long, then the cooldown starts." : "You'll hear when you reach this. Keep going after it if you like."
                    }
                case .distance:
                    WorkoutEndFields(goal: $distance, ending: $distanceEnding, unit: unit, endings: [.distance], defaultMeters: { $0 == .miles ? 3 * 1_609.344 : 5_000 }, trace: "Main distance") { _ in
                        hasCooldown ? "Run this far, then the cooldown starts." : "You'll hear when you reach this. Keep going after it if you like."
                    }
                case .free:
                    Section {
                        Label("Run as long as you like.", systemImage: "figure.run")
                    } footer: {
                        Text(hasCooldown
                            ? "Tap Next on the run screen, your Lock Screen or your Apple Watch to start the cooldown."
                            : "Finish the run when you're done.")
                    }
                case .intervals:
                    Section {
                        Stepper(value: $repeats.traced("Main workout", "Repeats"), in: IntervalBlock.repeatRange) {
                            Text(repeats == 1 ? "Once" : "\(repeats) times")
                                .monospacedDigit()
                        }
                    } header: {
                        WorkoutSheetQuestion(text: "Repeat")
                    }
                    WorkoutEndFields(
                        goal: $work,
                        ending: $workEnding,
                        unit: unit,
                        question: "Work",
                        defaultSeconds: 5 * 60,
                        defaultMeters: { $0 == .miles ? 402.336 : 400 },
                        trace: "Work"
                    ) { ending in
                        ending == .manual ? "The hard part. Tap Next when you're done with it." : "The hard part. Recover starts on its own when you reach this."
                    }
                    WorkoutEndFields(
                        goal: $recovery,
                        ending: $recoveryEnding,
                        unit: unit,
                        question: "Recover",
                        defaultSeconds: 2 * 60,
                        defaultMeters: { $0 == .miles ? 402.336 : 400 },
                        trace: "Recover"
                    ) { ending in
                        ending == .manual ? "Easy, or walk. Tap Next when you're ready to go again." : "Easy, or walk. The next one starts on its own when you reach this."
                    }
                }
            }
            .navigationTitle("Main workout")
            .navigationBarTitleDisplayMode(.inline)
            .traceScreen("Main workout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        Trace.tap("Main workout", "Cancel")
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Trace.tap("Main workout", "Done", ["type": type.rawValue])
                        if let main { done(main) }
                        dismiss()
                    }
                    .disabled(main == nil)
                }
            }
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
private struct WorkoutSheetQuestion: View {
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
    @State private var distanceUnit = DistanceUnit.kilometers
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
                VStack(alignment: .leading, spacing: 12) {
                    NumberBox(title: "Distance", text: $amount, allowsDecimal: true)
                    Picker("Unit", selection: $distanceUnit.traced(trace, "Unit") { $0.rawValue }) {
                        Text("Kilometers").tag(DistanceUnit.kilometers)
                        Text("Miles").tag(DistanceUnit.miles)
                    }
                    .pickerStyle(.segmented)
                }
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
        .onChange(of: distanceUnit) { update() }
    }

    /// The boxes start from the part as it is, and from sensible amounts for the ways it doesn't end.
    private func fill() {
        guard !isFilled else { return }
        isFilled = true
        var time = defaultSeconds
        distanceUnit = unit
        var meters = defaultMeters(unit)
        switch goal {
        case .time(let value): time = value
        case .distance(let value):
            meters = value
            distanceUnit = WorkoutDistance.unit(for: value, preferred: unit)
        case .open, nil: break
        }
        let whole = Int(time.rounded())
        minutes = "\(whole / 60)"
        seconds = "\(whole % 60)"
        amount = WorkoutDistance.amount(meters, in: distanceUnit)
    }

    private func update() {
        guard isFilled else { return }
        switch ending {
        case .time:
            let total = (Int(minutes) ?? 0) * 60 + (Int(seconds) ?? 0)
            goal = total > 0 ? .time(TimeInterval(total)) : nil
        case .distance:
            let value = Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0
            goal = value > 0 ? .distance(meters: value * distanceUnit.meters) : nil
        case .manual:
            goal = .open
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

#Preview("New workout") {
    WorkoutBuilderView(editing: .new) { _ in }
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
}
