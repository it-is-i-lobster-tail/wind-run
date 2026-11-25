import Foundation

/// Expands keyboard emoji using their complete Unicode sequences (including flags and ZWJ).
/// Only search text is expanded. The workout keeps the exact name the runner entered.
nonisolated struct WorkoutIconQuery {
    let text: String
    let emojiNames: [String]

    init(_ input: String) {
        var text = ""
        var names: [String] = []
        for character in input {
            if !character.isASCII,
               let name = Self.names[String(character).replacingOccurrences(of: "\u{FE0F}", with: "")] {
                names.append(name)
                text.append(" ")
            } else {
                text.append(character)
            }
        }
        self.text = text
        emojiNames = names
    }

    private static let names: [String: String] = {
        guard let url = Bundle.main.url(forResource: "WorkoutEmojiNames", withExtension: "tsv"),
              let data = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var names: [String: String] = [:]
        for line in data.split(separator: "\n") where !line.hasPrefix("# Unicode") {
            let pair = line.split(separator: "\t", maxSplits: 1)
            if pair.count == 2 { names[String(pair[0])] = String(pair[1]) }
        }
        return names
    }()
}
