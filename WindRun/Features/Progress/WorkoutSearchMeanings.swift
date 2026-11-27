import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// Reads a typed word that nothing in the history has as a word the history does have, using Apple's
/// on-device English word embedding, such as "downpour" as "rain".
///
/// It only maps an unknown word to one known word. It never searches workouts itself, and the workouts that
/// have the known word show as close matches under a chip that says what it was read as.
enum WorkoutSearchMeanings {
    /// Distance below which two words count as the same meaning, on the scale `NLEmbedding.distance` reports:
    /// the straight-line distance between the two unit vectors, from 0 to 2. Measured with
    /// `scripts/search-evaluation/embedding-calibration/calibrate.swift`: the closest pairs that must not join
    /// sit at 0.656 (knee, ankle), 0.657 (wife, husband) and 0.717 (dog, cat), while downpour and rain sit at 0.614.
    /// Anything looser joins opposites and neighbors, so only near-identical meanings pass.
    static let maximumDistance = 0.64

    /// Short words that carry no meaning of their own, so they are never what an unknown word maps to.
    private static let ignored: Set<String> = ["the", "and", "for", "with", "from", "this", "that", "was", "were",
                                               "but", "not", "had", "has", "have", "are", "you", "our", "out", "into"]

    /// A word's vector, or nil where the device has none. Tests replace it, which also clears what is kept.
    static var vector: (String) -> [Double]? = systemVector {
        didSet { known = nil; memo = [:] }
    }

    #if canImport(NaturalLanguage)
    private static let embedding = NLEmbedding.wordEmbedding(for: .english)
    /// The embedding is case sensitive and knows some words only capitalized, such as "Monday".
    static func systemVector(_ word: String) -> [Double]? {
        guard let embedding else { return nil }
        return embedding.vector(for: word) ?? embedding.vector(for: word.capitalized)
    }
    #else
    static func systemVector(_ word: String) -> [Double]? { nil }
    #endif

    private struct Known {
        var words: Set<String>
        var vectors: [(word: String, vector: [Double], length: Double)]
    }

    /// The history's word vectors, kept while the history's words stay the same.
    private static var known: Known?
    private static var memo: [String: String?] = [:]

    static func isMappable(_ word: String) -> Bool {
        word.count >= 3 && word.allSatisfy(\.isLetter) && !ignored.contains(word)
    }

    /// The history word closest in meaning to a typed word, when it is under the distance limit.
    static func nearest(_ term: String, in vocabulary: Set<String>) -> String? {
        guard isMappable(term) else { return nil }
        if known?.words != vocabulary {
            let vectors = vocabulary.filter(isMappable).sorted().compactMap { word -> (String, [Double], Double)? in
                guard let value = vector(word) else { return nil }
                let length = value.reduce(0) { $0 + $1 * $1 }.squareRoot()
                return length > 0 ? (word, value, length) : nil
            }
            known = Known(words: vocabulary, vectors: vectors)
            memo = [:]
        }
        if let kept = memo[term] { return kept }
        var best: (word: String, distance: Double)?
        if let wanted = vector(term) {
            let length = wanted.reduce(0) { $0 + $1 * $1 }.squareRoot()
            for candidate in known?.vectors ?? [] where length > 0 && candidate.vector.count == wanted.count {
                var dot = 0.0
                for index in wanted.indices { dot += wanted[index] * candidate.vector[index] }
                // Same scale as NLEmbedding.distance(between:and:): the gap between unit vectors, sqrt(2 · (1 − cos)).
                let distance = (2 * max(0, 1 - dot / (length * candidate.length))).squareRoot()
                if distance < (best?.distance ?? maximumDistance) { best = (candidate.word, distance) }
            }
        }
        memo[term] = best?.word
        return best?.word
    }
}
