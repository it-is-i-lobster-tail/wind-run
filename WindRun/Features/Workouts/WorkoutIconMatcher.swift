import Foundation
import NaturalLanguage

nonisolated struct WorkoutSymbol: Identifiable, Sendable {
    let id: String
    let title: String
    let phrases: [String]
    let examples: [String]
    let emoji: [String]

    static let catalog = [
        Self(id: "flame.fill", title: "Intensity", phrases: ["hard", "all out", "intense", "brutal"], examples: ["maximum effort workout", "exhausting intervals"], emoji: ["🔥", "🥵"]),
        Self(id: "mountain.2.fill", title: "Hills", phrases: ["hill", "hills", "uphill", "climb", "incline"], examples: ["steep uphill climbs", "mountain running"], emoji: ["⛰️", "🏔️"]),
        Self(id: "bolt.fill", title: "Speed", phrases: ["speed", "fast", "sprint", "sprints", "track"], examples: ["short bursts of speed", "explosive track sprints"], emoji: ["⚡", "🚀"]),
        Self(id: "leaf.fill", title: "Recovery", phrases: ["easy", "recovery", "recover", "gentle", "cool down"], examples: ["relaxed recovery jog", "gentle shakeout run"], emoji: ["🍃", "🐢"]),
        Self(id: "road.lanes", title: "Endurance", phrases: ["long run", "long", "endurance", "marathon", "distance"], examples: ["long distance endurance run", "steady mileage"], emoji: ["🛣️", "🏃"]),
        Self(id: WorkoutIcon.fallback, title: "Intervals", phrases: ["repeat", "repeats", "interval", "intervals"], examples: ["repeated intervals", "work and rest cycles"], emoji: ["🔁", "⏱️"])
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
        let words = name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let units = ["x", "min", "s", "km", "m", "open"]
        guard words.contains(where: { $0.contains(where: \.isLetter) && !units.contains($0) }) else {
            return WorkoutIcon.fallback
        }
        let query = words.joined(separator: " ")
        let padded = " " + query + " "
        for symbol in WorkoutSymbol.catalog where symbol.phrases.contains(where: { padded.contains(" " + $0 + " ") }) {
            return symbol.id
        }

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

// English short names and selected search keywords from Unicode CLDR annotations.
// https://github.com/unicode-org/cldr/blob/main/common/annotations/en.xml
nonisolated struct WorkoutEmoji: Identifiable {
    let id: String
    let name: String
    let keywords: [String]

    static let catalog = [
        Self(id: "🔥", name: "fire", keywords: ["flame", "hot"]),
        Self(id: "🥵", name: "hot face", keywords: ["heatstroke", "sweating"]),
        Self(id: "⛰️", name: "mountain", keywords: ["mountain"]),
        Self(id: "🏔️", name: "snow-capped mountain", keywords: ["cold", "mountain", "snow"]),
        Self(id: "⚡", name: "high voltage", keywords: ["lightning", "thunder"]),
        Self(id: "🚀", name: "rocket", keywords: ["space"]),
        Self(id: "🍃", name: "leaf fluttering in wind", keywords: ["blow", "flutter", "leaf", "wind"]),
        Self(id: "🐢", name: "turtle", keywords: ["terrapin", "tortoise"]),
        Self(id: "🛣️", name: "motorway", keywords: ["highway", "road"]),
        Self(id: "🏃", name: "person running", keywords: ["marathon", "running"]),
        Self(id: "🔁", name: "repeat button", keywords: ["arrow", "repeat"]),
        Self(id: "⏱️", name: "stopwatch", keywords: ["clock"])
    ]

    static func suggestions(name: String, symbol: String) -> [Self] {
        let words = Set(name.lowercased().split { !$0.isLetter }.map(String.init))
        let direct = catalog.filter { item in
            !words.isDisjoint(with: item.keywords + item.name.split(separator: " ").map(String.init))
        }
        let related = WorkoutSymbol.catalog.first { $0.id == symbol }?.emoji ?? []
        let extra = catalog.filter { related.contains($0.id) && !direct.map(\.id).contains($0.id) }
        return Array((direct + extra).prefix(4))
    }
}
