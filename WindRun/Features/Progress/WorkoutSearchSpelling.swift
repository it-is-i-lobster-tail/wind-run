import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// Fixes a misspelled search word with the system spell checker (`UITextChecker`), such as "tmepo" as "tempo"
/// or "febuary" as February (the owner, 2026-11-28).
///
/// It only runs on a word nothing in the history has, and only keeps a fix that search can use: a word some
/// workout has, or a word search reads as a filter, such as a month, a workout type or "hills". A word the
/// history has is never changed, so a place or a name the dictionary doesn't know still searches as typed.
/// The fix shows as a chip that says what was typed, and tapping it drops the word.
enum WorkoutSearchSpelling {
    /// What was fixed in one search.
    struct Fixes: Equatable {
        /// A history word for a typed word, keyed by the history word, such as "tempo": "tmepo".
        var words: [String: String] = [:]
        /// Chip text for a filter read from a fixed word, such as "February (from febuary)".
        var filters: [WorkoutSearchFilter: String] = [:]
    }

    /// The spell checker's guesses for a word, best first, or none when it is spelled right. Tests replace it,
    /// which also clears what is kept.
    static var guesses: (String) -> [String] = systemGuesses {
        didSet { memo = [:] }
    }
    private static var memo: [String: [String]] = [:]

    /// Short words, numbers and abbreviations are left alone: "5k", "mi" and "hr" are not typos.
    static func isCheckable(_ word: String) -> Bool {
        word.count >= 3 && word.allSatisfy(\.isLetter)
    }

    /// Replaces each fixable word in the intent's words with its fix, and says what it fixed.
    static func fix(_ intent: inout WorkoutSearchIntent, vocabulary: Set<String>,
                    known: (String) -> Bool) -> Fixes {
        var fixes = Fixes()
        guard !intent.terms.isEmpty else { return fixes }
        var terms: [String] = []
        for term in intent.terms {
            guard isCheckable(term), !known(term) else { terms.append(term); continue }
            if memo[term] == nil { memo[term] = guesses(term) }
            var fixed = false
            for guess in memo[term] ?? [] {
                let words = WorkoutSearchEngine.words(guess)
                guard words.count == 1, let word = words.first, word != term, isCheckable(word) else { continue }
                if vocabulary.contains(word) {
                    terms.append(word)
                    fixes.words[word] = term
                    fixed = true
                    break
                }
                // A word search reads as a filter on its own, such as a month or a workout type.
                let parsed = WorkoutSearchEngine.parse(word)
                if parsed.terms.isEmpty, parsed.stateCandidates.isEmpty, !parsed.filters.isEmpty {
                    for filter in parsed.filters where !intent.filters.contains(filter) {
                        intent.append(filter)
                        fixes.filters[filter] = "\(filter.label) (from \(term))"
                    }
                    fixed = true
                    break
                }
            }
            if !fixed { terms.append(term) }
        }
        intent.terms = terms
        return fixes
    }

    #if canImport(UIKit) && !os(watchOS)
    private static let checker = UITextChecker()

    /// The language search reads in: the runner's own when the checker has it, else US English.
    private static let language: String = {
        let available = UITextChecker.availableLanguages
        for preferred in Locale.preferredLanguages {
            let code = preferred.replacingOccurrences(of: "-", with: "_")
            if let match = available.first(where: { $0 == code }) ?? available.first(where: { code.hasPrefix($0) }),
               match.hasPrefix("en") { return match }
        }
        return available.first(where: { $0 == "en_US" }) ?? available.first(where: { $0.hasPrefix("en") }) ?? "en_US"
    }()

    static func systemGuesses(_ word: String) -> [String] {
        let range = NSRange(location: 0, length: (word as NSString).length)
        let wrong = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: language)
        guard wrong.location != NSNotFound else { return [] }
        return checker.guesses(forWordRange: wrong, in: word, language: language) ?? []
    }
    #else
    static func systemGuesses(_ word: String) -> [String] { [] }
    #endif
}
