//
//  VoiceScript.swift
//  Wind Run
//

import Foundation

/// Turns a call-out's words into the recorded clips that say them.
///
/// Every phrase the app speaks is recorded once in one voice, in pieces: whole lines such as "Paused.", and
/// short parts such as "1 kilometer,", "pace 5 minutes," and "per kilometer." Each part comes in the forms it's
/// needed in: with a comma, where the voice stays up because more follows, and with a period, where the voice
/// falls at the end. A line is matched with as few clips as possible. If any part of it has no clip, the whole
/// line goes to the synthesized voice instead, so one line never mixes two voices.
struct VoiceScript {
    /// One clip to play, and the silence after it.
    struct Piece: Equatable {
        let clip: String
        let pauseAfter: TimeInterval
    }

    /// Silence after a piece that ends in a comma or period, as a speaker would pause there.
    static let pauseAtPunctuation: TimeInterval = 0.2
    /// Silence between pieces that run straight on, such as "pace 5 minutes" and "20 seconds".
    static let pauseWithin: TimeInterval = 0.03

    private enum Form { case mid, end, line }

    /// Clip names by their words, then by form.
    private let index: [String: [Form: String]]
    /// The most words any clip says, so matching doesn't look further.
    private let longest: Int

    /// - Parameter clips: clip name → the words it says, as recorded ("1 kilometer," or "Paused.").
    init(clips: [String: String]) {
        var index: [String: [Form: String]] = [:]
        var longest = 1
        for (clip, text) in clips {
            let words = Self.words(text)
            guard let last = words.last else { continue }
            let key = words.map(\.word).joined(separator: " ")
            let isLine = clip.hasPrefix("line_") || words.dropLast().contains { $0.punctuation != nil }
            let form: Form = isLine ? .line : (last.punctuation == "," ? .mid : .end)
            index[key, default: [:]][form] = clip
            longest = max(longest, words.count)
        }
        self.index = index
        self.longest = longest
    }

    /// The clips that say `text`, in order, or nil when some part of it has no clip.
    func pieces(for text: String) -> [Piece]? {
        let words = Self.words(text)
        guard !words.isEmpty else { return nil }
        if let line = index[words.map(\.word).joined(separator: " ")]?[.line] {
            return [Piece(clip: line, pauseAfter: 0)]
        }

        // Fewest clips that cover the words from each position to the end.
        let count = words.count
        var best: [[Piece]?] = Array(repeating: nil, count: count + 1)
        best[count] = []
        for start in stride(from: count - 1, through: 0, by: -1) {
            for end in stride(from: min(count, start + longest), to: start, by: -1) {
                guard let rest = best[end] else { continue }
                if let current = best[start], current.count <= rest.count + 1 { continue }
                let key = words[start..<end].map(\.word).joined(separator: " ")
                guard let forms = index[key] else { continue }
                let punctuation = words[end - 1].punctuation
                let wantsEnd = punctuation == "." || end == count
                let clip = wantsEnd ? (forms[.end] ?? forms[.mid]) : (forms[.mid] ?? forms[.end])
                guard let clip else { continue }
                let pause = end == count ? 0 : (punctuation == nil ? Self.pauseWithin : Self.pauseAtPunctuation)
                best[start] = [Piece(clip: clip, pauseAfter: pause)] + rest
            }
        }
        return best[0]
    }

    private struct Word {
        let word: String
        let punctuation: Character?
    }

    /// Lowercased words, each with the comma or period that ended it, if any. A period inside a number stays.
    private static func words(_ text: String) -> [Word] {
        text.replacingOccurrences(of: "\u{2019}", with: "'")
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .compactMap { part in
                var word = String(part)
                var punctuation: Character?
                if let last = word.last, last == "," || last == "." {
                    punctuation = last
                    word.removeLast()
                }
                return word.isEmpty ? nil : Word(word: word, punctuation: punctuation)
            }
    }
}

extension VoiceScript {
    /// The recorded clips that ship with the app.
    static let bundled: VoiceScript = {
        guard let url = Bundle.main.url(forResource: "VoiceClips", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let clips = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return VoiceScript(clips: [:])
        }
        return VoiceScript(clips: clips)
    }()

    /// Where a clip's audio is in the app.
    static func url(of clip: String) -> URL? {
        Bundle.main.url(forResource: "vo_\(clip)", withExtension: "m4a")
    }
}
