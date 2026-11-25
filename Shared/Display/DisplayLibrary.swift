//
//  DisplayLibrary.swift
//  Wind Run
//

import Foundation
import Synchronization

/// The runner's saved display screens, one of them the default. A workout can pick one of them for its runs;
/// any run that doesn't pick one, or whose pick was deleted, shows the default.
///
/// Kept as text in the settings, so the list follows the runner to the Watch and through iCloud like the
/// other settings. The default screen is also written to `DisplayScreen.storageKey`, the key older versions
/// read, so a Watch that hasn't updated yet still shows it.
nonisolated struct DisplayLibrary: Equatable, Sendable {
    /// Never empty: the default is always in it.
    private(set) var screens: [DisplayScreen]
    private(set) var defaultID: UUID

    /// Every display, as JSON text.
    static let screensKey = "displayScreens"
    /// The default display's id.
    static let defaultKey = "defaultDisplayScreen"
    /// The most displays kept, which keeps the list well inside what the settings sync can carry.
    static let limit = 20
    /// The longest name a display can have.
    static let nameLimit = 30
    /// Room a unique name leaves for its number: " 2" to " 99", which is enough while `limit` is under 100.
    private static let suffixRoom = 3
    /// What the display that was there before saved displays is called, and the name a blank name saves as.
    static let firstName = "Everyday"
    static let newName = "New Display"

    init(screens: [DisplayScreen], defaultID: UUID? = nil) {
        let screens = screens.isEmpty ? [Self.first(from: .standard)] : screens
        self.screens = screens
        self.defaultID = defaultID.flatMap { id in screens.contains { $0.id == id } ? id : nil } ?? screens[0].id
    }

    /// The display the old single display becomes: its six spots, named "Everyday". It keeps its id, which is
    /// the same on every device, so two devices moving over at once end up with the same display.
    static func first(from screen: DisplayScreen) -> DisplayScreen {
        var screen = screen
        screen.name = firstName
        return screen
    }

    var defaultScreen: DisplayScreen { screens.first { $0.id == defaultID } ?? screens[0] }

    /// The cycling preset lives in the app, outside the synced list and its size limit.
    func defaultScreen(for sport: WorkoutSport) -> DisplayScreen {
        sport == .cycling ? .cycling : defaultScreen
    }

    func choices(for sport: WorkoutSport) -> [DisplayScreen] {
        sport == .cycling ? [.cycling] + sorted : sorted
    }

    /// A missing or deleted pick follows the workout's sport.
    func screen(id: UUID?, sport: WorkoutSport = .running) -> DisplayScreen {
        guard let id, let screen = screens.first(where: { $0.id == id }) else { return defaultScreen(for: sport) }
        return screen
    }

    func contains(_ id: UUID?) -> Bool {
        guard let id else { return false }
        return screens.contains { $0.id == id }
    }

    func isDefault(_ id: UUID?) -> Bool { id == defaultID }

    /// The default first, then the rest in the order they were made.
    var sorted: [DisplayScreen] {
        [defaultScreen] + screens.filter { $0.id != defaultID }
    }

    var isFull: Bool { screens.count >= Self.limit }

    // MARK: Changing

    /// Adds a copy of `original`, the default when it's nil, under a name no other display has, and returns
    /// it. Nil when the list is full.
    @discardableResult
    mutating func add(copying original: DisplayScreen? = nil) -> DisplayScreen? {
        guard !isFull else { return nil }
        let source = original ?? defaultScreen
        let name = uniqueName(original.map { "\($0.name) Copy" } ?? Self.newName)
        let screen = DisplayScreen(name: name, primary: source.primary, secondary: source.secondary, tiles: source.tiles)
        screens.append(screen)
        return screen
    }

    /// Replaces the display with the same id. A blank name is kept as the old one.
    mutating func update(_ screen: DisplayScreen) {
        guard let index = screens.firstIndex(where: { $0.id == screen.id }) else { return }
        var screen = screen
        let name = Self.trimmed(screen.name)
        screen.name = name.isEmpty ? screens[index].name : name
        screens[index] = screen
    }

    /// Takes a display out. The default can't be: another one has to be made the default first.
    mutating func delete(_ id: UUID) {
        guard id != defaultID else { return }
        screens.removeAll { $0.id == id }
    }

    mutating func makeDefault(_ id: UUID) {
        guard contains(id) else { return }
        defaultID = id
    }

    /// `base`, or `base 2`, `base 3`… when another display already has it.
    func uniqueName(_ base: String) -> String {
        let base = String(Self.trimmed(base).prefix(Self.nameLimit - Self.suffixRoom))
        let taken = Set(screens.map { $0.name.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)".lowercased()) { number += 1 }
        return "\(base) \(number)"
    }

    static func trimmed(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(nameLimit))
    }

    /// What typing `typed` into a display's name field does, for a display now called `current`.
    nonisolated enum NameEdit: Equatable, Sendable {
        /// Over the limit: the field is cut back to this while typing, so what shows is what's saved.
        case cut(String)
        /// The display takes this name.
        case rename(String)
        /// Nothing changes. A blank name keeps the old one, which comes back when the page closes.
        case keep
    }

    static func nameEdit(typed: String, current: String) -> NameEdit {
        if typed.count > nameLimit {
            return .cut(String(typed.prefix(nameLimit)))
        }
        let name = Self.trimmed(typed)
        guard !name.isEmpty, name != current else { return .keep }
        return .rename(name)
    }
}

// MARK: - Storage

extension DisplayLibrary {
    /// The settings last read, their texts and the library they made, so the run screen's reads each second
    /// only decode again after a change.
    private nonisolated static let lastRead = Mutex<(store: ObjectIdentifier, screens: String?, defaultID: String?, legacy: String?, library: DisplayLibrary)?>(nil)

    /// The runner's displays as stored now.
    nonisolated static var current: DisplayLibrary { current(in: .standard) }

    /// The stored displays. Before any were saved, the one display there was, named "Everyday", is the only
    /// one and the default. Reading never writes: that happens with the runner's first change.
    nonisolated static func current(in defaults: UserDefaults) -> DisplayLibrary {
        let screensText = defaults.string(forKey: screensKey)
        let defaultText = defaults.string(forKey: defaultKey)
        // The old key is read even with a list saved: a list that's empty or doesn't decode falls back to it,
        // so a change to it, such as from an older version through settings sync, has to be seen.
        let legacyText = defaults.string(forKey: DisplayScreen.storageKey)
        let store = ObjectIdentifier(defaults)
        return lastRead.withLock { last in
            if let last, last.store == store, last.screens == screensText, last.defaultID == defaultText, last.legacy == legacyText {
                return last.library
            }
            let library = decode(screensText, defaultID: defaultText, defaults: defaults)
            last = (store, screensText, defaultText, legacyText, library)
            return library
        }
    }

    private nonisolated static func decode(_ text: String?, defaultID: String?, defaults: UserDefaults) -> DisplayLibrary {
        let legacy = DisplayLibrary(screens: [first(from: DisplayScreen.legacy(in: defaults))])
        guard let text else { return legacy }
        do {
            let screens = try JSONDecoder().decode([DisplayScreen].self, from: Data(text.utf8))
            guard !screens.isEmpty else { return legacy }
            let id = defaultID.flatMap(UUID.init(uuidString:))
            if id.map({ id in screens.contains { $0.id == id } }) != true {
                Trace.log(.setting, "Default display not found, so the first one is the default", ["displays": screens.count])
            }
            return DisplayLibrary(screens: screens, defaultID: id)
        } catch {
            Trace.error("Displays didn't decode, so the old display shows", error)
            return legacy
        }
    }

    /// Keeps the list, and the default where older versions look for it.
    nonisolated func save(in defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(screens), let text = String(data: data, encoding: .utf8) else { return }
        defaults.set(text, forKey: Self.screensKey)
        defaults.set(defaultID.uuidString, forKey: Self.defaultKey)
        defaultScreen.save(in: defaults)
    }
}

// MARK: - Which display a run shows

/// The runs that aren't a saved workout, each of which can pick a display of its own in the settings. A saved
/// workout keeps its pick on the workout.
nonisolated enum DisplayRunKind: String, CaseIterable, Identifiable, Sendable {
    case free
    case cycling
    case distance
    case timed
    case coach

    var id: Self { self }

    var name: String {
        switch self {
        case .free: "Free Run"
        case .cycling: "Cycling"
        case .distance: "Distance Run"
        case .timed: "Timed Run"
        case .coach: "Coach's Workout"
        }
    }

    /// Where this kind's pick is kept: a display's id, or nothing for the default.
    var storageKey: String {
        switch self {
        case .free: "displayScreenFree"
        case .cycling: "displayScreenCycling"
        case .distance: "displayScreenDistance"
        case .timed: "displayScreenTimed"
        case .coach: "displayScreenCoach"
        }
    }

    static var storageKeys: [String] { allCases.map(\.storageKey) }

    /// The display this kind of run picked, or nil for the default.
    func pick(in defaults: UserDefaults = .standard) -> UUID? {
        defaults.string(forKey: storageKey).flatMap(UUID.init(uuidString:))
    }

    /// Keeps the pick; nil goes back to the default.
    func setPick(_ id: UUID?, in defaults: UserDefaults = .standard) {
        if let id {
            defaults.set(id.uuidString, forKey: storageKey)
        } else {
            defaults.removeObject(forKey: storageKey)
        }
    }
}

extension DisplayScreen {
    /// The display every run shows unless it picked another: the runner's default.
    nonisolated static var current: DisplayScreen { DisplayLibrary.current.defaultScreen }
}
