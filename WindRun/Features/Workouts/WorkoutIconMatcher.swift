import Foundation
import NaturalLanguage

nonisolated struct WorkoutSymbol: Identifiable, Sendable {
    let id: String
    let title: String
    let phrases: [String]
    let examples: [String]

    static let catalog = [
        Self(id: "flame.fill", title: "Intensity", phrases: ["fire", "hot face", "hard", "all out", "intense", "brutal"], examples: ["maximum effort workout", "exhausting intervals"]),
        Self(id: "mountain.2.fill", title: "Hills", phrases: ["hill", "hills", "uphill", "climb", "incline"], examples: ["steep uphill climbs", "mountain running"]),
        Self(id: "bolt.fill", title: "Speed", phrases: ["speed", "sprint", "sprints", "track"], examples: ["short bursts of speed", "explosive track sprints"]),
        Self(id: "leaf.fill", title: "Recovery", phrases: ["easy", "recovery", "recover", "gentle", "cool down"], examples: ["relaxed recovery jog", "gentle shakeout run"]),
        Self(id: "road.lanes", title: "Endurance", phrases: ["long run", "long", "endurance", "marathon", "distance"], examples: ["long distance endurance run", "steady mileage"]),
        Self(id: WorkoutIcon.fallback, title: "Intervals", phrases: ["repeat", "repeats", "interval", "intervals"], examples: ["repeated intervals", "work and rest cycles"])
    ]
}

/// Serializes access to the on-device English embedding off the UI thread.
actor WorkoutIconMatcher {
    static let shared = WorkoutIconMatcher()
    private lazy var embedding = NLEmbedding.sentenceEmbedding(for: .english)

    func symbol(for name: String) -> String {
        Self.match(name) { query, example in
            embedding?.distance(between: query, and: example) ?? .infinity
        }
    }

    static func match(_ name: String, distance: (String, String) -> Double) -> String {
        let words = WorkoutIconQuery(name).words
        if let match = WorkoutSymbolEntry.bestMatch(words) { return match }
        let units = ["x", "min", "s", "km", "m", "open"]
        guard words.contains(where: { $0.contains(where: \.isLetter) && !units.contains($0) }) else {
            return WorkoutIcon.fallback
        }
        let query = words.joined(separator: " ")
        var best = WorkoutIcon.fallback
        var bestDistance = 0.45
        for symbol in WorkoutSymbol.catalog {
            for example in symbol.examples {
                let score = distance(query, example)
                if score < bestDistance {
                    best = symbol.id
                    bestDistance = score
                }
            }
        }
        return best
    }
}
