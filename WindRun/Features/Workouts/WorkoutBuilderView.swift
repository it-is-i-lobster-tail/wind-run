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
    @State private var suggestedIcon = WorkoutIcon.fallback
    @State private var matchedName: String?
    @State private var pickingIcon = false
    @State private var saving = false
    private let original: WorkoutDraft
    /// A part's page to open straight away, for screenshots.
    private let opening: WorkoutPart?

    init(editing: WorkoutEditing, opening: WorkoutPart? = nil, saved: @escaping (IntervalPlan) -> Void) {
        self.editing = editing
        self.saved = saved
        self.opening = opening
        // The runner's unit, for a new workout and for one saved before workouts kept their own.
        let preferred = DistanceUnit.current()
        let draft = editing.plan.map { WorkoutDraft($0, preferred: preferred) } ?? .starter(unit: preferred)
        if let plan = editing.plan, plan.iconIsManualValue != true, let icon = plan.iconValue {
            _suggestedIcon = State(initialValue: icon)
            _matchedName = State(initialValue: draft.iconQuery)
        }
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

    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section {
                    HStack {
                        Button {
                            pickingIcon = true
                        } label: {
                            WorkoutGlyph(value: draft.manualIcon ?? suggestedIcon)
                                .font(.title2)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Choose workout icon")
                        .accessibilityValue(iconDescription)
                        TextField(draft.suggestedName, text: $draft.name)
                            .accessibilityLabel("Workout name")
                            .focused($isNameFocused)
                            .textInputAutocapitalization(.words)
                            .submitLabel(.done)
                            // Cut while typing, so what shows is what's saved.
                            .onChange(of: draft.name) { previous, name in
                                if name.count > IntervalPlan.nameLimit {
                                    draft.name = String(name.prefix(IntervalPlan.nameLimit))
                                    return
                                }
                                // Title case: "of", "the" and such go lowercase once the next word starts.
                                let titled = TitleCase.typed(name, after: previous)
                                if titled != name { draft.name = titled }
                            }
                    }
                } header: {
                    Text("Name")
                }
                Section {
                    Picker("Workout Type", selection: $draft.sport) {
                        ForEach(WorkoutSport.allCases) { sport in
                            Label(sport.name, systemImage: sport.systemImage).tag(sport)
                        }
                    }
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
                    if draft.sport == .running { paceRow }
                } header: {
                    Text("Main workout")
                }

                Section {
                    endRow(.cooldown, goal: draft.cooldown)
                } header: {
                    Text("Cooldown")
                } footer: {
                    Text("In all: \(WorkoutDistance.length(draft.timeline, in: unit))")
                }

                Section {
                    displayRow
                        .id(WorkoutPart.display)
                } header: {
                    Text("Display")
                } footer: {
                    Text("What your iPhone, Apple Watch and Lock Screen show during this workout.")
                }
            }
            #if DEBUG
            .task {
                guard TypingDemo.text != nil else { return }
                isNameFocused = true
                await TypingDemo.type(into: { draft.name = $0 }, reading: { draft.name })
            }
            .task {
                guard WorkoutsDemo.scrollsToDisplay else { return }
                try? await Task.sleep(for: .milliseconds(900))
                proxy.scrollTo(WorkoutPart.display, anchor: .bottom)
            }
            #endif
            }
            .sheet(isPresented: $pickingIcon) {
                WorkoutIconPicker(name: draft.iconQuery, automaticIcon: suggestedIcon, manualIcon: $draft.manualIcon)
            }
            .task(id: draft.iconQuery) {
                let name = draft.iconQuery
                guard matchedName != name else { return }
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                let icon = await WorkoutIconMatcher.shared.symbol(for: name)
                guard !Task.isCancelled, draft.iconQuery == name else { return }
                suggestedIcon = icon
                matchedName = name
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
            .interactiveDismissDisabled(saving || draft != original)
            .disabled(saving)
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
                    WorkoutMainPage(main: draft.main, hasCooldown: draft.cooldown != nil, unit: unit, sport: draft.sport) { draft.main = $0 }
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
                WorkoutPartRow(systemImage: draft.main.type.systemImage, title: draft.main.type.name(for: draft.sport), detail: WorkoutDistance.endDetail(goal, unit: unit))
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

    private var iconDescription: String {
        let icon = draft.manualIcon ?? suggestedIcon
        let title = WorkoutSymbol.catalog.first { $0.id == icon }?.title ?? icon
        return draft.manualIcon == nil ? "Automatic, " + title : title
    }

    private func save() {
        guard !saving else { return }
        saving = true
        Task {
            let name = draft.iconQuery
            var automatic = suggestedIcon
            if draft.manualIcon == nil && matchedName != name {
                automatic = await WorkoutIconMatcher.shared.symbol(for: name)
            }
            let plan = draft.save(replacing: editing.plan, in: modelContext, automaticIcon: automatic)
            dismiss()
            saved(plan)
        }
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

#Preview("New workout") {
    WorkoutBuilderView(editing: .new) { _ in }
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
}
