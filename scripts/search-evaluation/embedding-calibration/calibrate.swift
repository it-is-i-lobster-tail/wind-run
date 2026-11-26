// Prints Apple's on-device English word embedding distances for pairs search should and shouldn't join.
// Run on a Mac: swift scripts/search-evaluation/embedding-calibration/calibrate.swift
import NaturalLanguage

let should: [(String, String)] = [
    ("sunny", "sunshine"), ("scenic", "views"), ("puddles", "rain"), ("beach", "ocean"), ("forest", "woods"),
    ("hot", "heat"), ("humid", "muggy"), ("dog", "puppy"), ("friends", "buddies"), ("sore", "pain"),
    ("windy", "wind"), ("lakeside", "lake"), ("coastal", "coast"), ("foggy", "fog"), ("snowy", "snow"),
    ("stroll", "walk"), ("knee", "knees"), ("buddy", "friend"), ("seaside", "beach"), ("woodland", "forest"),
    ("downpour", "rain"), ("chilly", "cold"), ("tired", "exhausted"), ("speedy", "fast"), ("canine", "dog"),
    ("mountain", "mountains"), ("pier", "dock"), ("creek", "stream"), ("meadow", "field"), ("ache", "pain")
]
let shouldNot: [(String, String)] = [
    ("morning", "evening"), ("uphill", "downhill"), ("hot", "cold"), ("fast", "slow"), ("easy", "hard"),
    ("river", "lake"), ("tempo", "easy"), ("dog", "cat"), ("desert", "river"), ("cactus", "tree"),
    ("monday", "tuesday"), ("north", "south"), ("bridge", "tunnel"), ("park", "street"), ("knee", "ankle"),
    ("ocean", "mountain"), ("rain", "snow"), ("sunny", "rainy"), ("short", "long"), ("wife", "husband"),
    ("portland", "seattle"), ("trail", "road"), ("beach", "desert"), ("happy", "sad"), ("track", "trail")
]
guard let embedding = NLEmbedding.wordEmbedding(for: .english) else { fatalError("no embedding") }
func show(_ title: String, _ pairs: [(String, String)]) {
    print("== \(title)")
    for (a, b) in pairs.sorted(by: { embedding.distance(between: $0.0, and: $0.1) < embedding.distance(between: $1.0, and: $1.1) }) {
        print(String(format: "%.3f  %@ -> %@", embedding.distance(between: a, and: b), a, b))
    }
}
show("should", should)
show("should not", shouldNot)
