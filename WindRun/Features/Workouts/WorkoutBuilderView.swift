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

struct MissingWorkoutWaypoint: Equatable {
    let part: WorkoutPart
    let field: String?
    let message: String

    static func first(in draft: WorkoutDraft) -> Self? {
        func missing(_ goal: IntervalGoal?) -> Bool {
            if case .waypoint(let end) = goal { return end.point == nil }
            return false
        }
        if missing(draft.warmup) {
            return Self(part: .warmup, field: nil, message: "Choose a waypoint for the end of your warm-up.")
        }
        if case .waypointIntervals(let pairs) = draft.main {
            if pairs.allSatisfy(\.isEmpty) {
                return Self(part: .main, field: "Work - 1", message: "Choose a work waypoint and a recovery waypoint for at least one repeat.")
            }
            for (index, pair) in pairs.enumerated() where !pair.isEmpty {
                let field: String
                if pair.work?.point == nil { field = "Work - \(index + 1)" }
                else if pair.recovery?.point == nil { field = "Recovery - \(index + 1)" }
                else { continue }
                return Self(part: .main, field: field, message: "Choose a waypoint for \(field).")
            }
        }
        if missing(draft.main.singleGoal) {
            return Self(part: .main, field: nil, message: "Choose a waypoint for the end of your main workout.")
        }
        if missing(draft.cooldown) {
            return Self(part: .cooldown, field: nil, message: "Choose a waypoint for the end of your cooldown.")
        }
        return nil
    }
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

    @State private var revealedPhase: WorkoutPart?
    @State private var draft: WorkoutDraft
    @State private var editingRoute = false
    @State private var routeDraft = WaypointWorkout(name: "", points: [])
    @State private var part: WorkoutPart?
    @State private var missingWaypoint: MissingWorkoutWaypoint?
    @State private var isConfirmingCancel = false
    private let original: WorkoutDraft
    /// A part's page to open straight away, for screenshots.
    @State private var didOpenInitialPart = false
    private let opening: WorkoutPart?

    init(editing: WorkoutEditing, opening: WorkoutPart? = nil, saved: @escaping (IntervalPlan) -> Void) {
        self.editing = editing
        self.saved = saved
        self.opening = opening
        // The runner's unit, for a new workout and for one saved before workouts kept their own.
        let preferred = DistanceUnit.current()
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

    @FocusState private var isNameFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                Section {
                    TextField(draft.suggestedName, text: $draft.name)
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

                if draft.waypointRoute == nil {
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

                if draft.hasPinnedPhase {
                    Section { Toggle("Return to starting point", isOn: $draft.returnToStart) }
                }
                } else {
                    Section("Main workout") {
                        Button("Edit waypoint legs") {
                            if let route = draft.waypointRoute { routeDraft = route; editingRoute = true }
                        }
                        Button("Remove waypoint legs", role: .destructive) { draft.waypointRoute = nil }
                    }
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
        .interactiveDismissDisabled(draft != original)
        .navigationDestination(isPresented: $editingRoute) {
            WaypointPlanner(plan: $routeDraft)
                .onDisappear {
                    draft.waypointRoute = routeDraft.points.isEmpty ? nil : routeDraft
                }
        }
        .navigationDestination(item: $part) { part in
            Group {
                switch part {
                case .warmup, .cooldown:
                    WorkoutEndPage(
                        part: part,
                        goal: (part == .warmup ? draft.warmup : draft.cooldown) ?? WorkoutDraft.defaultEnd,
                        unit: unit
                    ) { goal in
                        if part == .warmup { draft.warmup = goal } else { draft.cooldown = goal }
                    }
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu("More", systemImage: "ellipsis") {
                                Button("Skip") {
                                    skipPhase(part)
                                    self.part = nil
                                }
                            }
                        }
                    }
                case .pace:
                    WorkoutPacePage(pace: draft.targetPace, unit: unit) { draft.targetPace = $0 }
                case .main:
                    WorkoutMainPage(main: draft.main, hasCooldown: draft.cooldown != nil, unit: unit, sport: draft.sport, missingField: missingWaypoint?.field) { draft.main = $0 }
                case .display:
                    DisplayPickerPage(selection: draft.displayScreenID, tracedAs: "workout") { draft.displayScreenID = $0 }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let issue = missingWaypoint, issue.part == part, issue == MissingWorkoutWaypoint.first(in: draft) {
                    WaypointIssueCard(message: issue.message)
                }
            }
            .environment(\.waypointSport, draft.sport)
            .environment(\.waypointSlots, waypointSlots)
        }
        .task(id: opening) {
            guard let opening, !didOpenInitialPart else { return }
            // Wait for the builder transition before pushing the demo page.
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            didOpenInitialPart = true
            if part == nil { part = opening }
        }
        .onChange(of: draft) {
            if let issue = missingWaypoint, issue != MissingWorkoutWaypoint.first(in: draft) { missingWaypoint = nil }
        }
        .onChange(of: part) { _, part in
            revealedPhase = nil
            if part == nil { missingWaypoint = nil }
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private var waypointSlots: [WaypointSlot] {
        var slots: [WaypointSlot] = []
        if case .waypoint(let end) = draft.warmup {
            slots.append(.init(phase: "Warm-Up End", end: end) { draft.warmup = .waypoint($0) })
        }
        if case .waypoint(let end) = draft.main {
            slots.append(.init(phase: "Main End", end: end) { draft.main = .waypoint($0) })
        } else if let pairs = draft.main.waypointPairs {
            for (index, pair) in pairs.enumerated() {
                for recovery in [false, true] {
                    let name = recovery ? "Recovery - \(index + 1)" : "Work - \(index + 1)"
                    slots.append(.init(phase: name, end: recovery ? pair.recovery : pair.work) { value in
                        guard var current = draft.main.waypointPairs, current.indices.contains(index) else { return }
                        if recovery { current[index].recovery = value } else { current[index].work = value }
                        draft.main = .waypointIntervals(current)
                    })
                }
            }
        }
        if case .waypoint(let end) = draft.cooldown {
            slots.append(.init(phase: "Cooldown End", end: end) { draft.cooldown = .waypoint($0) })
        }
        return slots
    }

    // MARK: Rows

    private func skipPhase(_ part: WorkoutPart) {
        if part == .warmup, let goal = draft.warmup {
            draft.skipped.warmup = goal
            draft.warmup = nil
        } else if part == .cooldown, let goal = draft.cooldown {
            draft.skipped.cooldown = goal
            draft.cooldown = nil
        }
    }

    /// The warm-up or cooldown, or a button to add it back.
    @ViewBuilder
    private func endRow(_ part: WorkoutPart, goal: IntervalGoal?) -> some View {
        let name = part == .warmup ? "Warm-up" : "Cooldown"
        let activeKey: WritableKeyPath<WorkoutDraft, IntervalGoal?> = part == .warmup ? \.warmup : \.cooldown
        let skippedKey: WritableKeyPath<WorkoutDraft.SkippedPhases, IntervalGoal?> = part == .warmup ? \.warmup : \.cooldown
        let skippedGoal = draft.skipped[keyPath: skippedKey]
        PhaseSwipeRow(isOpen: Binding(get: { revealedPhase == part }, set: { open in
            revealedPhase = open ? part : nil
        }), enabled: goal != nil, skip: {
            revealedPhase = nil
            skipPhase(part)
        }, open: {
            if let skippedGoal {
                draft[keyPath: activeKey] = skippedGoal
                draft.skipped[keyPath: skippedKey] = nil
            } else {
                self.part = part
            }
        }) {
            if let goal {
                WorkoutPartRow(systemImage: part == .warmup ? "sunrise" : "wind", title: name, goal: goal, unit: unit)
            } else {
                Label(skippedGoal == nil ? "Add \(name.lowercased())" : "Include \(name.lowercased())", systemImage: "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    /// The main part: its type and amount, or for intervals the repeats and each step.
    private var mainRow: some View {
        Button {
            Trace.tap("Workout builder", "Main workout")
            part = .main
        } label: {
            if case .intervals(let intervals) = draft.main {
                IntervalsPartRow(intervals: intervals, unit: unit)
            } else if case .waypointIntervals(let pairs) = draft.main {
                WorkoutPartRow(systemImage: "repeat", title: "Waypoint intervals",
                               detail: pairs.count == 1 ? "1 work and recovery pair" : "\(pairs.count) work and recovery pairs")
            } else if let goal = draft.main.singleGoal {
                WorkoutPartRow(systemImage: draft.main.type.systemImage, title: draft.main.type.name(for: draft.sport), goal: goal, unit: unit)
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
        if let issue = MissingWorkoutWaypoint.first(in: draft) {
            missingWaypoint = issue
            part = issue.part
            return
        }
        let plan = draft.save(replacing: editing.plan, in: modelContext)
        saved(plan)
    }
}

private struct WaypointIssueCard: View {
    let message: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        ZStack {
            if visible {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(red: 0.48, green: 0.19, blue: 0.04), in: .rect(cornerRadius: 16))
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .leading), removal: .move(edge: .trailing)))
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
        .task(id: message) {
            // Present after navigation so the card's entrance is visible.
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            withAnimation(.easeOut(duration: reduceMotion ? 0.15 : 0.36)) { visible = true }
            AccessibilityNotification.Announcement(message).post()
            do { try await Task.sleep(for: .seconds(6)) } catch { return }
            withAnimation(.easeIn(duration: reduceMotion ? 0.15 : 0.3)) { visible = false }
        }
    }
}

private struct PhaseSwipeRow<Content: View>: View {
    @Binding var isOpen: Bool
    let enabled: Bool
    let skip: () -> Void
    let open: () -> Void
    @ViewBuilder let content: () -> Content
    @Environment(\.layoutDirection) private var layoutDirection
    @ScaledMetric(relativeTo: .body) private var diameter: CGFloat = 48
    @State private var direction: CGFloat = 1
    @GestureState private var translation: CGFloat = 0

    var body: some View {
        let extent = diameter + 10
        let offset = enabled ? max(-extent, min(extent, (isOpen ? direction * extent : 0) + translation)) : 0
        let leading = (offset > 0) == (layoutDirection == .leftToRight)
        ZStack(alignment: leading ? .leading : .trailing) {
            if offset != 0 {
                Button(action: skip) {
                    Text("Skip")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white)
                        .frame(width: diameter, height: diameter)
                        .background(Color.accentColor, in: .circle)
                }
                .buttonStyle(.plain)
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { if isOpen { isOpen = false } else { open() } }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { open() }
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .offset(x: offset)
        }
        .clipped()
        .simultaneousGesture(DragGesture(minimumDistance: 16)
            .updating($translation) { value, state, _ in
                if abs(value.translation.width) > abs(value.translation.height) { state = value.translation.width }
            }
            .onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 20, abs(dx) > abs(value.translation.height) else { return }
                withAnimation(.snappy) {
                    let sign: CGFloat = dx > 0 ? 1 : -1
                    if isOpen && sign != direction { isOpen = false }
                    else { direction = sign; isOpen = true }
                }
            }, isEnabled: enabled)
        .accessibilityActions { if enabled { Button("Skip", action: skip) } }
    }
}

/// A part of the workout in the builder: an icon, its name, how it ends, and a chevron to change it.
struct WorkoutPartRow: View {
    let systemImage: String
    let title: String
    let detail: String
    private let point: RoutePoint?

    init(systemImage: String, title: String, detail: String) {
        self.systemImage = systemImage
        self.title = title
        self.detail = detail
        self.point = nil
    }

    init(systemImage: String, title: String, goal: IntervalGoal, unit: DistanceUnit) {
        self.systemImage = systemImage
        self.title = title
        if case .waypoint(let end) = goal {
            detail = end.point == nil ? "Set location on map" : "Waypoint"
            point = end.point
        } else {
            detail = WorkoutDistance.endDetail(goal, unit: unit)
            point = nil
        }
    }

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
                if let point { WaypointLocationDetail(point: point) }
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
    NavigationStack { WorkoutBuilderView(editing: .new) { _ in } }
        .modelContainer(WindRunSchema.makeContainer(inMemory: true))
}
