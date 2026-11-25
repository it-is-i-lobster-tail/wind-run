import Foundation

/// The same English activity names power picker search and automatic matching.
nonisolated struct WorkoutSymbolEntry: Identifiable {
    let id: String
    let title: String
    let terms: [String]
    let searchText: String

    private static let aliases = [
        "figure.run": ["running", "jogging", "jog", "run"],
        "figure.walk": ["walking", "walk", "stroll"],
        "figure.hiking": ["hiking", "hike", "trail hike", "trek", "backpacking"],
        "figure.climbing": ["climbing", "rock climbing", "bouldering"],
        "figure.outdoor.cycle": ["cycling", "bike ride", "road bike", "mountain biking", "mountain bike", "biking", "bike", "ride"],
        "bicycle": ["bicycle", "bike", "cycling"],
        "figure.indoor.cycle": ["indoor cycling", "stationary bike", "spin class", "spinning"],
        "figure.run.treadmill": ["treadmill run", "treadmill"],
        "figure.track.and.field": ["track and field", "track meet"],
        "figure.highintensity.intervaltraining": ["HIIT", "high intensity interval training"],
        "figure.strengthtraining.functional": ["functional strength", "functional training"],
        "figure.strengthtraining.traditional": ["strength training", "weightlifting"],
        "dumbbell": ["weights", "lifting", "gym"],
        "figure.jumprope": ["jump rope", "skipping"],
        "figure.taichi": ["tai chi"],
        "figure.cross.training": ["cross training", "crossfit"],
        "figure.flexibility": ["flexibility", "stretching"],
        "figure.pool.swim": ["swimming", "swim", "pool laps"],
        "figure.open.water.swim": ["open water swimming", "ocean swim"],
        "figure.skiing.crosscountry": ["cross country skiing", "nordic skiing"],
        "mountain.2": ["mountain", "mountains", "hills", "summit", "peak", "alpine"],
        "tree": ["forest", "woods", "woodland", "trail run"],
        "tent": ["camping", "camp", "campsite"],
        "backpack": ["pack", "rucking", "ruck"],
        "map": ["route", "navigation", "orienteering"],
        "sunrise": ["sunrise", "dawn", "early morning"],
        "sunset": ["sunset", "dusk"],
        "waterbottle": ["water bottle", "hydration"],
        "waveform.path.ecg": ["heart rate", "cardio"],
        "flag.pattern.checkered": ["finish line", "race day"],
        "medal": ["personal best", "race medal"],
    ]

    init(id: String) {
        self.id = id
        var components = id.components(separatedBy: ".")
        var variants = [String]()
        while let word = components.last, ["circle", "square", "fill"].contains(word) {
            variants.insert(word == "fill" ? "filled" : word, at: 0)
            components.removeLast()
        }
        let family = components.joined(separator: ".")
        let base = components.filter { $0 != "figure" }.joined(separator: " ")
        let aliases = Self.aliases[family] ?? []
        let display = aliases.first ?? base
        title = ([display] + variants).joined(separator: " ").capitalized
        terms = ([base] + aliases).map { $0.lowercased() }
        let quickPick = WorkoutSymbol.catalog.first { $0.id == id }
        let keywords = (quickPick?.phrases ?? []) + [quickPick?.title ?? ""]
        searchText = ([id, title] + terms + keywords).joined(separator: " ").lowercased()
    }

    static let sections = WorkoutSymbolGroup.all.map { group in
        (title: group.title, entries: group.symbols.map(Self.init))
    }

    static func search(_ text: String) -> [(title: String, entries: [Self])] {
        let words = text.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        return sections.compactMap { section in
            let entries = section.entries.filter { entry in
                let text = entry.searchText + " " + section.title.lowercased()
                return words.allSatisfy { text.contains($0) }
            }
            return entries.isEmpty ? nil : (section.title, entries)
        }
    }

    /// Prefer the base artwork for automatic suggestions. All variants remain selectable.
    static let nameMatches: [(term: String, id: String)] = sections.flatMap(\.entries)
        .filter { !$0.id.hasSuffix(".fill") && !$0.id.hasSuffix(".circle") && !$0.id.hasSuffix(".square") }
        .flatMap { entry in entry.terms.map { (term: $0, id: entry.id) } }
        .filter { $0.term.count >= 3 }
        .sorted {
            if $0.term.count != $1.term.count { return $0.term.count > $1.term.count }
            return $0.id < $1.id
        }
}
