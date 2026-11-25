//
//  DisplaysView.swift
//  Wind Run
//

import SwiftData
import SwiftUI

/// "Displays", from the Workout page's ⋯ menu: every saved display with a small preview, the default marked,
/// and which runs use each. Tapping one opens Edit Display; swiping makes it the default or deletes it.
struct DisplaysView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @Query(filter: IntervalPlan.onIntervalsPage) private var plans: [IntervalPlan]
    @State private var library = DisplayLibrary.current
    @State private var deleting: DisplayScreen?

    /// Opens Edit Display on a display just made.
    let open: (UUID) -> Void

    var body: some View {
        List {
            Section("Built-in") {
                DisplayRow(screen: .cycling, unit: unit, sport: .cycling,
                           detail: "Ride default · Speed, distance, time, average speed, heart rate and elevation")
                DisplayRow(screen: .hike, unit: unit, sport: .hiking, detail: "Hike default")
            }
            Section {
                ForEach(library.sorted) { screen in
                    let isDefault = library.isDefault(screen.id)
                    NavigationLink(value: WorkoutRoute.editDisplay(screen.id)) {
                        DisplayRow(screen: screen, unit: unit, isDefault: isDefault, detail: DisplayActions.usage(of: screen, in: library, workouts: workoutPicks))
                    }
                    .swipeActions(edge: .trailing) {
                        if !isDefault {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Trace.tap("Displays", "Swipe: Delete")
                                askOrDelete(screen)
                            }
                            Button("Make Default", systemImage: "star") {
                                Trace.tap("Displays", "Swipe: Make Default")
                                makeDefault(screen)
                            }
                            .tint(Color.accentColor)
                        }
                    }
                    .contextMenu {
                        if !isDefault {
                            Button("Make Default", systemImage: "star") {
                                Trace.tap("Displays", "Menu: Make Default")
                                makeDefault(screen)
                            }
                        }
                        Button("Duplicate", systemImage: "plus.square.on.square") {
                            Trace.tap("Displays", "Menu: Duplicate")
                            add(copying: screen)
                        }
                        .disabled(library.isFull)
                        if !isDefault {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                Trace.tap("Displays", "Menu: Delete")
                                askOrDelete(screen)
                            }
                        }
                    }
                }
                Button {
                    Trace.tap("Displays", "New Display")
                    add()
                } label: {
                    Label("New Display", systemImage: "plus")
                }
                .disabled(library.isFull)
            } footer: {
                Text(library.isFull
                    ? "That's \(DisplayLibrary.limit) displays, the most there can be. Delete one to make another."
                    : "Swipe a display to make it the default or delete it. The default shows on any run that doesn't pick another.")
            }
        }
        .navigationTitle("Displays")
        .navigationBarTitleDisplayMode(.inline)
        .traceScreen("Displays")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Display", systemImage: "plus") {
                    Trace.tap("Displays", "Toolbar: New Display")
                    add()
                }
                .disabled(library.isFull)
            }
        }
        // Back from Edit Display, which saves as the runner goes.
        .onAppear { library = .current }
        // Only asked when a workout or a kind of run uses the display; one nothing uses goes straight away.
        .alert(
            "Delete “\(deleting?.name ?? "display")”?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { screen in
            Button("Delete", role: .destructive) {
                Trace.tap("Displays", "Delete display?: Delete Display")
                delete(screen)
            }
            Button("Cancel", role: .cancel) {}
        } message: { screen in
            Text(DisplayActions.deleteMessage(of: screen, in: library, workouts: workoutPicks))
        }
    }

    /// Each saved workout's display pick and name, for what uses each display.
    private var workoutPicks: [(id: UUID?, name: String)] {
        plans.savedWorkouts.map { (id: $0.displayScreenID, name: $0.name) }
    }

    /// Asks first when something uses the display, else deletes it.
    private func askOrDelete(_ screen: DisplayScreen) {
        if DisplayActions.isInUse(screen.id, in: modelContext) {
            deleting = screen
        } else {
            delete(screen)
        }
    }

    private func delete(_ screen: DisplayScreen) {
        withAnimation {
            DisplayActions.delete(screen.id, in: modelContext)
            library = .current
        }
    }

    private func makeDefault(_ screen: DisplayScreen) {
        withAnimation {
            library.makeDefault(screen.id)
        }
        library.save()
    }

    private func add(copying screen: DisplayScreen? = nil) {
        guard let new = DisplayActions.add(copying: screen, to: &library) else { return }
        open(new.id)
    }
}

/// What adding and deleting a display does everywhere, and what uses each, shared by the list, Edit Display
/// and the picker.
enum DisplayActions {
    /// Adds a copy of `original`, or a new display from the default, to `library` and saves it. Nil when the
    /// library is full. `traced` notes it in the trace.
    @discardableResult
    static func add(copying original: DisplayScreen? = nil, to library: inout DisplayLibrary, traced: Bool = true, defaults: UserDefaults = .standard) -> DisplayScreen? {
        guard let new = library.add(copying: original) else { return nil }
        library.save(in: defaults)
        if traced {
            Trace.log(.setting, "Display added", ["displays": library.screens.count, "copy": original != nil])
        }
        return new
    }

    /// "Hill Repeats, Free Run", "Not used yet", or for the default what it's for. `workouts` holds each saved
    /// workout's display pick and name; the kinds of run follow, in their own order.
    static func usage(of screen: DisplayScreen, in library: DisplayLibrary, workouts: [(id: UUID?, name: String)], defaults: UserDefaults = .standard) -> String {
        if library.isDefault(screen.id) { return "Shows on any run that doesn't pick another" }
        let names = workouts.filter { $0.id == screen.id }.map { $0.name }
            + DisplayRunKind.allCases.filter { $0.pick(in: defaults) == screen.id }.map(\.name)
        return names.isEmpty ? "Not used yet" : names.joined(separator: ", ")
    }

    /// Takes the display out, and points every run that picked it back at the default: the kinds of run in the
    /// settings and every workout, including ones only a past run keeps.
    static func delete(_ id: UUID, in context: ModelContext, defaults: UserDefaults = .standard) {
        var library = DisplayLibrary.current(in: defaults)
        guard library.contains(id), !library.isDefault(id) else { return }
        library.delete(id)
        library.save(in: defaults)
        var cleared = 0
        for kind in DisplayRunKind.allCases where kind.pick(in: defaults) == id {
            kind.setPick(nil, in: defaults)
            cleared += 1
        }
        let text = id.uuidString
        let plans = (try? context.fetch(FetchDescriptor<IntervalPlan>(predicate: #Predicate { $0.displayScreenIDValue == text }))) ?? []
        for plan in plans {
            plan.displayScreenID = nil
        }
        context.saveQuietly()
        Trace.log(.setting, "Display deleted", ["displays": library.screens.count, "runKinds": cleared, "workouts": plans.count])
    }

    /// Whether a saved workout on the Workout page or a kind of run picks the display, so deleting it changes
    /// what a run shows. Copies only a past run keeps don't count.
    static func isInUse(_ id: UUID, in context: ModelContext, defaults: UserDefaults = .standard) -> Bool {
        if DisplayRunKind.allCases.contains(where: { $0.pick(in: defaults) == id }) { return true }
        let text = id.uuidString
        let plans = (try? context.fetch(FetchDescriptor<IntervalPlan>(predicate: #Predicate { $0.displayScreenIDValue == text }))) ?? []
        return plans.contains(where: \.isSavedWorkout)
    }

    /// Names the workouts that use this display and explains what they will show after deletion.
    static func deleteMessage(of screen: DisplayScreen, in library: DisplayLibrary, workouts: [(id: UUID?, name: String)], defaults: UserDefaults = .standard) -> String {
        let users = usage(of: screen, in: library, workouts: workouts, defaults: defaults)
        return "Used by \(users). Each workout will use its activity’s default display."
    }
}

/// A display in a list: its preview, its name, "Default" on the default, and a line about it.
struct DisplayRow: View {
    let screen: DisplayScreen
    let unit: DistanceUnit
    var sport: WorkoutSport = .running
    var isDefault = false
    var detail: String?

    var body: some View {
        HStack(spacing: 14) {
            DisplayThumbnail(screen: screen, unit: unit, sport: sport)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(screen.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if isDefault {
                        DefaultBadge()
                    }
                }
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// "Default", on the runner's default display.
struct DefaultBadge: View {
    var body: some View {
        Text("Default")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.onAccent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor, in: .capsule)
    }
}

/// A display shrunk to a stamp: its six numbers with sample values, laid out as the run screen has them, so
/// displays can be told apart at a glance. Only for looking at; the row around it says what it is.
struct DisplayThumbnail: View {
    let screen: DisplayScreen
    let unit: DistanceUnit
    var sport: WorkoutSport = .running
    var width: CGFloat = 54

    var body: some View {
        let readings = screen.readings(.sample(unit: unit, sport: sport))
        let scale = width / 54
        VStack(spacing: 1 * scale) {
            Text(readings.primary.value)
                .font(.system(size: 12 * scale, weight: .bold, design: .rounded))
            Text(readings.secondary.value)
                .font(.system(size: 9.5 * scale, weight: .bold, design: .rounded))
            Grid(horizontalSpacing: 3 * scale, verticalSpacing: 2 * scale) {
                ForEach(DisplayTileLayout.rows(count: readings.tiles.count), id: \.lowerBound) { row in
                    GridRow {
                        ForEach(row, id: \.self) { index in
                            Text(readings.tiles[index].value)
                                .font(.system(size: 7.5 * scale, weight: .semibold, design: .rounded))
                        }
                    }
                }
            }
            .padding(.top, 2 * scale)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(.horizontal, 3 * scale)
        .frame(width: width, height: width * 64 / 54)
        .background(Color(.systemBackground), in: .rect(cornerRadius: 8 * scale))
        .overlay(RoundedRectangle(cornerRadius: 8 * scale).strokeBorder(.quaternary))
        .accessibilityHidden(true)
    }
}

/// Picks the display a workout, or a kind of run, shows: the default or any saved display, with a way to make
/// a new one or change the one picked without leaving.
struct DisplayPickerPage: View {
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @State private var library = DisplayLibrary.current
    @State private var selection: UUID?
    @State private var editing: UUID?
    /// What the pick is for, for the trace: "workout" or a kind of run.
    let sport: WorkoutSport
    let tracedAs: String
    let pick: (UUID?) -> Void

    init(selection: UUID?, sport: WorkoutSport = .running, tracedAs: String, pick: @escaping (UUID?) -> Void) {
        _selection = State(initialValue: selection)
        self.sport = sport
        self.tracedAs = tracedAs
        self.pick = pick
    }

    /// The display that shows: the one picked, or the default for none or a deleted one.
    private var chosen: DisplayScreen { library.screen(id: selection, sport: sport) }

    var body: some View {
        Form {
            Section {
                ForEach(library.choices(for: sport)) { screen in
                    let isChosen = chosen.id == screen.id
                    Button {
                        Trace.tap("Display picker", "Pick", ["for": tracedAs, "default": screen.id == library.defaultScreen(for: sport).id])
                        choose(screen.id)
                    } label: {
                        HStack {
                            DisplayRow(screen: screen, unit: unit, sport: sport, isDefault: screen.id == library.defaultScreen(for: sport).id)
                            Spacer(minLength: LayoutMetrics.compactSpacing)
                            if isChosen {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(.rect)
                    }
                    .tint(.primary)
                    .accessibilityAddTraits(isChosen ? .isSelected : [])
                }
            } footer: {
                Text("What your workout screen, Apple Watch and Lock Screen show. A change to a saved display shows on every workout that uses it.")
            }

            Section {
                Button {
                    Trace.tap("Display picker", "New Display", ["for": tracedAs])
                    guard let new = DisplayActions.add(copying: library.builtInScreen(for: sport), to: &library, traced: false) else { return }
                    choose(new.id)
                    editing = new.id
                } label: {
                    Label("New Display", systemImage: "plus")
                }
                .disabled(library.isFull)
                if library.contains(chosen.id) {
                    Button {
                        Trace.tap("Display picker", "Edit display", ["for": tracedAs])
                        editing = chosen.id
                    } label: {
                        Label("Edit “\(chosen.name)”", systemImage: "pencil")
                    }
                }
            }
        }
        .navigationTitle("Display")
        .navigationBarTitleDisplayMode(.inline)
        .traceScreen("Display picker")
        .navigationDestination(item: $editing) { id in
            EditDisplayView(screenID: id, sport: sport)
        }
        // Back from Edit Display, which may have renamed, changed or deleted a display.
        .onAppear { library = .current }
    }

    /// Picking the default keeps no pick, so the run follows whichever display is the default when it starts.
    private func choose(_ id: UUID) {
        selection = id == library.defaultScreen(for: sport).id ? nil : id
        pick(selection)
    }
}

/// The display a built-in run or the coach's run shows, on its Start page, with a way to pick another.
struct DisplayChoiceRow: View {
    let kind: DisplayRunKind

    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @State private var library = DisplayLibrary.current
    @State private var pickID: UUID?
    @State private var isPicking = false

    init(kind: DisplayRunKind) {
        self.kind = kind
        _pickID = State(initialValue: kind.pick())
    }

    private var sport: WorkoutSport {
        switch kind {
        case .cycling: .cycling
        case .hike: .hiking
        default: .running
        }
    }

    var body: some View {
        let screen = library.screen(id: pickID, sport: sport)
        Button {
            Trace.tap("Workout ready", "Display", ["kind": kind.rawValue])
            isPicking = true
        } label: {
            HStack(spacing: 14) {
                DisplayThumbnail(screen: screen, unit: unit, sport: sport)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Display")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(screen.name)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
            .windRunGlassCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Display, \(screen.name)")
        .accessibilityHint("Picks what the run screen shows")
        .navigationDestination(isPresented: $isPicking) {
            DisplayPickerPage(selection: pickID, sport: sport, tracedAs: kind.rawValue) { id in
                kind.setPick(id)
                pickID = id
            }
        }
        .onAppear {
            library = .current
            pickID = kind.pick()
        }
    }
}

#Preview("Displays") {
    NavigationStack { DisplaysView { _ in } }
}

#Preview("Picker") {
    NavigationStack { DisplayPickerPage(selection: nil, tracedAs: "preview") { _ in } }
}
