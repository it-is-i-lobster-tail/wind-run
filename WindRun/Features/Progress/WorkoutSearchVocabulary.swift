import Foundation

nonisolated enum WorkoutSearchTerrain: String, Codable, Sendable {
    case hills, uphill, downhill
    /// No steep stretch at all. Only searches ask for this; the index never stores it.
    case flat

    var label: String {
        switch self {
        case .hills: "Hills · 6% or steeper for 100 m"
        case .uphill: "Uphill · 6% or steeper for 100 m"
        case .downhill: "Downhill · 6% or steeper for 100 m"
        case .flat: "Flat · nothing 6% or steeper for 100 m"
        }
    }
}

/// US state names and codes for reading MapKit addresses.
enum WorkoutSearchLocations {
    // MapKit formats US city context as "City, ST". Keep the displayed address and index both forms.
    static func searchAddress(_ address: String, city: String?, region: String?) -> String {
        guard region == "US", let code = stateCode(address, city: city), let state = stateNames[code] else { return address }
        return "\(address) \(code) \(state)"
    }

    static func stateCode(_ address: String, city: String?) -> String? {
        let cityState = city?.split(separator: ",").last?.trimmingCharacters(in: .whitespaces)
        // Rural addresses can lack a city, but still carry the state before the ZIP code.
        let postalState = address.firstMatch(of: /\b([A-Z]{2})\s+\d{5}\b/).map { String($0.1) }
        return [cityState, postalState].compactMap { $0 }.first { stateNames[$0] != nil }
    }

    static let stateNames = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California",
        "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware", "DC": "District of Columbia",
        "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois",
        "IN": "Indiana", "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana",
        "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
        "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
        "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
        "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma",
        "OR": "Oregon", "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina",
        "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont",
        "VA": "Virginia", "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming"
    ]
}

/// The words search treats as the same, and how far a typed word may stray from one it knows.
/// The parser and the scorer both read this, so a word is never understood in one and missed in the other.
enum WorkoutSearchVocabulary {
    /// Each group shares one meaning. The first word is the one chips show.
    static let synonyms: [[String]] = [
        ["hills", "hill", "hilly", "climbing", "climbs", "uphill", "elevation"],
        ["easy", "recovery", "jog", "jogging", "gentle", "relaxed"],
        ["tempo", "threshold"],
        ["track", "oval", "laps"],
        ["intervals", "repeats", "reps", "speedwork", "fartlek"],
        ["long", "longrun"],
        ["rain", "rainy", "raining", "drizzle", "wet", "damp"],
        ["trail", "trails", "singletrack"],
        ["morning", "sunrise", "dawn"],
        ["evening", "sunset", "dusk"],
        ["waterfront", "lakefront", "riverfront", "harbor", "harbour"],
        ["race", "racing", "parkrun"]
    ]

    private static let groups: [String: Int] = {
        var lookup: [String: Int] = [:]
        for (index, group) in synonyms.enumerated() {
            for word in group { lookup[stem(word)] = lookup[stem(word)] ?? index }
        }
        return lookup
    }()

    /// The stems that mean the same as this word, itself included.
    static func meanings(of word: String) -> [String] {
        let own = stem(word)
        guard let group = groups[own] else { return [own] }
        return [own] + synonyms[group].map(stem).filter { $0 != own }
    }

    /// Drops plural and verb endings, so "rides", "riding" and "ride" compare as one word.
    static func stem(_ word: String) -> String {
        var word = word.lowercased()
        guard word.count > 3, word.allSatisfy(\.isLetter) else { return word }
        for ending in ["ing", "ies", "es", "ed", "s"] where word.hasSuffix(ending) && word.count - ending.count >= 3 {
            word.removeLast(ending.count)
            if ending == "ies" { word += "y" }
            break
        }
        if word.hasSuffix("e") || word.hasSuffix("y"), word.count > 3 { word.removeLast() }
        let letters = Array(word)
        if letters.count > 3, letters[letters.count - 1] == letters[letters.count - 2],
           !"aeiou".contains(letters[letters.count - 1]) { word.removeLast() }
        return word
    }

    /// Slips a typed word may have: none under 5 letters, so "5k" never reads as "6k", one from 5, two from 8.
    static func allowedSlips(_ word: String) -> Int {
        guard word.allSatisfy(\.isLetter) else { return 0 }
        return word.count >= 8 ? 2 : (word.count >= 5 ? 1 : 0)
    }

    /// Edits between two words, where a missing, extra, wrong or swapped letter each count as one.
    static func slips(_ a: String, _ b: String, limit: Int) -> Int {
        let a = Array(a), b = Array(b)
        guard abs(a.count - b.count) <= limit else { return limit + 1 }
        if a.isEmpty || b.isEmpty { return max(a.count, b.count) }
        var before = [Int](repeating: 0, count: b.count + 1)
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var best = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    current[j] = min(current[j], before[j - 2] + 1)
                }
                best = min(best, current[j])
            }
            if best > limit { return limit + 1 }
            (before, previous, current) = (previous, current, before)
        }
        return previous[b.count]
    }

    static let synonymScore = 0.75

    /// How well a typed word matches a word in a workout: 1 for the same word or meaning, less for a typo.
    static func closeness(_ wanted: String, to word: String) -> Double {
        if word == wanted || (wanted.count >= 3 && word.hasPrefix(wanted)) { return 1 }
        let stems = meanings(of: wanted), own = stem(word)
        // A word with the same meaning is a close match, so "sunrise" still lists the workouts that say it first.
        if stems.contains(own) { return own == stems[0] ? 1 : synonymScore }
        let allowed = allowedSlips(wanted)
        guard allowed > 0, word.count >= 4 else { return 0 }
        return slips(wanted, word, limit: allowed) <= allowed ? 0.85 : 0
    }

    /// The best closeness of a typed word anywhere in a field's words.
    static func closeness(_ wanted: String, in field: [String]) -> Double {
        var best = 0.0
        for word in field {
            best = max(best, closeness(wanted, to: word))
            if best == 1 { break }
        }
        return best
    }
}
