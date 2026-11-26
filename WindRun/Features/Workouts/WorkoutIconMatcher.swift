import Foundation

nonisolated struct WorkoutSymbol: Identifiable, Sendable {
    let id: String
    let title: String
    let phrases: [String]

    static let catalog = [
        Self(id: "flame.fill", title: "Intensity", phrases: ["fire", "hot face", "hard", "all out", "intense", "brutal"]),
        Self(id: "mountain.2.fill", title: "Hills", phrases: ["hill", "hills", "uphill", "climb", "incline"]),
        Self(id: "bolt.fill", title: "Speed", phrases: ["speed", "sprint", "sprints"]),
        Self(id: "leaf.fill", title: "Recovery", phrases: ["easy", "recovery", "recover", "gentle", "cool down"]),
        Self(id: "road.lanes", title: "Endurance", phrases: ["long run", "long", "endurance", "marathon", "distance"]),
        Self(id: "repeat", title: "Intervals", phrases: ["repeat", "repeats", "interval", "intervals"])
    ]
}

/// Picks a workout's automatic icon from its name using the shared word list.
/// Matching is plain lookup, so the same name always gets the same icon on every device.
nonisolated enum WorkoutIconMatcher {
    static func symbol(for name: String, sport: WorkoutSport = .running) -> String {
        match(name, fallback: sport.systemImage)
    }

    static func match(_ name: String, fallback: String = WorkoutIcon.fallback) -> String {
        WorkoutSymbolEntry.bestMatch(WorkoutIconQuery(name).words) ?? fallback
    }
}
