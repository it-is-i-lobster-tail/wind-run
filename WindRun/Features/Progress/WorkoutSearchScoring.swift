import Foundation

/// Why a workout ranks where it does. Only what fell short is kept, since the row already shows the rest.
struct WorkoutSearchMiss: Hashable {
    enum Kind: Hashable {
        /// The workout's amount was over or under what the search asked for.
        case over, under
        /// The workout doesn't have this at all, such as a place, a word or hills.
        case missing
        /// A typed word matched a similar word, such as "Portand" for Portland.
        case loose(String)
    }
    var filter: WorkoutSearchFilter?
    var term: String?
    var kind: Kind
}

struct WorkoutSearchMatch {
    var id: UUID
    var score: Double
    var misses: [WorkoutSearchMiss]
}

/// Scores each workout that passes the hard parts of a query, from 0 to 1.
///
/// Dates, sports, exclusions and "exactly" are hard: a workout outside them is left out. Every other part
/// gives a score, and a workout's score is their weighted average, so one near miss lowers it instead of
/// leaving it out. A word nothing in the history matches is a light miss.
enum WorkoutSearchScoring {
    static let bestScore = 0.8
    static let closeScore = 0.5
    static let closeLimit = 20
    /// A near miss starts just under a best match and fades to a bare close match at the edge of its fade.
    /// Past that it scores nothing.
    static func nearMiss(_ share: Double) -> Double {
        share > 0 ? closeScore + (bestScore - 0.01 - closeScore) * share : 0
    }
    /// A word nothing in the history has counts as a miss, but weighs a quarter of a real part.
    static let unknownWordWeight = 0.25
    static let unknownOnlyScore = 0.6
    /// A typo or a word with the same meaning counts for a little less than the word itself.
    static let looseWordScore = 0.85
    /// A place the route went through, rather than started in. Still a best match, ranked below a start.
    static let passedThroughScore = 0.9

    struct Part {
        var score: Double
        var weight: Double
        var miss: WorkoutSearchMiss?
    }

    static func isHard(_ filter: WorkoutSearchFilter) -> Bool {
        switch filter {
        case .date, .dayOfMonth, .timeOfDay, .weekday, .sport, .excludingSport, .excludingType, .unsupported: true
        case .similar: false
        case .distance(let op, _, _), .duration(let op, _, _), .pace(let op, _, _),
             .heartRate(let op, _, _), .climb(let op, _, _), .calories(let op, _, _): op == .equal
        default: false
        }
    }

    /// How far past the limit a soft amount fades out, as a share of the limit.
    private static func fade(for filter: WorkoutSearchFilter) -> Double {
        switch filter {
        case .distance, .duration: 0.2
        case .heartRate, .calories, .climb: 0.05
        default: 0
        }
    }

    /// Full marks inside the window, then a near miss that fades out with distance from it.
    static func amount(_ value: Double?, op: WorkoutSearchComparison, target: Double, fade: Double,
                       filter: WorkoutSearchFilter) -> Part {
        guard let value, value > 0 || target == 0 && op != .greater else {
            return Part(score: 0, weight: 1, miss: WorkoutSearchMiss(filter: filter, kind: .missing))
        }
        if op.matches(value, target: target) { return Part(score: 1, weight: 1) }
        let low: Double, high: Double
        switch op {
        case .about: (low, high) = (target * 0.95, target * 1.08)
        case .greater, .atLeast: (low, high) = (target, .infinity)
        case .less, .atMost: (low, high) = (0, target)
        case .equal: (low, high) = (target, target)
        }
        // A value on the edge of a strict limit, such as exactly 5 miles for "under 5 miles", misses by nothing.
        let over = value - high >= low - value
        let gap = max(0, over ? value - high : low - value)
        let reach = max(target * fade, 1)
        let share = max(0, 1 - gap / reach)
        return Part(score: nearMiss(share), weight: 1,
                    miss: WorkoutSearchMiss(filter: filter, kind: over ? .over : .under))
    }

    /// A temperature or wind speed fades out over `reach` (3°C, 2 m/s) past its limit. A workout without
    /// weather misses it.
    static func weather(_ value: Double?, op: WorkoutSearchComparison, target: Double, about: Double, reach: Double,
                        filter: WorkoutSearchFilter) -> Part {
        guard let value else { return Part(score: 0, weight: 1, miss: WorkoutSearchMiss(filter: filter, kind: .missing)) }
        if WorkoutSearchTemperature.matches(value, op, target, about: about) { return Part(score: 1, weight: 1) }
        let (low, high) = WorkoutSearchTemperature.bounds(op, target, about: about)
        // A value right on a strict limit, such as 40°F for "below 40°F", misses by nothing.
        let over = value >= high
        let gap = max(0, over ? value - high : low - value)
        return Part(score: nearMiss(max(0, 1 - gap / reach)), weight: 1,
                    miss: WorkoutSearchMiss(filter: filter, kind: over ? .over : .under))
    }

    /// Pace fades out over 15 seconds per kilometer or mile past the limit, whichever the runner typed.
    static func pace(_ value: Double?, op: WorkoutSearchComparison, target: Double, perMile: Bool,
                     filter: WorkoutSearchFilter) -> Part {
        guard let value else { return Part(score: 0, weight: 1, miss: WorkoutSearchMiss(filter: filter, kind: .missing)) }
        if op.matches(value, target: target) { return Part(score: 1, weight: 1) }
        let reach = perMile ? 15 / 1.609_344 : 15
        let tooSlow = value > target
        let gap = abs(value - target)
        let share = max(0, 1 - gap / reach)
        // A pace is slower when it takes more seconds, so "over" means slower here.
        return Part(score: nearMiss(share), weight: 1,
                    miss: WorkoutSearchMiss(filter: filter, kind: tooSlow ? .over : .under))
    }

    /// Remembers how close each typed word is to each workout word during one search, so 1,000 workouts
    /// compare each distinct word once.
    final class Matcher {
        private var memo: [String: [String: Double]] = [:]
        private var places: [String: [String: Bool]] = [:]
        /// The workouts a "like this one" search compares against.
        var records: [UUID: WorkoutSearchRecord] = [:]

        func closeness(_ wanted: String, to word: String) -> Double {
            if let known = memo[wanted]?[word] { return known }
            let value = WorkoutSearchVocabulary.closeness(wanted, to: word)
            memo[wanted, default: [:]][word] = value
            return value
        }

        func closeness(_ wanted: String, in field: [String]) -> Double {
            var best = 0.0
            for word in field {
                best = max(best, closeness(wanted, to: word))
                if best == 1 { break }
            }
            return best
        }

        /// Words in a field: 1 for the word, less for a typo or a word with the same meaning.
        func words(_ tokens: [String], in field: [String]) -> Double {
            guard !tokens.isEmpty else { return 0 }
            var total = 0.0
            for token in tokens {
                let value = closeness(token, in: field)
                guard value > 0 else { return 0 }
                total += value
            }
            return total / Double(tokens.count)
        }

        private var passing: [String: [String: Bool]] = [:]

        func place(_ place: WorkoutSearchPlace, matches name: String) -> Bool {
            if let known = places[name]?[place.searchableText] { return known }
            let value = place.matchesName(name)
            places[name, default: [:]][place.searchableText] = value
            return value
        }

        func place(_ place: WorkoutSearchPlace, passesThrough name: String) -> Bool {
            let text = place.passedText
            if let known = passing[name]?[text] { return known }
            let value = place.passesThrough(name)
            passing[name, default: [:]][text] = value
            return value
        }
    }

    static func part(_ filter: WorkoutSearchFilter, _ record: WorkoutSearchRecord, fields: Fields, matcher: Matcher) -> Part {
        func text(_ score: Double) -> Part {
            score >= 1 ? Part(score: 1, weight: 1)
                : Part(score: score, weight: 1, miss: WorkoutSearchMiss(filter: filter, kind: score > 0 ? .loose("") : .missing))
        }
        func tokens(_ phrase: String) -> [String] { WorkoutSearchEngine.cachedWords(phrase) }
        switch filter {
        case .sky, .temperature, .wind:
            if filter.matches(record) { return Part(score: 1, weight: 1) }
            // A runner's own "rainy" in a title or note counts as much as the saved weather.
            let written = filter.weatherWords
            if !written.isEmpty && (fields.title.contains(where: written.contains) || fields.notes.contains(where: written.contains)) {
                return Part(score: 1, weight: 1)
            }
            switch filter {
            case .temperature(let op, let x, let label):
                let fahrenheit = WorkoutSearchTemperature.isFahrenheit(label)
                return weather(record.weather.map { WorkoutSearchTemperature.shown($0.temperature, fahrenheit: fahrenheit) },
                               op: op, target: x, about: WorkoutSearchWeather.temperatureAbout, reach: 3, filter: filter)
            case .wind(let op, let x, _):
                return weather(record.weather?.windSpeed, op: op, target: x, about: WorkoutSearchWeather.windAbout, reach: 2, filter: filter)
            default:
                return Part(score: 0, weight: 1, miss: WorkoutSearchMiss(filter: filter, kind: .missing))
            }
        case .type, .terrain:
            return filter.matches(record) ? Part(score: 1, weight: 1)
                : Part(score: 0, weight: 1, miss: WorkoutSearchMiss(filter: filter, kind: .missing))
        case .place(let name):
            guard let place = record.place else {
                return Part(score: 0, weight: 1.5, miss: WorkoutSearchMiss(filter: filter, kind: .missing))
            }
            if matcher.place(place, matches: name) { return Part(score: 1, weight: 1.5) }
            // A route that only went through the place still counts as a best match, below one that
            // started there.
            if matcher.place(place, passesThrough: name) { return Part(score: passedThroughScore, weight: 1.5) }
            let loose = matcher.words(tokens(name), in: fields.place)
            return Part(score: loose >= 1 ? looseWordScore : loose, weight: 1.5,
                        miss: WorkoutSearchMiss(filter: filter, kind: loose > 0 ? .loose(place.city) : .missing))
        case .title(let x): return text(matcher.words(tokens(x), in: fields.title))
        case .notes(let x): return text(matcher.words(tokens(x), in: fields.notes))
        case .titleOrNotes(let x):
            return text(max(matcher.words(tokens(x), in: fields.title), matcher.words(tokens(x), in: fields.notes)))
        case .distance(let op, let x, _):
            return amount(record.distance, op: op, target: x, fade: fade(for: filter), filter: filter)
        case .duration(let op, let x, _):
            return amount(record.duration, op: op, target: x, fade: fade(for: filter), filter: filter)
        case .pace(let op, let x, let label):
            return pace(record.pace, op: op, target: x, perMile: WorkoutSearchEngine.isPerMile(label), filter: filter)
        case .heartRate(let op, let x, _):
            return amount(record.heartRate.map { $0.rounded() }, op: op, target: x, fade: fade(for: filter), filter: filter)
        case .climb(let op, let x, _):
            return amount(record.climb, op: op, target: x, fade: fade(for: filter), filter: filter)
        case .calories(let op, let x, _):
            return amount(record.calories, op: op, target: x, fade: fade(for: filter), filter: filter)
        case .similar(let id, _):
            guard let id, let target = matcher.records[id] else {
                return Part(score: 0, weight: 1.5, miss: WorkoutSearchMiss(filter: filter, kind: .missing))
            }
            let similarity = WorkoutSearchSimilarity.score(record, like: target)
            if similarity >= WorkoutSearchSimilarity.alike { return Part(score: 1, weight: 1.5) }
            // Half as alike is a bare close match.
            let share = max(0, (similarity - WorkoutSearchSimilarity.alike / 2) / (WorkoutSearchSimilarity.alike / 2))
            return Part(score: nearMiss(share), weight: 1.5, miss: WorkoutSearchMiss(filter: filter, kind: .missing))
        case .date, .dayOfMonth, .timeOfDay, .weekday, .sport, .excludingSport, .excludingType, .unsupported:
            return Part(score: filter.matches(record) ? 1 : 0, weight: 1)
        }
    }

    /// A workout's words. Splitting text is the slow part of a search, so each workout is split once and
    /// kept until its title, notes or place change.
    struct Fields {
        var title: [String]
        var notes: [String]
        var place: [String]
        var all: [String]

        init(_ record: WorkoutSearchRecord) {
            title = WorkoutSearchEngine.words(record.title)
            notes = WorkoutSearchEngine.words(record.notes)
            place = WorkoutSearchEngine.words([record.place?.searchableText, record.place?.passedText]
                .compactMap { $0 }.joined(separator: " "))
            all = WorkoutSearchEngine.words(record.sport + " " + record.type) + place + title + notes
        }

        /// What the words come from, to tell when a kept copy is out of date.
        private struct Source: Equatable {
            var title, notes, sport, type: String
            var place: WorkoutSearchPlace?
        }

        private static var cache: [UUID: (key: Source, fields: Fields)] = [:]
        private static var vocabulary: (signature: Int, words: Set<String>)?

        static func of(_ record: WorkoutSearchRecord) -> Fields {
            let key = Source(title: record.title, notes: record.notes, sport: record.sport, type: record.type, place: record.place)
            if let kept = cache[record.id], kept.key == key { return kept.fields }
            let fields = Fields(record)
            if cache.count > 20_000 { cache.removeAll() }
            cache[record.id] = (key, fields)
            return fields
        }

        /// Every word in a history, kept while the history stays the same.
        static func vocabulary(of records: [WorkoutSearchRecord]) -> Set<String> {
            var hasher = Hasher()
            for record in records {
                hasher.combine(record.id)
                hasher.combine(record.title)
                hasher.combine(record.notes)
                hasher.combine(record.place)
            }
            let signature = hasher.finalize()
            if let kept = vocabulary, kept.signature == signature { return kept.words }
            var words = Set<String>()
            for record in records { words.formUnion(of(record).all) }
            vocabulary = (signature, words)
            return words
        }
    }

    /// Scores the workouts that pass every hard part. Words that match no workout at all are returned
    /// separately: they count as a light miss and show as not understood.
    static func score(_ intent: WorkoutSearchIntent, records: [WorkoutSearchRecord])
        -> (matches: [WorkoutSearchMatch], notUnderstood: [String], meanings: [String: String]) {
        let hard = intent.filters.filter(isHard)
        let soft = intent.filters.filter { !isHard($0) }
        let matcher = Matcher()
        // "Like this run" never lists the run itself.
        var targets = Set<UUID>()
        for case let .similar(id?, _) in soft {
            targets.insert(id)
            if let target = records.first(where: { $0.id == id }) { matcher.records[id] = target }
        }
        let passing = records.filter { record in
            !targets.contains(record.id) && hard.allSatisfy { $0.matches(record) } && sortable(record, intent)
        }
        // A word counts only where some workout in the history has it. Otherwise it is noise the runner can see.
        var known: [String] = [], unknown: [String] = []
        // An unknown word the on-device embedding reads as a history word, such as "downpour" as "rain".
        var meanings: [String: String] = [:]
        if !intent.terms.isEmpty {
            let vocabulary = Fields.vocabulary(of: records)
            for term in intent.terms {
                if vocabulary.contains(where: { matcher.closeness(term, to: $0) > 0 }) { known.append(term) }
                else if let meaning = WorkoutSearchMeanings.nearest(term, in: vocabulary) { meanings[term] = meaning }
                else { unknown.append(term) }
            }
        }
        var matches: [WorkoutSearchMatch] = []
        for record in passing {
            let words = Fields.of(record)
            var parts = soft.map { part($0, record, fields: words, matcher: matcher) }
            for term in known {
                let score = matcher.closeness(term, in: words.all)
                parts.append(Part(score: score, weight: 1,
                                  miss: score >= 1 ? nil : WorkoutSearchMiss(term: term, kind: score > 0 ? .loose("") : .missing)))
            }
            // A meaning read from the embedding is never a best match on its own: it counts like a synonym.
            for (term, meaning) in meanings {
                let found = matcher.closeness(meaning, in: words.all) >= 1
                parts.append(Part(score: found ? WorkoutSearchVocabulary.synonymScore : 0, weight: 1,
                                  miss: WorkoutSearchMiss(term: term, kind: found ? .loose(meaning) : .missing)))
            }
            let weight = parts.reduce(0) { $0 + $1.weight } + Double(unknown.count) * unknownWordWeight
            var score = weight > 0 ? parts.reduce(0) { $0 + $1.score * $1.weight } / weight : 1
            // With nothing else to go on, a query of only unknown words still lists what passes its dates and
            // sports, as close matches under their "Not understood" chip, never as an empty screen.
            if parts.isEmpty && !unknown.isEmpty { score = unknownOnlyScore }
            // Best matches meet every part, at least loosely. A workout that misses one is a close match at most,
            // however well it fits the rest, so "over 5 miles in Boise" never lists a 4.9 mile run as a best match.
            if parts.contains(where: { $0.score < looseWordScore }) { score = min(score, bestScore - 0.01) }
            guard score >= closeScore else { continue }
            matches.append(WorkoutSearchMatch(id: record.id, score: score, misses: parts.compactMap(\.miss)))
        }
        return (matches, unknown, meanings)
    }

    /// Superlatives rank by a value, so a workout without that value has no place in the list.
    static func sortable(_ record: WorkoutSearchRecord, _ intent: WorkoutSearchIntent) -> Bool {
        switch intent.sort {
        case .bestEffort: intent.effortMeters.flatMap { record.bestEfforts?[WorkoutSearchEfforts.key($0)] } != nil
        case .hardest, .easiest: (record.heartRate ?? 0) > 0 || record.pace != nil
        case .hottest, .coldest, .windiest: record.weather != nil
        case .fastest: record.pace != nil
        case .longest: record.distance > 0
        case .mostClimb: (record.climb ?? 0) > 0
        case .newest, .oldest: true
        }
    }
}
