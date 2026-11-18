//
//  WorkoutBuilderView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// One of a workout's three parts, each changed on its own page.
enum WorkoutPart: String, Identifiable {
    case warmup
    case main
    /// The main part's target pace.
    case pace
    case cooldown
    /// The display its runs show.
    case display

    var id: Self { self }
}

/// "New Workout" and "Edit Workout": a name, then the three parts of a workout. The warm-up and cooldown
/// can be taken out; the main part is always there. Each part pushes its own page, which changes the workout as
/// the runner goes, so the row reads the change on the way back. Nothing is stored until Save, and Cancel
/// still throws it all away.
struct WorkoutBuilderView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let editing: WorkoutEditing
    let saved: (IntervalPlan) -> Void

    @State private var draft: WorkoutDraft
    @State private var part: WorkoutPart?
    @State private var isConfirmingCancel = false
    private let original: WorkoutDraft
    /// A part's page to open straight away, for screenshots.
    private let opening: WorkoutPart?

    init(editing: WorkoutEditing, opening: WorkoutPart? = nil, saved: @escaping (IntervalPlan) -> Void) {
        self.editing = editing
        self.saved = saved
        self.opening = opening
        // The runner's unit, for a new workout and for one saved before workouts kept their own.
        let preferred = UserDefaults.standard.string(forKey: DistanceUnit.storageKey).flatMap(DistanceUnit.init(rawValue:)) ?? .kilometers
        let draft = editing.plan.map { WorkoutDraft($0, preferred: preferred) } ?? .starter(unit: preferred)
        self.original = draft
        #if DEBUG
        if WorkoutsDemo.switchesToMiles {
            var switched = draft
            switched.unit = .miles
            _draft = State(initialValue: switched)
            return
        }
        #endif
        _draft = State(initialValue: draft)
    }

    private var title: String { editing.plan == nil ? "New Workout" : "Edit Workout" }

    /// The workout's one unit, which every distance and the pace here are shown and typed in.
    private var unit: DistanceUnit { draft.unit }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section {
                    TextField(WorkoutDraft.defaultName, text: $draft.name)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        // Cut while typing, so what shows is what's saved.
                        .onChange(of: draft.name) { _, name in
                            if name.count > IntervalPlan.nameLimit { draft.name = String(name.prefix(IntervalPlan.nameLimit)) }
                        }
                } header: {
                    Text("Name")
                }
                // The unit pill sits just under the name it belongs with.
                .listSectionSpacing(10)

                Section {
                    // Switching converts every distance and the pace as they read; what's kept stays exact.
                    Picker("Units", selection: $draft.unit.traced("Workout builder", "Units") { $0.rawValue }) {
                        Text("Kilometers").tag(DistanceUnit.kilometers)
                        Text("Miles").tag(DistanceUnit.miles)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                // A small gap, not a section's worth, before the warm-up.
                .listSectionSpacing(.compact)

                Section {
                    endRow(.warmup, goal: draft.warmup)
                } header: {
                    Text("Warm-up")
                }

                Section {
                    mainRow
                    paceRow
                } header: {
                    Text("Main workout")
                }

                Section {
                    endRow(.cooldown, goal: draft.cooldown)
                } header: {
                    Text("Cooldown")
                } footer: {
                    Text("In all: \(RunFormat.intervalLength(draft.timeline, unit: unit) { WorkoutDistance.text($0, in: unit) })")
                }

                Section {
                    displayRow
                        .id(WorkoutPart.display)
                } header: {
                    Text("Display")
                } footer: {
                    Text("What your run screen, Apple Watch and Lock Screen show during this workout.")
                }
            }
            #if DEBUG
            .task {
                guard WorkoutsDemo.scrollsToDisplay else { return }
                try? await Task.sleep(for: .milliseconds(900))
                proxy.scrollTo(WorkoutPart.display, anchor: .bottom)
            }
            #endif
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
            .navigationDestination(item: $part) { part in
                switch part {
                case .warmup, .cooldown:
                    WorkoutEndPage(
                        part: part,
                        goal: (part == .warmup ? draft.warmup : draft.cooldown) ?? WorkoutDraft.defaultEnd,
                        unit: unit
                    ) { goal in
                        if part == .warmup { draft.warmup = goal } else { draft.cooldown = goal }
                    }
                case .pace:
                    WorkoutPacePage(pace: draft.targetPace, unit: unit) { draft.targetPace = $0 }
                case .main:
                    WorkoutMainPage(main: draft.main, hasCooldown: draft.cooldown != nil, unit: unit) { draft.main = $0 }
                case .display:
                    DisplayPickerPage(selection: draft.displayScreenID, tracedAs: "workout") { draft.displayScreenID = $0 }
                }
            }
            // Keyed on the part: the sheet can be built before the part to open on reaches it.
            .task(id: opening) {
                guard let opening else { return }
                // Wait for this sheet to finish sliding up, or the page doesn't push.
                try? await Task.sleep(for: .milliseconds(700))
                part = opening
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
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
                WorkoutPartRow(systemImage: part == .warmup ? "sunrise" : "wind", title: name, detail: WorkoutDistance.endDetail(goal, unit: unit))
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
            if case .intervals(let intervals) = draft.main {
                IntervalsPartRow(intervals: intervals, unit: unit)
            } else if let goal = draft.main.singleGoal {
                WorkoutPartRow(systemImage: draft.main.type.systemImage, title: draft.main.type.name, detail: WorkoutDistance.endDetail(goal, unit: unit))
            }
        }
        .tint(.primary)
    }

    /// "Add Target Pace", or the pace with a way to change it.
    private var paceRow: some View {
        Button {
            Trace.tap("Workout builder", draft.targetPace == nil ? "Add target pace" : "Target pace")
            part = .pace
        } label: {
            HStack {
                if let pace = draft.targetPace {
                    Text("Target pace")
                    Spacer()
                    Text(WorkoutDistance.paceText(pace, unit: unit))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Add Target Pace")
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                }
                PartChevron()
            }
            .contentShape(.rect)
        }
        .tint(.primary)
    }

    /// The display the workout's runs show, with its preview: the default unless it picked another.
    private var displayRow: some View {
        let library = DisplayLibrary.current
        let screen = library.screen(id: draft.displayScreenID)
        return Button {
            Trace.tap("Workout builder", "Display")
            part = .display
        } label: {
            HStack {
                DisplayRow(screen: screen, unit: unit, isDefault: library.isDefault(screen.id))
                Spacer()
                PartChevron()
            }
            .contentShape(.rect)
        }
        .tint(.primary)
    }

    private func save() {
        let plan = draft.save(replacing: editing.plan, in: modelContext)
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
                    .font(.subheadline)
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
                    step("Recovery", intervals.recovery)
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
            Text(WorkoutDistance.endDetail(goal, unit: unit))
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

// MARK: - Main workout

/// The main part: a time, a distance, a free run, or intervals. Each change goes straight into the workout.
struct WorkoutMainPage: View {
    let hasCooldown: Bool
    let unit: DistanceUnit
    let apply: (WorkoutMain) -> Void

    @State private var type: WorkoutType
    // Each type keeps what was set on it, so trying another type and coming back loses nothing.
    @State private var time: IntervalGoal?
    @State private var timeEnding = WorkoutEnding.time
    @State private var distance: IntervalGoal?
    @State private var distanceEnding = WorkoutEnding.distance
    // All time or all distance, with what was typed for each kept.
    @State private var intervals: IntervalSetEntry
    @State private var repeats: Int

    init(main: WorkoutMain, hasCooldown: Bool, unit: DistanceUnit, apply: @escaping (WorkoutMain) -> Void) {
        self.hasCooldown = hasCooldown
        self.unit = unit
        self.apply = apply
        _type = State(initialValue: main.type)
        var time = IntervalGoal.time(30 * 60)
        var distance = IntervalGoal.distance(meters: Self.defaultDistanceMeters(unit))
        var intervals = WorkoutMain.Intervals.starter
        switch main {
        case .time(let seconds): time = .time(seconds)
        case .distance(let meters): distance = .distance(meters: meters)
        case .free: break
        case .intervals(let set): intervals = set
        }
        _time = State(initialValue: time)
        _distance = State(initialValue: distance)
        _intervals = State(initialValue: IntervalSetEntry(intervals, unit: unit))
        _repeats = State(initialValue: intervals.repeats)
    }

    /// What a distance run starts at in each unit: 3 mi or 5 km.
    static func defaultDistanceMeters(_ unit: DistanceUnit) -> Double {
        unit == .miles ? 3 * 1_609.344 : 5_000
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
            return intervals.intervals(repeats: repeats).map { .intervals($0) }
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Main workout", selection: $type.traced("Main workout", "Type") { $0.rawValue }) {
                    Text("Distance").tag(WorkoutType.distance)
                    Text("Free").tag(WorkoutType.free)
                    Text("Intervals").tag(WorkoutType.intervals)
                    Text("Time").tag(WorkoutType.time)
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
                WorkoutEndFields(goal: $distance, ending: $distanceEnding, unit: unit, endings: [.distance], defaultMeters: { Self.defaultDistanceMeters($0) }, trace: "Main distance") { _ in
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
                        Text(repeats == 1 ? "Repeat once" : "Repeat \(repeats) times")
                            .monospacedDigit()
                    }
                }
                Section {
                    Picker("Intervals by", selection: $intervals.kind.traced("Main workout", "Intervals by") { $0.rawValue }) {
                        Text("Time").tag(IntervalSetEntry.Kind.time)
                        Text("Distance").tag(IntervalSetEntry.Kind.distance)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    switch intervals.kind {
                    case .time:
                        IntervalAmountRow(title: "Work", text: $intervals.workTime, kind: .time)
                        IntervalAmountRow(title: "Recovery", text: $intervals.recoveryTime, kind: .time)
                    case .distance:
                        IntervalAmountRow(title: "Work", text: $intervals.workDistance, kind: .distance)
                        IntervalAmountRow(title: "Recovery", text: $intervals.recoveryDistance, kind: .distance)
                    }
                } header: {
                    HStack {
                        Spacer()
                        switch intervals.kind {
                        case .time:
                            Text("min : sec")
                        case .distance:
                            Text(unit.name)
                        }
                    }
                    .font(.footnote)
                    .textCase(nil)
                } footer: {
                    if let total = intervals.total(repeats: repeats) {
                        Text("\(total) total")
                    }
                }
            }
        }
        .navigationTitle("Main workout")
        .navigationBarTitleDisplayMode(.inline)
        .traceScreen("Main workout")
        // While a box is empty the workout keeps its last main part.
        .onChange(of: main) { _, main in
            if let main { apply(main) }
        }
    }
}

// MARK: - Target pace

/// The main part's target pace: one pace, or a range from faster to slower, per kilometer or mile as the
/// runner counts. Each change goes straight into the workout; Remove takes it out.
struct WorkoutPacePage: View {
    @Environment(\.dismiss) private var dismiss

    let unit: DistanceUnit
    /// Sets the pace, seconds per kilometer, or nil to take it out.
    let apply: (ClosedRange<TimeInterval>?) -> Void

    @State private var entry: PaceEntry

    init(pace: ClosedRange<TimeInterval>?, unit: DistanceUnit, apply: @escaping (ClosedRange<TimeInterval>?) -> Void) {
        self.unit = unit
        self.apply = apply
        _entry = State(initialValue: PaceEntry(pace, unit: unit))
    }

    var body: some View {
        Form {
            Section {
                Picker("Target pace", selection: $entry.isRange.traced("Target pace", "Kind") { $0 ? "range" : "single" }) {
                    Text("Single pace").tag(false)
                    Text("Pace range").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Main workout only")
            }

            Section {
                if entry.isRange {
                    PaceRow(title: "Faster pace", text: $entry.faster, unit: entry.unit)
                    PaceRow(title: "Slower pace", text: $entry.slower, unit: entry.unit)
                } else {
                    PaceRow(title: "Target pace", text: $entry.single, unit: entry.unit)
                }
            } footer: {
                if let pace = entry.pace {
                    Text("Target: \(WorkoutDistance.paceText(pace, unit: entry.unit))")
                }
            }

            Section {
                Button(role: .destructive) {
                    Trace.tap("Target pace", "Remove target pace")
                    apply(nil)
                    dismiss()
                } label: {
                    Text("Remove target pace")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Target Pace")
        .navigationBarTitleDisplayMode(.inline)
        .traceScreen("Target pace")
        // Added as it opens, so Back keeps a pace just added.
        .onAppear { if let pace = entry.pace { apply(pace) } }
        // While a box is empty or doesn't read as a pace, the workout keeps its last one.
        .onChange(of: entry.pace) { _, pace in
            if let pace { apply(pace) }
        }
    }
}

/// What the target pace page shows and how it reads back: m:ss per kilometer or mile, stored as seconds per
/// kilometer.
struct PaceEntry: Equatable {
    var isRange: Bool
    var single: String
    var faster: String
    var slower: String
    /// The workout's unit, which the boxes are in.
    let unit: DistanceUnit
    // Each box's pace in seconds per kilometer as the workout has it, kept until the box is changed, so opening
    // the page or switching the workout's unit never rounds it: only the boxes round to whole seconds.
    private var exactSingle: TimeInterval?
    private var exactFaster: TimeInterval?
    private var exactSlower: TimeInterval?

    /// The page for a workout's pace, or for a new one: 6:00 /km or 9:30 /mi to change from.
    init(_ pace: ClosedRange<TimeInterval>?, unit: DistanceUnit) {
        self.unit = unit
        let fallback = unit == .miles ? Self.perKilometer(9 * 60 + 30, unit: .miles) : 6 * 60
        let start = pace ?? fallback...fallback
        isRange = start.lowerBound != start.upperBound
        exactFaster = start.lowerBound
        exactSlower = start.upperBound
        let middle = isRange ? (start.lowerBound + start.upperBound) / 2 : start.lowerBound
        exactSingle = middle
        single = Self.text(middle, unit: unit)
        faster = Self.text(start.lowerBound, unit: unit)
        slower = Self.text(start.upperBound, unit: unit)
    }

    /// The pace as typed, seconds per kilometer, fastest first, or nil while a box doesn't read as a pace.
    var pace: ClosedRange<TimeInterval>? {
        if isRange {
            guard let fast = Self.value(faster, exact: exactFaster, unit: unit),
                  let slow = Self.value(slower, exact: exactSlower, unit: unit) else { return nil }
            return min(fast, slow)...max(fast, slow)
        }
        guard let one = Self.value(single, exact: exactSingle, unit: unit) else { return nil }
        return one...one
    }

    /// A box's pace, seconds per kilometer: its exact pace while it still shows it, or else what's typed.
    private static func value(_ text: String, exact: TimeInterval?, unit: DistanceUnit) -> TimeInterval? {
        if let exact, text == Self.text(exact, unit: unit) { return exact }
        return IntervalSetEntry.seconds(text).map { perKilometer($0, unit: unit) }
    }

    /// Seconds per kilometer from seconds per `unit`.
    static func perKilometer(_ seconds: TimeInterval, unit: DistanceUnit) -> TimeInterval {
        seconds * 1_000 / unit.meters
    }

    /// "8:45" for a pace per `unit`, from seconds per kilometer.
    static func text(_ secondsPerKilometer: TimeInterval, unit: DistanceUnit) -> String {
        WorkoutDistance.pacePerUnit(secondsPerKilometer, unit: unit)
    }
}

/// "Target pace", a filled box to type m:ss in, and "min/km" or "min/mi".
private struct PaceRow: View {
    let title: String
    @Binding var text: String
    let unit: DistanceUnit

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0:00", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(width: 64)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.fill.tertiary, in: .rect(cornerRadius: 10))
                .accessibilityLabel("\(title) per \(unit == .miles ? "mile" : "kilometer")")
            Text("min/\(unit.symbol)")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Intervals

/// The intervals card: work and recovery, both a time or both a distance in one unit. A time is typed as m:ss,
/// such as 5:00, and a distance as a number, such as 0.25. Each kind keeps what was typed, so switching
/// between them and back loses nothing.
struct IntervalSetEntry: Equatable {
    enum Kind: String {
        case time
        case distance
    }

    var kind: Kind
    var workTime: String
    var recoveryTime: String
    var workDistance: String
    var recoveryDistance: String
    /// The workout's unit, which the distances are typed in.
    let unit: DistanceUnit
    // The distances in meters as the workout has them, kept while their boxes still show them, so opening the
    // page never rounds them.
    private var exactWork: Double?
    private var exactRecovery: Double?

    /// The card for a saved set. One from before sets were all one kind, or with a step that waited for
    /// Next, takes its kind from the work and starts the odd step from a sensible amount.
    init(_ intervals: WorkoutMain.Intervals, unit: DistanceUnit) {
        var kind = Kind.time
        var workSeconds = WorkoutMain.Intervals.starterWorkSeconds
        var recoverySeconds = WorkoutMain.Intervals.starterRecoverySeconds
        // A quarter mile or 400 m.
        var workMeters = unit == .miles ? 402.336 : 400
        var recoveryMeters = workMeters
        switch (intervals.work, intervals.recovery) {
        case (.time(let work), .time(let recovery)):
            workSeconds = work
            recoverySeconds = recovery
        case (.time(let work), _):
            workSeconds = work
        case (.distance(let work), .distance(let recovery)):
            kind = .distance
            workMeters = work
            recoveryMeters = recovery
        case (.distance(let work), _):
            kind = .distance
            workMeters = work
            recoveryMeters = work
        case (.open, .time(let recovery)):
            recoverySeconds = recovery
        case (.open, .distance(let recovery)):
            kind = .distance
            workMeters = recovery
            recoveryMeters = recovery
        case (.open, .open):
            break
        }
        self.kind = kind
        self.unit = unit
        workTime = Self.timeText(workSeconds)
        recoveryTime = Self.timeText(recoverySeconds)
        workDistance = WorkoutDistance.amount(workMeters, in: unit)
        recoveryDistance = WorkoutDistance.amount(recoveryMeters, in: unit)
        exactWork = workMeters
        exactRecovery = recoveryMeters
    }

    /// The set as typed, or nil while a box is empty or doesn't read as a time or distance.
    func intervals(repeats: Int) -> WorkoutMain.Intervals? {
        switch kind {
        case .time:
            guard let work = Self.seconds(workTime), let recovery = Self.seconds(recoveryTime) else { return nil }
            return .init(work: .time(work), recovery: .time(recovery), repeats: repeats)
        case .distance:
            guard let work = meters(workDistance, exact: exactWork), let recovery = meters(recoveryDistance, exact: exactRecovery) else { return nil }
            return .init(work: .distance(meters: work), recovery: .distance(meters: recovery), repeats: repeats)
        }
    }

    /// "14 min" or "2.5 km": the work and recovery, repeated.
    func total(repeats: Int) -> String? {
        guard let set = intervals(repeats: repeats) else { return nil }
        switch (set.work, set.recovery) {
        case (.time(let work), .time(let recovery)):
            return RunFormat.goal(.time(Double(repeats) * (work + recovery)), unit: unit)
        case (.distance(let work), .distance(let recovery)):
            return "\(WorkoutDistance.amount(Double(repeats) * (work + recovery), in: unit)) \(unit.symbol)"
        default:
            return nil
        }
    }

    /// A box's distance in meters: the exact one while the box still shows it, or else what's typed.
    private func meters(_ text: String, exact: Double?) -> Double? {
        if let exact, text == WorkoutDistance.amount(exact, in: unit) { return exact }
        return Self.amount(text).map { $0 * unit.meters }
    }

    /// "5:00" for 300 seconds.
    static func timeText(_ seconds: TimeInterval) -> String {
        WorkoutDistance.minutesSeconds(seconds)
    }

    /// The seconds in "5:00", "1:30" or "5" (minutes), or nil when it's empty, zero, or the seconds run past 59.
    static func seconds(_ text: String) -> TimeInterval? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count) else { return nil }
        let minutes = parts[0].isEmpty ? 0 : Int(parts[0])
        let seconds = parts.count == 2 ? (parts[1].isEmpty ? 0 : Int(parts[1])) : 0
        guard let minutes, let seconds, minutes >= 0, (0..<60).contains(seconds) else { return nil }
        let total = minutes * 60 + seconds
        return total > 0 ? TimeInterval(total) : nil
    }

    /// The number in "0.25" or "0,25", or nil when it's empty or zero.
    static func amount(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")), value > 0 else { return nil }
        return value
    }
}

/// "Work" or "Recovery" with a filled box on the right to type the amount in.
private struct IntervalAmountRow: View {
    let title: String
    @Binding var text: String
    let kind: IntervalSetEntry.Kind

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(kind == .time ? "0:00" : "0", text: $text)
                .keyboardType(kind == .time ? .numbersAndPunctuation : .decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(width: 88)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.fill.tertiary, in: .rect(cornerRadius: 10))
                .accessibilityLabel(title)
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

#Preview("New workout") {
    WorkoutBuilderView(editing: .new) { _ in }
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
}
