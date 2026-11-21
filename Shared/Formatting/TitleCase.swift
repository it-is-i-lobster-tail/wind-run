//
//  TitleCase.swift
//  Wind Run
//

import Foundation

/// Title case for names typed in the app, such as a display's or a workout's name. The keyboard's
/// `.words` mode capitalizes every word as it's typed; iOS has no mode that leaves short words such as
/// "of" or "the" lowercase, so this does that part.
enum TitleCase {
    /// Short words that stay lowercase in a title, unless they're the first word.
    static let smallWords: Set<String> = [
        "a", "an", "the", "and", "but", "or", "nor", "of", "to", "in", "on", "at", "by", "for", "as", "vs", "via", "per",
    ]

    /// The name to show once `new` replaces `old` in a name field. When a space was just typed at the end,
    /// the word before it goes lowercase if it's a small word the keyboard capitalized ("Of" becomes "of"),
    /// unless it's the first word. Nothing else changes, so a word typed in capitals ("OF") or lowercase
    /// on purpose stays as typed, the word being typed is never touched (so the last word keeps its capital),
    /// and the cursor, at the end, doesn't move.
    static func typed(_ new: String, after old: String) -> String {
        guard new.count == old.count + 1, new.hasPrefix(old), new.hasSuffix(" ") else { return new }
        let body = new.dropLast()
        guard let wordStart = body.lastIndex(of: " ").map(body.index(after:)) else { return new }
        // Only a word with something but spaces before it; the first word keeps its capital.
        guard body[..<wordStart].contains(where: { $0 != " " }) else { return new }
        let word = body[wordStart...]
        guard let first = word.first, first.isUppercase,
              word.dropFirst().allSatisfy({ $0.isLowercase }),
              smallWords.contains(word.lowercased()) else { return new }
        return String(body[..<wordStart]) + word.lowercased() + " "
    }
}
