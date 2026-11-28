import Foundation

struct WorkoutSearchPlace: Hashable, Codable {
    var address: String
    var city: String
    var state: String
    var country: String
    /// Parks, neighborhoods, towns and states the route went through after the start, from the offline
    /// pack. Nil for workouts placed by Apple Maps, which only knows the start.
    var passed: [String]? = nil

    var cityAndState: String { [city, state].filter { !$0.isEmpty }.joined(separator: ", ") }
    var searchableText: String {
        let stateName = country.uppercased() == "US" ? WorkoutSearchLocations.stateNames[state.uppercased()] : nil
        let stateCode = country.uppercased() == "US" ? Self.stateCodes[state.lowercased()] : nil
        return [address, city, state, country, stateName, stateCode].compactMap { $0 }.joined(separator: " ")
    }

    static let stateCodes = Dictionary(uniqueKeysWithValues: WorkoutSearchLocations.stateNames.map { ($0.value.lowercased(), $0.key) })

    private static func stateCode(_ state: String) -> String? {
        WorkoutSearchLocations.stateNames[state.uppercased()] == nil ? stateCodes[state.lowercased()] : state.uppercased()
    }

    func matchesName(_ name: String) -> Bool {
        let pieces = name.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if pieces.count <= 2, let last = pieces.last, let requestedState = Self.stateCode(last) {
            guard country.uppercased() == "US", Self.stateCode(state) == requestedState else { return false }
            return pieces.count == 1 || WorkoutSearchEngine.words(pieces[0]) == WorkoutSearchEngine.words(city)
        }
        return WorkoutSearchEngine.contains(name, in: searchableText)
    }

    /// The places passed through, as one string of words.
    var passedText: String { (passed ?? []).joined(separator: " ") }

    /// True when the route went through a place with this name after the start.
    func passesThrough(_ name: String) -> Bool {
        guard let passed, !passed.isEmpty else { return false }
        return WorkoutSearchEngine.contains(name, in: passedText)
    }
}

struct WorkoutSearchRecord {
    var id: UUID
    var date: Date
    var sport: String
    var type: String
    var title: String
    var notes: String
    var distance: Double
    var duration: Double
    var place: WorkoutSearchPlace?
    var isCoached: Bool = false
    /// Steep stretches the route held for 100 m. Nil while the workout is still being indexed.
    var terrain: Set<WorkoutSearchTerrain>?
    /// Climb in meters, mean heart rate in beats per minute and active calories, when recorded.
    var climb: Double?
    var heartRate: Double?
    var calories: Double?
    /// The time zone the workout started in. Nil reads the device's current one.
    var timeZone: TimeZone? = nil
    /// The fastest time over each standard distance inside the workout, in seconds, keyed by whole meters.
    /// Nil while the workout is still being indexed.
    var bestEfforts: [Int: Double]? = nil
    /// The squares of about 150 m the route went through, for finding workouts that went the same way.
    var cells: [Int64]? = nil
    /// The weather during the workout, when Apple Weather readings were saved with it.
    var weather: WorkoutSearchWeather? = nil

    var pace: Double? {
        guard distance >= 10, duration > 0 else { return nil }
        return duration / (distance / 1000)
    }
}

enum WorkoutSearchSort: String, Codable {
    case newest, oldest, longest, fastest, mostClimb
    /// The fastest time over the search's effort distance, such as the best 5K inside any run.
    case bestEffort
    /// Heart rate and pace against the runner's own usual.
    case hardest, easiest
    /// By the temperature or wind speed in the workout's saved weather.
    case hottest, coldest, windiest
    /// "PR this year": the workouts holding each best among the ones searched, such as the furthest and the fastest 5K.
    case personalBests
    /// "New PRs": the workouts that set a best when they were recorded, newest first.
    case recordsSet

    var label: String {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .longest: "Longest distance"
        case .fastest: "Fastest average pace"
        case .mostClimb: "Most climb"
        case .bestEffort: "Fastest time"
        case .hottest: "Hottest"
        case .coldest: "Coldest"
        case .windiest: "Windiest"
        case .hardest: "Hardest effort"
        case .easiest: "Easiest effort"
        case .personalBests: "Personal bests"
        case .recordsSet: "PRs set"
        }
    }

    /// Superlatives rank every workout, so screens show the top few first.
    var ranks: Bool { self != .newest && self != .oldest }
}

enum WorkoutSearchComparison: String, Codable {
    case greater, atLeast, less, atMost, equal
    /// A bare amount such as "5k" or "1 hour": real workouts run a little over or under it.
    case about

    func matches(_ value: Double, target: Double) -> Bool {
        switch self {
        case .greater: value > target
        case .atLeast: value >= target
        case .less: value < target
        case .atMost: value <= target
        case .equal: abs(value - target) < 0.000_001
        case .about: value >= target * 0.95 && value <= target * 1.08
        }
    }
}

enum WorkoutSearchFilter: Hashable, Codable {
    case sport(String), excludingSport(String), type(String), excludingType(String)
    case place(String), title(String), notes(String), titleOrNotes(String)
    case date(DateInterval, String)
    /// The same day of every month, such as "day 7 of a month", in the time zone the search was typed in.
    case dayOfMonth(Int, timeZone: String, String)
    case distance(WorkoutSearchComparison, Double, String), duration(WorkoutSearchComparison, Double, String)
    case terrain(WorkoutSearchTerrain)
    /// Mean heart rate in beats per minute, climb in meters and active calories.
    case heartRate(WorkoutSearchComparison, Double, String), climb(WorkoutSearchComparison, Double, String)
    case calories(WorkoutSearchComparison, Double, String)
    /// Average pace in seconds per kilometer. The label keeps the unit the runner typed.
    case pace(WorkoutSearchComparison, Double, String)
    /// A start time window in minutes after local midnight, which can run past midnight, such as "morning".
    case timeOfDay(from: Int, to: Int, String)
    /// Days of the week, 1 for Sunday through 7 for Saturday, in the time zone each workout started in.
    case weekday(Set<Int>, String)
    /// Workouts that went the same way as this one. Nil means the most recent workout.
    case similar(UUID?, String)
    /// What the sky was doing, from the workout's saved weather.
    case sky(WorkoutSearchSky, String)
    /// The temperature in degrees Celsius. The label keeps the unit the runner typed, such as "Below 40°F".
    case temperature(WorkoutSearchComparison, Double, String)
    /// The wind speed in meters a second.
    case wind(WorkoutSearchComparison, Double, String)
    case unsupported(String)

    var label: String {
        switch self {
        case .sport(let x), .type(let x): x.capitalized
        case .excludingSport(let x), .excludingType(let x): "Exclude " + x
        case .place(let x): x
        case .title(let x): "Title contains “" + x + "”"
        case .titleOrNotes(let x): "Title or notes contain “" + x + "”"
        case .notes(let x): "Notes mention “" + x + "”"
        case .date(_, let x), .dayOfMonth(_, _, let x), .duration(_, _, let x), .distance(_, _, let x): x
        case .heartRate(_, _, let x), .climb(_, _, let x), .calories(_, _, let x), .pace(_, _, let x): x
        case .timeOfDay(_, _, let x), .weekday(_, let x), .similar(_, let x): x
        case .sky(_, let x), .temperature(_, _, let x), .wind(_, _, let x): x
        case .terrain(let terrain): terrain.label
        case .unsupported(let x): "Unrecognized: " + x
        }
    }

    func matches(_ record: WorkoutSearchRecord) -> Bool {
        switch self {
        case .sport(let x): record.sport == x
        case .excludingSport(let x): record.sport != x
        case .type(let x): x == record.type || (x == "coached" && record.isCoached)
        case .excludingType(let x): x != record.type && !(x == "coached" && record.isCoached)
        case .place(let x): record.place?.matchesName(x) == true
        case .title(let x): WorkoutSearchEngine.contains(x, in: record.title)
        case .titleOrNotes(let x): WorkoutSearchEngine.contains(x, in: record.title) || WorkoutSearchEngine.contains(x, in: record.notes)
        case .notes(let x): WorkoutSearchEngine.contains(x, in: record.notes)
        case .date(let span, _): (span.start..<span.end).contains(record.date)
        case .dayOfMonth(let day, let zone, _):
            WorkoutSearchEngine.dayOfMonth(record.date, zone: zone) == day
        case .distance(let op, let x, _): record.distance > 0 && op.matches(record.distance, target: x)
        case .duration(let op, let x, _): record.duration > 0 && op.matches(record.duration, target: x)
        case .terrain(let terrain): record.terrain.map {
            switch terrain {
            case .hills: !$0.isEmpty
            case .flat: $0.isEmpty
            default: $0.contains(terrain)
            }
        } == true
        // Compare whole beats, as rows show them, so "over 150" never lists a 150 bpm average.
        case .heartRate(let op, let x, _): record.heartRate.map { $0 > 0 && op.matches($0.rounded(), target: x) } == true
        case .climb(let op, let x, _): record.climb.map { op.matches($0, target: x) } == true
        case .calories(let op, let x, _): record.calories.map { $0 > 0 && op.matches($0, target: x) } == true
        case .pace(let op, let x, _): record.pace.map { op.matches($0, target: x) } == true
        case .timeOfDay(let start, let end, _): WorkoutSearchClock.contains(WorkoutSearchClock.minute(of: record), from: start, to: end)
        case .weekday(let days, _): days.contains(WorkoutSearchClock.weekday(of: record))
        // Scored against the other workout; on its own, a workout is only like itself.
        case .similar(let id, _): id == record.id
        case .sky(let sky, _): record.weather.map(sky.matches) == true
        case .temperature(let op, let x, let label):
            record.weather.map {
                let shown = WorkoutSearchTemperature.shown($0.temperature, fahrenheit: WorkoutSearchTemperature.isFahrenheit(label))
                return WorkoutSearchTemperature.matches(shown, op, x, about: WorkoutSearchWeather.temperatureAbout)
            } == true
        case .wind(let op, let x, _):
            record.weather.map { WorkoutSearchTemperature.matches($0.windSpeed, op, x, about: WorkoutSearchWeather.windAbout) } == true
        case .unsupported: false
        }
    }
}

struct WorkoutSearchIntent: Hashable, Codable {
    var filters: [WorkoutSearchFilter] = []
    var terms: [String] = []
    var sort: WorkoutSearchSort = .newest
    /// State codes typed in capitals away from a city or "in", such as "ME" in "ME trail runs". Search reads
    /// each as a place when a workout started in that state, and as a word otherwise.
    var stateCandidates: [String] = []
    /// The distance a "fastest 5K" search ranks best times over, in meters. Set with `.bestEffort`.
    var effortMeters: Double? = nil

    mutating func append(_ filter: WorkoutSearchFilter) {
        if !filters.contains(filter) { filters.append(filter) }
    }
}

struct WorkoutSearchResult {
    var ids: [UUID]
    var placeChoices: [String]
    var appliedIntent: WorkoutSearchIntent
    /// Near misses for when the best matches are few or none, best first and at most 20.
    var closeIDs: [UUID] = []
    /// Words that matched nothing in the history. They lowered every score a little.
    var notUnderstood: [String] = []
    /// What each close match fell short on.
    var misses: [UUID: [WorkoutSearchMiss]] = [:]
    /// Chip text for places read from a near spelling, such as "Portland (from Portand)", keyed by the place filter's name.
    var looseReadings: [String: String] = [:]
    /// Unknown words read as a history word with the same meaning, such as "downpour" as "rain", keyed by the typed word.
    var meanings: [String: String] = [:]
    /// The personal bests each listed workout holds, which its row stars. For "PR" searches these are the bests
    /// searched for; otherwise they are the all-time bests a workout still holds.
    var marks: [UUID: [WorkoutSearchPersonalBests.Mark]] = [:]
    /// Misspelled words read as the spell checker's fix, such as "tmepo" as "tempo".
    var spelling = WorkoutSearchSpelling.Fixes()
}

enum WorkoutSearchEngine {
    static func words(_ string: String) -> [String] {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static var calendars: [String: Calendar] = [:]

    static func dayOfMonth(_ date: Date, zone: String) -> Int? {
        if calendars[zone] == nil, let timeZone = TimeZone(identifier: zone) {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            calendars[zone] = calendar
        }
        return calendars[zone]?.component(.day, from: date)
    }

    private static var wordCache: [String: [String]] = [:]

    /// `words`, remembered for the short phrases a query repeats against every workout.
    static func cachedWords(_ string: String) -> [String] {
        if let kept = wordCache[string] { return kept }
        if wordCache.count > 2_000 { wordCache.removeAll() }
        let value = words(string)
        wordCache[string] = value
        return value
    }

    static func contains(_ query: String, in text: String) -> Bool {
        let field = words(text)
        let tokens = words(query)
        return !tokens.isEmpty && tokens.allSatisfy { wanted in
            field.contains { $0 == wanted || (wanted.count >= 3 && $0.hasPrefix(wanted)) }
        }
    }

    static func search(_ intent: WorkoutSearchIntent, in records: [WorkoutSearchRecord]) -> WorkoutSearchResult {
        var intent = intent
        var readings: [String: String] = [:]
        for code in intent.stateCandidates {
            let name = WorkoutSearchLocations.stateNames[code]?.lowercased()
            if records.contains(where: { record in
                guard let place = record.place, place.country.uppercased() == "US" else { return false }
                return place.state.uppercased() == code || place.state.lowercased() == name
            }) {
                intent.append(.place(code))
            } else {
                intent.terms.append(code.lowercased())
            }
        }
        intent.stateCandidates = []
        // An unqualified saved city is a location. Resolve after places arrive so this also
        // works for saved history and never has to send place names to the interpreter.
        if !intent.terms.isEmpty {
            let cities = Set(records.compactMap { $0.place?.city }.filter { !$0.isEmpty })
            let typed = WorkoutSearchPlaceNames.words(intent.terms.joined(separator: " "))
            if let city = cities.sorted().first(where: { WorkoutSearchPlaceNames.words($0) == typed }) {
                if words(city) != intent.terms { readings[city] = "\(city) (from \(intent.terms.joined(separator: " ")))" }
                intent.append(.place(city))
                intent.terms = []
            } else if let city = cities.sorted().first(where: { looselyNames($0, intent.terms) }) {
                readings[city] = "\(city) (from \(intent.terms.joined(separator: " ")))"
                intent.append(.place(city))
                intent.terms = []
            }
        }
        // A misspelled word nothing in the history has is read as the spell checker's fix, when search can use it.
        var spelling = WorkoutSearchSpelling.Fixes()
        if !intent.terms.isEmpty {
            let vocabulary = WorkoutSearchScoring.Fields.vocabulary(of: records)
            let matcher = WorkoutSearchScoring.Matcher()
            spelling = WorkoutSearchSpelling.fix(&intent, vocabulary: vocabulary) { term in
                vocabulary.contains { matcher.closeness(term, to: $0) > 0 }
            }
        }
        // "Like my last run" means the newest workout.
        if let index = intent.filters.firstIndex(where: { if case .similar(nil, _) = $0 { true } else { false } }),
           case .similar(_, let label) = intent.filters[index] {
            let latest = records.max { $0.date < $1.date }
            intent.filters[index] = .similar(latest?.id, label)
        }
        let places = Set(records.compactMap(\.place))
        for case let .place(name) in intent.filters {
            let cityMatches = places.filter { words($0.city) == words(name) }
            let choices = Set(cityMatches.map(\.cityAndState))
            if choices.count > 1 { return WorkoutSearchResult(ids: [], placeChoices: choices.sorted(), appliedIntent: intent) }
            if !places.contains(where: { $0.matchesName(name) }),
               let city = places.map(\.city).sorted().first(where: { looselyNames($0, words(name)) }) {
                readings[name] = "\(city) (from \(name))"
            }
        }
        let scored = WorkoutSearchScoring.score(intent, records: records)
        let effortKey = intent.effortMeters.map { WorkoutSearchEfforts.key($0) }
        let intensity = intent.sort == .hardest || intent.sort == .easiest ? WorkoutSearchIntensity.scores(records) : [:]
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let similarTarget: WorkoutSearchRecord? = intent.filters.lazy.compactMap { filter -> WorkoutSearchRecord? in
            if case .similar(let id?, _) = filter { return byID[id] } else { return nil }
        }.first
        func newer(_ lhs: WorkoutSearchRecord, _ rhs: WorkoutSearchRecord) -> Bool {
            lhs.date != rhs.date ? lhs.date > rhs.date : lhs.id.uuidString < rhs.id.uuidString
        }
        func ranked(_ lhs: WorkoutSearchRecord, _ rhs: WorkoutSearchRecord) -> Bool? {
            switch intent.sort {
            case .fastest where lhs.pace != rhs.pace: (lhs.pace ?? .infinity) < (rhs.pace ?? .infinity)
            case .longest where lhs.distance != rhs.distance: lhs.distance > rhs.distance
            case .mostClimb where lhs.climb != rhs.climb: (lhs.climb ?? 0) > (rhs.climb ?? 0)
            case .oldest where lhs.date != rhs.date: lhs.date < rhs.date
            case .bestEffort:
                if let key = effortKey, let a = WorkoutSearchPersonalBests.effort(lhs, key: key),
                   let b = WorkoutSearchPersonalBests.effort(rhs, key: key), a != b { a < b } else { nil }
            case .hardest where intensity[lhs.id] != intensity[rhs.id]: (intensity[lhs.id] ?? 0) > (intensity[rhs.id] ?? 0)
            case .easiest where intensity[lhs.id] != intensity[rhs.id]: (intensity[lhs.id] ?? 0) < (intensity[rhs.id] ?? 0)
            case .hottest where lhs.weather?.temperature != rhs.weather?.temperature:
                (lhs.weather?.temperature ?? -.infinity) > (rhs.weather?.temperature ?? -.infinity)
            case .coldest where lhs.weather?.temperature != rhs.weather?.temperature:
                (lhs.weather?.temperature ?? .infinity) < (rhs.weather?.temperature ?? .infinity)
            case .windiest where lhs.weather?.windSpeed != rhs.weather?.windSpeed:
                (lhs.weather?.windSpeed ?? -.infinity) > (rhs.weather?.windSpeed ?? -.infinity)
            default: nil
            }
        }
        let best = scored.matches.filter { $0.score >= WorkoutSearchScoring.bestScore }.sorted { a, b in
            let lhs = byID[a.id]!, rhs = byID[b.id]!
            // A superlative or "oldest" ranks by its value. Otherwise the best fit comes first and date breaks ties.
            if let order = ranked(lhs, rhs) { return order }
            if let target = similarTarget {
                let x = WorkoutSearchSimilarity.score(lhs, like: target), y = WorkoutSearchSimilarity.score(rhs, like: target)
                if x != y { return x > y }
            }
            if intent.sort == .newest && a.score != b.score { return a.score > b.score }
            return newer(lhs, rhs)
        }
        var close = scored.matches.filter { $0.score < WorkoutSearchScoring.bestScore }.sorted { a, b in
            a.score != b.score ? a.score > b.score : newer(byID[a.id]!, byID[b.id]!)
        }.prefix(WorkoutSearchScoring.closeLimit)
        var ids = best.map(\.id)
        var marks: [UUID: [WorkoutSearchPersonalBests.Mark]]
        switch intent.sort {
        case .personalBests:
            // The bests among the workouts searched, such as this year's, one row per workout that holds any.
            marks = WorkoutSearchPersonalBests.bests(in: ids.compactMap { byID[$0] }, history: records)
            ids = ids.filter { marks[$0] != nil }.sorted { a, b in
                let x = marks[a]![0].kind, y = marks[b]![0].kind
                return x != y ? x < y : newer(byID[a]!, byID[b]!)
            }
            close = []
        case .recordsSet:
            // A best set at the time, against every earlier workout, even ones outside the search's dates.
            marks = WorkoutSearchPersonalBests.set(records)
            ids = ids.filter { marks[$0] != nil }
            close = []
        default:
            marks = WorkoutSearchPersonalBests.standing(records)
            // "Fastest 5K this year": the top row holds the best searched for, whether or not it stands all time.
            if intent.sort == .bestEffort, let key = effortKey, let top = ids.first, let record = byID[top],
               let seconds = WorkoutSearchPersonalBests.effort(record, key: key) {
                let kind = WorkoutSearchPersonalBests.Kind.effort(key)
                var held = (marks[top] ?? []).filter { $0.kind != kind }
                let allTime = WorkoutSearchPersonalBests.standing(records, kinds: [kind])[top] != nil
                held.append(WorkoutSearchPersonalBests.Mark(kind: kind, value: seconds, allTime: allTime))
                marks[top] = held.sorted { $0.kind < $1.kind }
            }
        }
        let listed = Set(ids).union(close.map(\.id))
        marks = marks.filter { listed.contains($0.key) }
        return WorkoutSearchResult(ids: ids, placeChoices: [], appliedIntent: intent,
                                   closeIDs: close.map(\.id), notUnderstood: scored.notUnderstood,
                                   misses: Dictionary(uniqueKeysWithValues: close.map { ($0.id, $0.misses) }),
                                   looseReadings: readings, meanings: scored.meanings, marks: marks,
                                   spelling: spelling)
    }

    /// True when a pace label was typed per mile, such as "under 8 min/mi".
    static func isPerMile(_ label: String) -> Bool {
        label.range(of: #"(?:/|per |an? )\s*mi"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// True when every typed word is a near spelling of the place's words, such as "Portand" for Portland.
    static func looselyNames(_ place: String, _ typed: [String]) -> Bool {
        let name = words(place)
        guard !typed.isEmpty, name.count == typed.count else { return false }
        return zip(typed, name).allSatisfy { wanted, word in
            let allowed = WorkoutSearchVocabulary.allowedSlips(wanted)
            return wanted == word || (allowed > 0 && WorkoutSearchVocabulary.slips(wanted, word, limit: allowed) <= allowed)
        }
    }

    // Consume recognized clauses before treating the remaining words as literal text. Separators
    // keep a location such as "in Portland last month under 1 hour" from swallowing other filters.
    /// `places` are names from the runner's history (`WorkoutSearchPlaceNames.known`), read as places before
    /// any other word.
    static func parse(_ query: String, now: Date = .now, calendar: Calendar = .current,
                      climbInFeet: Bool = climbInFeet, places: [String] = []) -> WorkoutSearchIntent {
        var parser = SearchParser(text: query, now: now, calendar: calendar, feet: climbInFeet, places: places)
        return parser.parse()
    }

    /// A climb typed without a unit follows the runner's distance unit: feet with miles, meters with kilometers.
    static var climbInFeet: Bool {
        UserDefaults.standard.string(forKey: DistanceUnit.storageKey) == DistanceUnit.miles.rawValue
    }
}

private struct SearchParser {
    var text: String
    let now: Date
    let calendar: Calendar
    var feet = false
    var places: [String] = []
    var intent = WorkoutSearchIntent()

    // Each expression is compiled once, and every match is removed from the working copy.
    mutating func take(_ pattern: NSRegularExpression) -> [[String]] {
        let original = text as NSString
        let matches = pattern.matches(in: text, range: NSRange(location: 0, length: original.length))
        let captures = matches.map { match in
            (0..<match.numberOfRanges).map { i in
                let range = match.range(at: i)
                return range.location == NSNotFound ? "" : original.substring(with: range)
            }
        }
        let mutable = NSMutableString(string: text)
        for match in matches.reversed() { mutable.replaceCharacters(in: match.range, with: " | ") }
        text = mutable as String
        return captures
    }

    static func regex(_ pattern: String) -> NSRegularExpression {
        // These are fixed grammar expressions, never user-provided regular expressions.
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static let quotedValue = #"[“"'‘]([^"”'’]+)["”'’]"#
    // A field can precede its literal ("notes mention …"), follow it ("… as its title"),
    // or introduce it with punctuation. Protect those literals before parsing other clauses.
    private static let fieldLabel = regex(#"\b(title|name|notes?)(?:\s+(?:includes?|contains?|mentions?))?\s*:\s*([^.;?!]+?)(?=\s*,\s*(?:title|name|notes?)\b|[.;?!]|$)"#)
    private static let quotedField = regex(quotedValue + #"\s+(?:(?:as|in|within|was|is)\s+)?(?:(?:my|the|its|their|workout['’]s)\s+)?(title|name|notes?)\b"#)
    private static let eitherField = #"(?:titles?\s+or\s+notes?|notes?\s+or\s+titles?)"#
    private static let eitherSuffix = regex(
        #"\b(?:matching|with|containing)\s+([^,;?!|]+?)\s+in\s+(?:(?:the|my|their)\s+)?"# + eitherField + #"\b"#
    )
    private static let eitherQuoted = regex(quotedValue + #"\s+in\s+(?:(?:the|my|their)\s+)?"# + eitherField + #"\b"#)
    private static let fieldSuffix = regex(
        #"\b(?:with|have|has|had)\s+([^,.;?!|]+?)\s+(?:in|within)\s+(?:(?:their|its|my|the)\s+)?(title|name|notes?)\b"#
    )
    private static let writeAbout = regex(#"\b(?:write|wrote|note|noted|mention|mentioned)\s+"# + quotedValue + #"\s+(?:about|during|for)\b"#)
    private static let notePhrase = regex(#"\b(?:wrote|mentioned|noted)\s+([^|?!.,]+?)\s+in\s+(?:(?:the|my|its|their)\s+)?notes?\b"#)
    private static let writtenNote = regex(#"(?:\b(?:wrote|recorded|logged|noted|mentioned)\s+)?[\"“]([^\"”]+)[\"”]\s+(?:in|within)\s+(?:(?:the|my|its|their)\s+)?notes?\b"#)
    private static let quote = regex(#"\b(notes?\s+(?:mention(?:s|ing|ed)?|contain(?:s|ing)?|say(?:s)?|about)|mentioned|(?:titled|named|called)|(?:the\s+)?title(?:\s+(?:contains?|includes?))?)\s+[\"“]([^\"”]+)[\"”]"#)
    private static let sportType = regex(#"\b(?:(skip(?:ping)?|exclud(?:e|ing)|except(?: for)?|without|besides|other than|apart from|leav(?:e|ing) out|no|not|non|(?:is|was|were|are)n['’]t)[\s-]+(?:(?:any|my|a|an|the)\s+)?)?(running|runner|runs?|ran|jogs?|jogging|cycling|cycles?|bicycles?|biking|bikes?|rides?|rode|hiking|hikes?|hiked|intervals?(?:\s+training)?|coached|coach|free|timed|distance\s+(?:runs?|workouts?)|time\s+(?:runs?|workouts?))\b"#)
    // Remove speech framing only in a request or next to the field it describes.
    // An unrecognized word remains a text constraint.
    private static let requestIntro = regex(#"(?:^|[|;?!])[,\s]*(?:please\s+)?(?:I\s+(?:mean|meant)|pull\s+up|look\s+(?:up|for|through)|search\s+(?:through|for)|retrieve|rank|I\s+(?:want|would like)(?:\s+to\s+(?:see|find))?|are there|were there)\b"#)
    private static let historyContext = regex(
        #"\b(?:in|from|through|of)\s+(?:(?:my|the)\s+)?(?:(?:workout|session)\s+)?(?:history|records|archive|log)\b|"# +
        #"\bon record\b"#
    )
    private static let startLocationVerb = regex(#"\b(?:began|commenced|originated)\s+(?=(?:in|at|near|from)\b)"#)
    private static let recordedLocation = regex(#"\b(?:training|workouts?|sessions?|activities|outings?)\s+(?:recorded|logged|tracked)\s+(?=(?:in|at|near|from)\b)"#)
    private static let explicitType = regex(
        #"\b(?:(not|except|excluding|without)\s+(?:(?:workouts?|sessions?|activities|outings?)\s+)?)?(?:of\s+type|(?:recorded|logged|classified)\s+as)\s+(free|distance|time|timed|intervals?|coached)\b"#
    )
    private static let dated = regex(#"\bdated\s+(?=\d{4}-\d{2}-\d{2}\b)"#)
    private static let recordedKind = regex(#"\b(?:recorded|logged|tracked|completed)\s+(?=(?:runs?|hikes?|rides?|workouts?|sessions?|intervals?)\b)"#)
    private static let recordedAction = regex(#"\b(?:I|we)(?:\s+(?:have|had|did))?(?:\s+(?:ever|previously))?\s+(?:record(?:ed)?|log(?:ged)?|track(?:ed)?|complet(?:e|ed)|done)\b"#)
    private static let sorting = regex(#"\b(?:(?:(?:went|came|occurred|happened|finished)(?: the)?|had (?:my|the))\s+)?(fastest(?:\s+(?:average\s+)?pace)?|best (?:average |avg )?pace|fast(?:er)?(?:\s+pace)?|quick(?:est)?|speediest|long(?:est|er)?(?:\s+distance)?|farthest|furthest|most (?:distance|ground|mileage|miles|kilometers)|greatest (?:mileage|distance)|distance record|oldest|earliest|first(?: ever)?(?: record(?:ed)?)?(?=\s+(?:a\s+|an\s+|the\s+)?(?:workout|session|outing|run|ride|hike|interval|coached|free|bike))|newest|most recent(?:ly)?|latest)\b"#)
    private static let activeTime = regex(#"\b(?:active|moving)\s+(?:time|duration)\b|\b(?:excluding|without|excluding the)\s+(?:paused|pause)\s+time\b"#)
    private static let magnitude = #"\d+(?:\.\d+)?|one|two|three|four|five|six|seven|eight|nine|ten|twenty|thirty|forty|fifty|sixty|ninety"#
    private static let units = #"kilomet(?:er|re)s?|km|k|miles?|mi|met(?:er|re)s?|hours?|hrs?|h|minutes?|mins?|seconds?|secs?"#
    // A shared unit applies to both ends: "between 12 and 18 minutes".
    private static let measurementBounds = regex(
        #"\b(?:between|from)\s+("# + magnitude + #")\s*("# + units + #")?\s+(?:and|to)\s+("# +
        magnitude + #")\s*(?:(?:active|moving)\s+)?("# + units + #")\b"#
    )
    // A trailing unit disambiguates a numeric range from a date such as "Nov 8".
    private static let dashedMeasurement = regex(
        #"(?<![\p{L}\d.‐‑–—-])(\d+(?:\.\d+)?)\s*("# + units + #")?\s*[-‐‑–—]\s*(\d+(?:\.\d+)?)\s*("# + units + #")\b"#
    )
    // Captures are comparator, magnitude, unit, then an optional trailing comparator.
    private static let measurement = regex(
        #"(?<![\p{L}\d.])(?:(?:measur(?:ing|ed)|reach(?:ing|ed)|mov(?:ing|ed) for)\s+)?"# +
        #"(?:(more than|greater than|no longer than|longer than|no shorter than|above|over|past|beyond|(?:did not |does not |do not |didn['’]t )reach|(?:did not |does not |do not )exceed|not exceeding|exceed(?:s|ed|ing)?|"# +
        #"(?:a )?minimum of|(?:a )?maximum of|at least|no less than|no fewer than|not less than|at or above|less than|fewer than|shorter than|under|below|at most|at or below|"# +
        #"no more than|no greater than|not more than|up to(?: and including)?|at exactly|at|exactly|precisely|>=|<=|≥|≤|>|<)\s*)?"# +
        #"("# + magnitude + #")"# +
        #"\s*(?:(?:active|moving)\s+)?("# + units + #")\b"# +
        #"(?:\s+(?:of\s+)?(?:(?:active|moving)(?:\s+time)?|activity)\b)?"# +
        #"(?:\s+(or (?:more|less|longer|shorter|fewer|greater|higher|above|further|farther)|and (?:above|below)|minimum|maximum))?"# +
        #"(?:\s+(?:of\s+)?(?:(?:active|moving)(?:\s+time)?|activity)\b)?"#
    )
    private static let isoComponents = #"(\d{4})-(\d{2})-(\d{2})\b"#
    private static let dateISO = regex(#"\b"# + isoComponents)
    private static let cutoffPrefix = #"\b(?:(?:available|recorded|logged|completed)\s+)?(on or before|on or after|(?:before|by) the end of|no later than|(?:as )?known on|as of|as at|up to|through|by|before|after|since)\s+"#
    private static let cutoffISO = regex(cutoffPrefix + isoComponents)
    private static let dateRangeISO = regex(#"\b(?:from|between)\s+"# + isoComponents + #"\s+(?:to|through|and)\s+"# + isoComponents)
    private static let cutoffWeek = regex(
        #"\b(?:(?:available|recorded|logged|completed)\s+)?(on or before|on or after|(?:before|by) the end of|no later than|as of|as at|up to|through|by|before|after|since|at)\s+"# +
        #"(?:(?:the )?end of )?(?:week|checkpoint)\s+(\d{1,2})\b"#)
    // A trailing "(week 12)" says when the question was asked.
    private static let weekNote = regex(#"\((\s*)(?:week|checkpoint)\s+(\d{1,2})\s*\)"#)
    // "On 2025-03-02, … so far this year" asks from that day, so the day ends the range instead of being it.
    private static let soFarOn = regex(#"(?:^|[|;?!.,])\s*(on)\s+"# + isoComponents + #"(?=.*\bso far\b)"#)
    private static let soFar = regex(#"\bso far\b"#)
    // "On day 7 of a month" is that day of every month.
    private static let dayOfMonth = regex(#"\b(?:on\s+)?(?:the\s+)?day\s+(\d{1,2})\s+of\s+(?:a|the|each|every|any)\s+month\b"#)
    private static let relative = regex(#"\b(today|yesterday|(?:this|last|previous)\s+(?:calendar\s+)?(?:week|month|year))\b(?:['’]s\b)?"#)
    private static let recent = regex(#"\b(?:last|past)\s+(\d+)\s+(days?|weeks?|months?)\b"#)
    private static let monthName = #"(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)"#
    private static let namedDay = monthName + #"\s+(\d{1,2})(?:st|nd|rd|th)?(?:,?\s+(\d{4}))?(?![\p{L}\d])"#
    private static let calendarDay = regex(#"\b"# + namedDay)
    private static let monthOnly = regex(#"\b"# + monthName + #"(?:\s+(\d{4}))?\b"#)
    private static let cutoffNamed = regex(cutoffPrefix + namedDay)

    // A bare "in" can be part of the note itself. End an unquoted note at a
    // separate calendar, start-place or comparison clause; quotes protect any literal.
    private static let requestedNote = regex(
        #"\b(?:(?:notes?\s+)?(?:mentions?|mentioning)|(?:search|look\s+in)\s+(?:(?:my|the)\s+)?notes?\s+for)\s+([^|,;?!]+?)(?=\s+(?:and\s+)?(?:(?:in|during|from)\s+(?:"# +
        monthName + #"|this|last|previous)\b|(?:starting|started)\s+(?:in|at|near)\b|(?:in|near|from)\s+(?-i:\p{Lu})|(?:over|under|above|below|at least|at most)\s+(?:"# +
        magnitude + #")\b|(?:this|last|previous)\s+(?:week|month|year)\b)|[|,;?!]|$)"#
    )
    private static let quotedRequestedNote = regex(
        #"\b(?:(?:notes?\s+)?(?:mentions?|mentioning)|(?:search|look\s+in)\s+(?:(?:my|the)\s+)?notes?\s+for)\s+"# + quotedValue
    )
    private static let includingSport = regex(#"\bincluding\s+(?=(?:runs?|rides?|hikes?)\b)"#)
    private static let scope = regex(#"\b(notes?\s+(?:mention(?:s|ing|ed)?|contain(?:s|ing)?|say(?:s)?|about)|mentioned|(?:titled|named|called)|(?:the\s+)?title(?:\s+(?:contains?|includes?))?)\s+([^|?!]+?)(?=\s+(?:in|near|from|during|under|over|and|but)\b|[|?!]|$)"#)
    private static let paceQualifier = regex(#"\b(?:by|on)\s+(?:my\s+)?(?:average|avg)\s+pace\b"#)
    private static let place = regex(#"\b(?:in|near|around|from|out of|at)\s+(?!(?:sessions?|workouts?|my notes|its notes|the notes)\b)([^|?!]+?)(?=\s+(?:where|whose|with|that|which|for which|but|and|has|have|had|were|was|are|is|took|taking|lasted|lasting|came|occurred|happened|finished|except|excluding|without|skip|besides|other than|leaving out)\b|[|?!]|$)"#)
    private static let stateNames = WorkoutSearchLocations.stateNames.values
        .sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
    private static let stateAbbreviations = WorkoutSearchLocations.stateNames.keys.sorted().joined(separator: "|")
    private static let stateName = regex("\\b(" + stateNames + ")\\b")
    // A standalone city/state clause can precede a follow-up such as "list workouts there".
    private static let qualifiedCity = regex(
        #"(?:^|[|;.?!])\s*([\p{L}][\p{L}’'.-]*(?:\s+[\p{L}][\p{L}’'.-]*){0,5},\s*(?:"# +
        stateNames + "|" + stateAbbreviations + #"))\b"#
    )
    private static let stateCode = try! NSRegularExpression(pattern: "\\b(" + stateAbbreviations + ")\\b")
    private static let excludedPlace = regex(#"\b(?:not|never|except|outside(?: of)?|excluding|without)\s+(?:in|near|from|around)\s+[^|?!]+"#)
    private static let terrain = regex(#"\b(?:(?:steep|sustained)\s+)?(hills?|hilly|grades?|uphills?|inclines?|downhills?|declines?|descents?|descending|flat)\b"#)
    // Recorded effort: mean heart rate, climb and active calories. A number needs a metric word or its own unit.
    private static let metricWord = #"((?:(?:average|avg|mean)\s+)?heart\s*rate|(?:average|avg|mean)\s+hr|bpm|calories|kcal|climb(?:ing|ed)?|elevation(?:\s+gain)?|ascent|vert(?:ical)?(?:\s+gain)?)"#
    private static let metricComparator = #"(more than|greater than|higher than|above|over|at least|no less than|less than|lower than|fewer than|under|below|at most|no more than|>=|<=|≥|≤|>|<)"#
    private static let metricUnit = #"(bpm|kcal|calories|cal|meters|metres|meter|metre|m|feet|foot|ft)"#
    // Stop a bare number from taking a distance or time that follows it: "climbing over 5 km" is not a climb.
    private static let notDistance = #"(?![\p{L}\d])(?!\s*(?:km?\b|kilo|mi\b|miles?\b|min|hours?\b|hrs?\b|h\b|sec))"#
    private static let metricFirst = regex(#"\b"# + metricWord + #"\s+(?:(?:was|is|of|at|stayed|averaged)\s+)?(?:"# + metricComparator +
                                           #"\s*)?(\d+(?:\.\d+)?)\s*"# + metricUnit + "?" + notDistance)
    private static let metricLast = regex(#"(?<![\p{L}\d.])(?:"# + metricComparator + #"\s*)?(\d+(?:\.\d+)?)\s*"# + metricUnit +
                                          #"?\s+(?:of\s+)?(?:(?:the|my)\s+)?"# + metricWord + #"\b"#)
    // "under 8 min/mi", "pace faster than 5:30 per km", "7:45 a mile pace". Read before durations take "8 min".
    private static let paceClause = regex(
        #"(?:\b(?:average\s+|avg\s+)?pace\s+(?:(?:was|is|of|at)\s+)?)?(?:(under|below|faster than|quicker than|less than|sub|better than|over|above|slower than|more than|at least|at most|no slower than|no faster than)\s*)?"# +
        #"(?<![\p{L}\d.:])(\d{1,2}(?::[0-5]\d)?|\d{1,2}\.\d+)\s*(?:min(?:ute)?s?(?:\s+|-)?)?(?:/|per\s+|an?\s+)\s*(mi(?:les?)?|km|kilomet(?:er|re)s?)\b(?:\s+pace)?"#)
    private static let metricUnitOnly = regex(#"(?<![\p{L}\d.])(?:"# + metricComparator + #"\s*)?(\d+(?:\.\d+)?)\s*(bpm|kcal|calories|cal)\b"#)
    private static let mostClimb = regex(#"\b(?:(?:the\s+)?(?:most|highest|biggest|greatest|largest)\s+)?(?:hilliest|climb(?:s|ing|ed)?|elevation(?:\s+gain)?|ascent|vert(?:ical)?(?:\s+gain)?)\b"#)
    private static let hasHeartRate = regex(#"\b(?:(?:the\s+)?(?:highest|lowest|most)\s+)?(?:(?:average|avg|mean)\s+)?(?:heart\s*rate|bpm)\b"#)
    private static let hasCalories = regex(#"\b(?:(?:the\s+)?(?:most|highest)\s+)?(?:calories|kcal)\b"#)
    // Race names stand for their distance, give or take what the course and GPS add.
    private static let raceDistance = regex(#"\b(half[\s-]?marathons?|marathons?)\b"#)
    private static let unsupported = regex(#"\b(?:cadence|elapsed(?:\s+time)?|felt|ignore\s+(?:all|previous|prior)|system\s+prompt)\b"#)
    // "Fastest 5K", "best mile", "half marathon PR": the fastest stretch of that distance inside any workout.
    private static let effortDistance = #"(400\s*m(?:eters?|etres?)?|800\s*m(?:eters?|etres?)?|(?:1|one)\s*k(?:m|ilomet(?:er|re))?|1,?000\s*m(?:eters?|etres?)?|(?:(?:1|one|a)\s+)?mile|(?:2|two)\s*mi(?:les?)?|(?:5|five)\s*k(?:m)?|5,?000\s*m(?:eters?|etres?)?|(?:10|ten)\s*k(?:m)?|10,?000\s*m(?:eters?|etres?)?|15\s*k(?:m)?|(?:10|ten)\s*mi(?:les?)?|half[\s-]*marathon|half|marathon)"#
    private static let effortLead = regex(#"\b(?:fastest|best|quickest|top|personal\s+(?:best|record)|pr|pb)\s+(?:times?\s+(?:for|over|in)\s+(?:a|an|the|my)?\s*)?"# + effortDistance + #"(?:\s+(?:times?|efforts?|splits?|segments?|races?))?(?![\p{L}\d])"#)
    private static let effortTrail = regex(#"(?<![\p{L}\d])"# + effortDistance + #"\s+(?:prs?|pbs?|personal\s+(?:bests?|records?)|records?|best(?:\s+times?)?|fastest(?:\s+times?)?)\b"#)
    // "New PR", "PRs set", "broke my PB": the workouts that set a best when they were recorded.
    private static let newRecord = regex(#"\b(?:(?:new|set|broke|broken|beat|beaten|hit|got)\s+(?:(?:a|an|my|any)\s+)?(?:new\s+)?(?:prs?|pbs?|personal\s+(?:bests?|records?|prs?))|(?:prs?|pbs?|personal\s+(?:bests?|records?)|records?)\s+(?:(?:i|were|was)\s+)?(?:set|broken|broke|beaten))\b"#)
    // "PR", "PBs", "personal bests", "my bests" with no distance: the bests among the workouts searched.
    private static let anyRecord = regex(#"\b(?:prs?|pbs?|personal\s+(?:bests?|records?|prs?)|bests)\b"#)
    private static let intensity = regex(#"\b(hardest|toughest|most\s+(?:intense|difficult|demanding)|biggest\s+efforts?|easiest|most\s+relaxed|gentlest|lightest)\b"#)
    private static let similarRun = regex(#"\b(?:like|similar\s+to|same\s+(?:route|course|way|loop|path)\s+as)\s+(?:my\s+|the\s+)?(?:last|latest|most\s+recent|previous)\s+(?:one|run|workout|time|ride|hike|outing)\b"#)
    // Parts of the day, in the time zone each workout started in.
    private static let dayPart = regex(#"\b(?:(this)\s+)?(early[\s-]+mornings?|mornings?|lunch\s*(?:time|break)?s?|midday|noon|afternoons?|evenings?|late[\s-]+nights?|nights?|night\s*time|nighttime|after\s+dark)\b"#)
    private static let clockTime = regex(#"\b(?:(before|after|by|earlier\s+than|later\s+than|around|about|at)\s+)?(\d{1,2})(?::(\d{2}))?\s*([ap])\.?\s?m\b\.?"#)
    private static let clockTime24 = regex(#"\b(before|after|earlier\s+than|later\s+than|around|at)\s+(\d{1,2}):(\d{2})\b"#)
    private static let weekdayName = #"(sundays?|mondays?|tuesdays?|wednesdays?|thursdays?|fridays?|saturdays?)"#
    private static let pastWeekday = regex(#"\b(last|this\s+past|previous|this)\s+"# + weekdayName + #"\b"#)
    private static let anyWeekday = regex(#"\b"# + weekdayName + #"\b"#)
    private static let weekPart = regex(#"\b(?:(last|this\s+past|previous|this)\s+)?(weekends?|weekdays?|week\s+days?|workdays?|work\s+days?|school\s+days?)\b"#)

    // Weather, from each workout's saved Apple Weather readings. "In the rain" is read before places take "in".
    private static let weatherSort = regex(#"\b(hottest|warmest|coldest|coolest|chilliest|windiest|rainiest|wettest|snowiest)\b"#)
    private static let weatherComparator = #"(below|under|less than|lower than|colder than|cooler than|over|above|more than|higher than|warmer than|hotter than|at least|at most|no more than|no less than|around|about|>=|<=|≥|≤|>|<)"#
    private static let temperatureAmount = regex(
        #"(?:\b(?:temp(?:erature)?s?|feels?\s+like)\s+(?:(?:was|were|is|of|at)\s+)?)?(?:"# + weatherComparator +
        #"\s*)?(?<![\p{L}\d.])(-?\d{1,3})\s*(?:°\s*([fc])?|degrees?(?:\s+(fahrenheit|celsius|f|c)\b)?|([fc])(?![\p{L}\d]))"#
    )
    private static let temperatureBare = regex(
        #"\btemp(?:erature)?s?\s+(?:(?:was|were|is|of|at)\s+)?"# + weatherComparator + #"\s*(-?\d{1,3})(?![\p{L}\d.:])"#
    )
    private static let windUnit = #"(mph|km\s*/\s*h|kph|kmh|m\s*/\s*s)"#
    private static let windFirst = regex(
        #"\b(?:wind(?:\s+speeds?)?|winds|gusts?)\s+(?:(?:was|were|is|of|at)\s+)?(?:"# + weatherComparator +
        #"\s*)?(\d{1,3}(?:\.\d+)?)\s*"# + windUnit + #"?(?![\p{L}\d])"#
    )
    private static let windLast = regex(
        #"(?<![\p{L}\d.])(?:"# + weatherComparator + #"\s*)?(\d{1,3}(?:\.\d+)?)\s*"# + windUnit + #"\s+(?:of\s+)?(?:winds?|gusts?)\b"#
    )
    private static let weatherWord = regex(
        #"\b(?:(?:in|on|during|through)\s+(?:the\s+|a\s+)?)?(rain(?:y|ing)?|wet|drizzl(?:e|y|ing)|showers|snow(?:y|ing)?|sleet|"# +
        #"thunder(?:storms?|y)?|storm(?:y|s)?|fog(?:gy)?|misty|mist|hazy|cloudy|overcast|gr[ae]y\s+skies|sunny|sunshine|"# +
        #"clear\s+(?:skies|sky|days?|nights?)|humid(?:ity)?|muggy|windy|breezy|gusty|cold|chilly|freezing|frosty|frigid|icy|"# +
        #"hot|heat(?:\s*wave)?|warm(?![\s-]*ups?\b)|scorching|sweltering|weather)\b(?:\s+(?:days?|weather|out(?:side)?|conditions))?"#
    )

    mutating func parse() -> WorkoutSearchIntent {
        // A state code that is also a word, such as IN, OR or ME, is a place only when the query gives a
        // reason: it is the whole query, it follows "in" or a city, or it is in capitals and a workout started there.
        let standalone = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if WorkoutSearchLocations.stateNames[standalone.uppercased()] != nil {
            intent.append(.place(standalone.uppercased()))
            return intent
        }
        for match in take(Self.eitherSuffix) + take(Self.eitherQuoted) { addTextFilter([match[0], "either", match[1]]) }
        for match in take(Self.fieldLabel) { addTextFilter(match) }
        for match in take(Self.writtenNote) { intent.append(.notes(match[1])) }
        for match in take(Self.quotedField) { addTextFilter([match[0], match[2], match[1]]) }
        for match in take(Self.fieldSuffix) { addTextFilter([match[0], match[2], match[1]]) }
        for match in take(Self.writeAbout) { intent.append(.notes(match[1])) }
        for match in take(Self.notePhrase) { intent.append(.notes(match[1])) }
        for match in take(Self.quote) { addTextFilter(match) }
        for match in take(Self.quotedRequestedNote) { addMention(match) }
        // Names from the runner's own history come before every other word, so "Nob Hill" is a place, not hills.
        let known = WorkoutSearchPlaceNames.find(in: text, known: places)
        if !known.isEmpty {
            let mutable = NSMutableString(string: text)
            for found in known.reversed() { mutable.replaceCharacters(in: found.range, with: " | ") }
            text = mutable as String
            for found in known { intent.append(.place(found.name)) }
        }
        for _ in take(Self.similarRun) { intent.append(.similar(nil, "Like your last workout")) }
        for match in take(Self.effortLead) + take(Self.effortTrail) { addEffort(match[1]) }
        for _ in take(Self.newRecord) { intent.sort = .recordsSet }
        // "Fastest 5K PR" already ranks the 5K, so the leftover "PR" only needs consuming.
        for _ in take(Self.anyRecord) where intent.sort == .newest { intent.sort = .personalBests }
        for match in take(Self.intensity) {
            let word = match[1].lowercased()
            let easy = word.hasPrefix("eas") || word.hasSuffix("relaxed") || word.hasPrefix("gent") || word.hasPrefix("light")
            intent.sort = easy ? .easiest : .hardest
        }
        addTimesOfDay()
        addWeekdays()
        for match in take(Self.dateRangeISO) {
            if let lower = isoDay(Array(match[1...3])), let upper = isoDay(Array(match[4...6])), lower.start < upper.end {
                intent.append(.date(DateInterval(start: lower.start, end: upper.end), match[0]))
            } else { intent.append(.unsupported(match[0])) }
        }
        for match in take(Self.soFarOn) { addCutoff([match[0], "through"], span: isoDay(Array(match.dropFirst(2)))) }
        _ = take(Self.soFar)
        for match in take(Self.cutoffISO) { addCutoff(match, span: isoDay(Array(match.dropFirst(2)))) }
        for match in take(Self.cutoffNamed) { addCutoff(match, span: namedSpan(month: match[2], day: match[3], year: match[4])) }
        for match in take(Self.cutoffWeek) + take(Self.weekNote) {
            var iso = Calendar(identifier: .iso8601)
            iso.timeZone = calendar.timeZone
            let year = iso.component(.yearForWeekOfYear, from: now)
            let week = Int(match[2])
            let parts = DateComponents(weekday: 2, weekOfYear: week, yearForWeekOfYear: year)
            let span = iso.date(from: parts).flatMap { date in
                iso.component(.weekOfYear, from: date) == week && iso.component(.yearForWeekOfYear, from: date) == year
                    ? iso.dateInterval(of: .weekOfYear, for: date) : nil
            }
            addCutoff(match, span: span)
        }
        // Literal note/title phrases may contain sport, quantity or place words.
        for match in take(Self.requestedNote) { addMention(match) }
        _ = take(Self.includingSport)
        for match in take(Self.scope) { addTextFilter(match) }
        // After note and title phrases, so "notes mention rain" stays a note search.
        addWeather()
        _ = take(Self.requestIntro)
        _ = take(Self.recordedAction)
        _ = take(Self.historyContext)
        _ = take(Self.startLocationVerb)
        _ = take(Self.recordedLocation)
        _ = take(Self.dated)
        for match in take(Self.explicitType) {
            let word = match[2].lowercased()
            let value = word.hasPrefix("interval") ? "intervals" : (word == "timed" ? "time" : word)
            intent.append(match[1].isEmpty ? .type(value) : .excludingType(value))
        }
        for match in take(Self.paceClause) { addPace(match) }
        for match in take(Self.metricFirst) { addMetric(label: match[0], word: match[1], comparator: match[2], number: match[3], unit: match[4]) }
        for match in take(Self.metricLast) { addMetric(label: match[0], word: match[4], comparator: match[1], number: match[2], unit: match[3]) }
        for match in take(Self.metricUnitOnly) { addMetric(label: match[0], word: "", comparator: match[1], number: match[2], unit: match[3]) }
        for bound in take(Self.measurementBounds) + take(Self.dashedMeasurement) {
            let lowerUnit = bound[2].isEmpty ? bound[4] : bound[2]
            if Self.isDurationUnit(lowerUnit) == Self.isDurationUnit(bound[4]) {
                addQuantity(["At least \(bound[1]) \(lowerUnit)", "at least", bound[1], lowerUnit, ""])
                addQuantity(["At most \(bound[3]) \(bound[4])", "at most", bound[3], bound[4], ""])
            } else { intent.append(.unsupported(bound[0])) }
        }
        for match in take(Self.measurement) { addQuantity(match) }
        for match in take(Self.raceDistance) {
            let half = match[1].lowercased().hasPrefix("half")
            intent.append(.distance(.about, half ? 21_097.5 : 42_195, half ? "Half marathon" : "Marathon"))
        }
        if intent.filters.contains(where: { if case .duration = $0 { true } else { false } }) {
            _ = take(Self.activeTime)
        }
        for match in take(Self.dayOfMonth) {
            if let day = Int(match[1]), (1...31).contains(day) { intent.append(.dayOfMonth(day, timeZone: calendar.timeZone.identifier, match[0])) }
            else { intent.append(.unsupported(match[0])) }
        }
        for match in take(Self.dateISO) {
            if let interval = isoDay(Array(match.dropFirst())) {
                intent.append(.date(interval, match[0]))
            } else { intent.append(.unsupported(match[0])) }
        }
        for match in take(Self.recent) {
            let unit: Calendar.Component = match[2].lowercased().hasPrefix("day") ? .day :
                (match[2].lowercased().hasPrefix("week") ? .weekOfYear : .month)
            if let count = Int(match[1]), (1...10_000).contains(count),
               let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
               let start = calendar.date(byAdding: unit, value: -count, to: end) {
                intent.append(.date(DateInterval(start: start, end: end), match[0]))
            } else { intent.append(.unsupported(match[0])) }
        }
        for match in take(Self.relative) {
            let phrase = match[1].lowercased()
            let unit: Calendar.Component = phrase.hasSuffix("week") ? .weekOfYear :
                (phrase.hasSuffix("month") ? .month : (phrase.hasSuffix("year") ? .year : .day))
            let offset = phrase == "yesterday" || phrase.hasPrefix("last") || phrase.hasPrefix("previous") ? -1 : 0
            if let date = calendar.date(byAdding: unit, value: offset, to: now),
               let interval = calendar.dateInterval(of: unit, for: date) {
                intent.append(.date(interval, match[0]))
            }
        }
        for match in take(Self.calendarDay) {
            if let span = namedSpan(month: match[1], day: match[2], year: match[3]) { intent.append(.date(span, match[0])) }
            else { intent.append(.unsupported(match[0])) }
        }
        for match in take(Self.monthOnly) {
            if let span = namedSpan(month: match[1], day: "", year: match[2]) { intent.append(.date(span, match[0])) }
            else { intent.append(.unsupported(match[0])) }
        }
        if !take(Self.mostClimb).isEmpty && intent.sort == .newest { intent.sort = .mostClimb }
        if !take(Self.hasHeartRate).isEmpty, !intent.filters.contains(where: { if case .heartRate = $0 { true } else { false } }) {
            intent.append(.heartRate(.greater, 0, "Has heart rate"))
        }
        if !take(Self.hasCalories).isEmpty, !intent.filters.contains(where: { if case .calories = $0 { true } else { false } }) {
            intent.append(.calories(.greater, 0, "Has calories"))
        }
        for match in take(Self.excludedPlace) { intent.append(.unsupported(match[0])) }
        for match in take(Self.place) {
            let name = match[1].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            // "in my runs" names no place. Put its words back so the other clauses still read them.
            if WorkoutSearchEngine.words(name).allSatisfy({ Self.ignored.contains($0) || Self.generic.contains($0) }) {
                text += " " + name
            } else if !name.isEmpty { intent.append(.place(Self.cityAndState(name))) }
        }
        for match in take(Self.terrain) {
            let word = match[1].lowercased()
            if word.hasPrefix("uphill") || word.hasPrefix("incline") { intent.append(.terrain(.uphill)) }
            else if word.hasPrefix("downhill") || word.hasPrefix("decline") || word.hasPrefix("descen") { intent.append(.terrain(.downhill)) }
            else if word == "flat" { intent.append(.terrain(.flat)) }
            else { intent.append(.terrain(.hills)) }
        }
        for match in take(Self.sorting) {
            let raw = match[1].lowercased()
            if raw.hasPrefix("fast") || raw.hasPrefix("quick") || raw.hasPrefix("best ") || raw == "speediest" { intent.sort = .fastest }
            else if raw.hasPrefix("long") || raw == "farthest" || raw == "furthest" || (raw.hasPrefix("most ") && !raw.hasPrefix("most recent")) || raw.hasPrefix("greatest") || raw == "distance record" { intent.sort = .longest }
            else if raw == "oldest" || raw == "earliest" || raw.hasPrefix("first") { intent.sort = .oldest }
            else { intent.sort = .newest }
        }
        if intent.sort == .fastest { _ = take(Self.paceQualifier) }
        _ = take(Self.recordedKind)
        for match in take(Self.sportType) {
            let word = match[2].lowercased()
            let excluded = !match[1].isEmpty
            let sport: String?
            switch word {
            case "running", "runner", "run", "runs", "ran", "jog", "jogs", "jogging": sport = "running"
            case "cycling", "cycle", "cycles", "bicycle", "bicycles", "biking", "bike", "bikes", "ride", "rides", "rode": sport = "cycling"
            case "hiking", "hike", "hikes", "hiked": sport = "hiking"
            default: sport = nil
            }
            if let sport { intent.append(excluded ? .excludingSport(sport) : .sport(sport)) }
            else {
                let type: String
                if word.hasPrefix("interval") { type = "intervals" }
                else if word.hasPrefix("time") { type = "time" }
                else if word.hasPrefix("distance") { type = "distance" }
                else if word.hasPrefix("coach") { type = "coached" }
                else { type = "free" }
                intent.append(excluded ? .excludingType(type) : .type(type))
                if !excluded, word.hasSuffix("run") || word.hasSuffix("runs") { intent.append(.sport("running")) }
            }
        }
        for match in take(Self.qualifiedCity) { intent.append(.place(match[1])) }
        for match in take(Self.stateName) { intent.append(.place(match[0])) }
        for match in take(Self.stateCode) {
            if !intent.stateCandidates.contains(match[0]) { intent.stateCandidates.append(match[0]) }
        }
        for match in take(Self.unsupported) { intent.append(.unsupported(match[0])) }
        let hasPlace = intent.filters.contains { if case .place = $0 { true } else { false } }
        let hasDistance = intent.sort == .longest || intent.filters.contains { if case .distance = $0 { true } else { false } }
        intent.terms = WorkoutSearchEngine.words(text).filter {
            !Self.ignored.contains($0) && !Self.generic.contains($0) && !(hasPlace && $0 == "there") && !(hasDistance && $0 == "distance")
        }
        return intent
    }

    /// "Portland OR" names Portland, Oregon when the code is in capitals or ends the query.
    private static func cityAndState(_ name: String) -> String {
        let pieces = name.split(separator: " ")
        guard pieces.count >= 2, !name.contains(","), let last = pieces.last, last.count == 2,
              WorkoutSearchLocations.stateNames[last.uppercased()] != nil,
              last == last.uppercased(), pieces.dropLast().allSatisfy({ $0.first?.isUppercase == true }) else { return name }
        return pieces.dropLast().joined(separator: " ") + ", " + last
    }

    private mutating func addCutoff(_ match: [String], span: DateInterval?) {
        guard let span else { intent.append(.unsupported(match[0])); return }
        let interval: DateInterval
        switch match[1].lowercased() {
        case "after": interval = DateInterval(start: span.end, end: .distantFuture)
        case "on or after", "since": interval = DateInterval(start: span.start, end: .distantFuture)
        case "before": interval = DateInterval(start: .distantPast, end: span.start)
        default: interval = DateInterval(start: .distantPast, end: span.end)
        }
        intent.append(.date(interval, match[0]))
    }

    private func namedSpan(month: String, day: String, year: String) -> DateInterval? {
        let names = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        guard let index = names.firstIndex(of: month.prefix(3).lowercased()) else { return nil }
        var parts = DateComponents(year: Int(year) ?? calendar.component(.year, from: now), month: index + 1, day: Int(day) ?? 1)
        // With no year, a month or day means the most recent one that has started: "October" typed in
        // February is last October. A typed year always wins.
        if Int(year) == nil, let start = calendar.date(from: parts), start > now { parts.year! -= 1 }
        guard let date = calendar.date(from: parts),
              calendar.dateComponents([.year, .month, .day], from: date) == parts else { return nil }
        return calendar.dateInterval(of: day.isEmpty ? .month : .day, for: date)
    }

    private func isoDay(_ parts: [String]) -> DateInterval? {
        let components = DateComponents(year: Int(parts[0]), month: Int(parts[1]), day: Int(parts[2]))
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components else { return nil }
        return calendar.dateInterval(of: .day, for: date)
    }

    private mutating func addEffort(_ typed: String) {
        let word = typed.lowercased()
        let meters: Double?
        if word.hasPrefix("half") { meters = 21_097.5 }
        else if word.hasPrefix("marathon") { meters = 42_195 }
        else if word.contains("mi") && !word.contains("m ") && word.range(of: #"\d\s*m(?:et|$)"#, options: .regularExpression) == nil {
            let count = word.hasPrefix("2") || word.hasPrefix("two") ? 2.0 : (word.hasPrefix("10") || word.hasPrefix("ten") ? 10.0 : 1.0)
            meters = WorkoutSearchEfforts.standard(near: count * DistanceUnit.miles.meters)
        } else {
            let digits = word.replacingOccurrences(of: ",", with: "")
            let spelled = ["one": 1.0, "five": 5.0, "ten": 10.0]
            let number = Double(digits.prefix { $0.isNumber }) ?? spelled.first { digits.hasPrefix($0.key) }?.value ?? 0
            let isKilometers = digits.contains("k")
            meters = WorkoutSearchEfforts.standard(near: isKilometers ? number * 1000 : number)
        }
        guard let meters else { return }
        intent.sort = .bestEffort
        intent.effortMeters = meters
    }

    private mutating func addWeather() {
        for match in take(Self.weatherSort) {
            let word = match[1].lowercased()
            if word == "hottest" || word == "warmest" { intent.sort = .hottest }
            else if word == "windiest" { intent.sort = .windiest }
            else if word == "rainiest" || word == "wettest" { intent.append(.sky(.rain, WorkoutSearchSky.rain.label)) }
            else if word == "snowiest" { intent.append(.sky(.snow, WorkoutSearchSky.snow.label)) }
            else { intent.sort = .coldest }
        }
        for match in take(Self.temperatureAmount) {
            // Captures: comparator, number, then the unit after "°", after "degrees" or on its own.
            addTemperature(match[1], match[0], number: match[2], unit: (match[3] + match[4] + match[5]).lowercased())
        }
        for match in take(Self.temperatureBare) { addTemperature(match[1], match[0], number: match[2], unit: "") }
        for match in take(Self.windFirst) + take(Self.windLast) { addWind(match[1], number: match[2], unit: match[3]) }
        for match in take(Self.weatherWord) {
            let word = match[1].lowercased()
            let t = WorkoutSearchWeather.self
            if word.hasPrefix("rain") || word == "wet" || word.hasPrefix("drizzl") || word == "showers" { intent.append(.sky(.rain, "Rain")) }
            else if word.hasPrefix("snow") || word == "sleet" { intent.append(.sky(.snow, "Snow")) }
            else if word.hasPrefix("thunder") || word.hasPrefix("storm") { intent.append(.sky(.storm, "Storms")) }
            else if word.hasPrefix("fog") || word.hasPrefix("mist") || word == "hazy" { intent.append(.sky(.fog, "Fog")) }
            else if word == "cloudy" || word == "overcast" || word.hasSuffix("skies") && word.hasPrefix("gr") { intent.append(.sky(.cloudy, "Cloudy")) }
            else if word.hasPrefix("sun") { intent.append(.sky(.sunny, "Sunny")) }
            else if word.hasPrefix("clear") { intent.append(.sky(.clear, "Clear skies")) }
            else if word.hasPrefix("humid") || word == "muggy" { intent.append(.sky(.humid, "Humid")) }
            else if word == "windy" || word == "gusty" { intent.append(.wind(.atLeast, t.windy, "Windy · \(windText(t.windy))+")) }
            else if word == "breezy" { intent.append(.wind(.atLeast, t.breezy, "Breezy · \(windText(t.breezy))+")) }
            else if word == "freezing" || word == "icy" || word == "frosty" || word == "frigid" {
                intent.append(.temperature(.atMost, t.freezing, "Freezing · \(degrees(t.freezing)) or colder"))
            }
            else if word == "cold" { intent.append(.temperature(.less, t.cold, "Cold · below \(degrees(t.cold))")) }
            else if word == "chilly" { intent.append(.temperature(.less, t.chilly, "Chilly · below \(degrees(t.chilly))")) }
            else if word.hasPrefix("warm") { intent.append(.temperature(.atLeast, t.warm, "Warm · \(degrees(t.warm))+")) }
            else if word == "weather" { intent.append(.sky(.any, WorkoutSearchSky.any.label)) }
            else { intent.append(.temperature(.atLeast, t.hot, "Hot · \(degrees(t.hot))+")) }
        }
    }

    /// "41°F" for miles runners, "5°C" for kilometers.
    private func degrees(_ celsius: Double) -> String {
        feet ? "\(Int((celsius * 9 / 5 + 32).rounded()))°F" : "\(Int(celsius.rounded()))°C"
    }

    private func windText(_ metersPerSecond: Double) -> String {
        feet ? "\(Int((metersPerSecond * 2.236_936).rounded())) mph" : "\(Int((metersPerSecond * 3.6).rounded())) km/h"
    }

    private static func weatherComparison(_ typed: String) -> WorkoutSearchComparison {
        switch typed.lowercased() {
        case "colder than", "cooler than": .less
        case "warmer than", "hotter than": .greater
        case "around", "about", "": .about
        default: comparison(typed)
        }
    }

    private static func comparisonWord(_ op: WorkoutSearchComparison) -> String {
        switch op {
        case .greater: "Above"
        case .atLeast: "At least"
        case .less: "Below"
        case .atMost: "At most"
        case .about: "About"
        case .equal: "Exactly"
        }
    }

    /// A typed temperature. Without °F or °C it follows the distance unit: Fahrenheit with miles.
    private mutating func addTemperature(_ comparator: String, _ typed: String, number: String, unit: String) {
        guard let value = Double(number), abs(value) < 200 else { intent.append(.unsupported(typed)); return }
        let fahrenheit = unit.hasPrefix("f") || (unit.isEmpty && feet)
        let op = Self.weatherComparison(comparator)
        let target = WorkoutSearchTemperature.celsius(value, fahrenheit: fahrenheit)
        intent.append(.temperature(op, target, "\(Self.comparisonWord(op)) \(Int(value))°\(fahrenheit ? "F" : "C")"))
    }

    /// A typed wind speed. Without a unit it follows the distance unit: mph with miles, km/h with kilometers.
    private mutating func addWind(_ comparator: String, number: String, unit: String) {
        guard let value = Double(number) else { return }
        let unit = unit.lowercased().replacingOccurrences(of: " ", with: "")
        let metersPerSecond: Double, shown: String
        if unit == "m/s" { (metersPerSecond, shown) = (value, "m/s") }
        else if unit == "mph" || (unit.isEmpty && feet) { (metersPerSecond, shown) = (value / 2.236_936, "mph") }
        else { (metersPerSecond, shown) = (value / 3.6, "km/h") }
        let op = Self.weatherComparison(comparator)
        let number = value.rounded() == value ? "\(Int(value))" : "\(value)"
        intent.append(.wind(op, metersPerSecond, "Wind \(Self.comparisonWord(op).lowercased()) \(number) \(shown)"))
    }

    private mutating func addTimesOfDay() {
        for match in take(Self.dayPart) {
            let word = match[2].lowercased()
            let window: (Int, Int, String)
            if word.hasPrefix("early") { window = (4 * 60, 7 * 60, "Early morning · 4–7 AM") }
            else if word.hasPrefix("morning") { window = (4 * 60, 12 * 60, "Morning · 4 AM–noon") }
            else if word.hasPrefix("lunch") || word == "midday" || word == "noon" { window = (11 * 60, 14 * 60, "Midday · 11 AM–2 PM") }
            else if word.hasPrefix("afternoon") { window = (12 * 60, 17 * 60, "Afternoon · noon–5 PM") }
            else if word.hasPrefix("evening") { window = (17 * 60, 21 * 60, "Evening · 5–9 PM") }
            else if word.hasPrefix("late") { window = (22 * 60, 4 * 60, "Late night · 10 PM–4 AM") }
            else { window = (20 * 60, 4 * 60, "Night · 8 PM–4 AM") }
            intent.append(.timeOfDay(from: window.0, to: window.1, window.2))
            // "This morning" is today's.
            if !match[1].isEmpty, let today = calendar.dateInterval(of: .day, for: now) { intent.append(.date(today, "Today")) }
        }
        for match in take(Self.clockTime) {
            guard var hour = Int(match[2]), (1...12).contains(hour) else { intent.append(.unsupported(match[0])); continue }
            let minute = Int(match[3]) ?? 0
            if match[4].lowercased() == "p" && hour < 12 { hour += 12 }
            if match[4].lowercased() == "a" && hour == 12 { hour = 0 }
            addClock(match[1], minutes: hour * 60 + minute, typed: match[0])
        }
        for match in take(Self.clockTime24) {
            guard let hour = Int(match[2]), let minute = Int(match[3]), hour < 24, minute < 60 else { intent.append(.unsupported(match[0])); continue }
            addClock(match[1], minutes: hour * 60 + minute, typed: match[0])
        }
    }

    private mutating func addClock(_ comparator: String, minutes: Int, typed: String) {
        let label = "Started " + typed.trimmingCharacters(in: .whitespaces)
        switch comparator.lowercased() {
        case "before", "by", "earlier than": intent.append(.timeOfDay(from: 0, to: minutes, label))
        case "after", "later than": intent.append(.timeOfDay(from: minutes, to: 24 * 60, label))
        default:
            // "At 7 AM" or a bare "7am" is the half hour either side.
            intent.append(.timeOfDay(from: (minutes + 24 * 60 - 30) % (24 * 60), to: (minutes + 30) % (24 * 60), "Started around " + typed.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: #"^(?i:at|around|about)\s+"#, with: "", options: .regularExpression)))
        }
    }

    private static func weekdayIndex(_ name: String) -> Int? {
        let name = name.lowercased()
        return WorkoutSearchClock.weekdayNames.firstIndex { name.hasPrefix($0) }.map { $0 + 1 }
    }

    private mutating func addWeekdays() {
        // "Last Saturday" is one day; a bare "Saturday" is every Saturday.
        for match in take(Self.pastWeekday) {
            guard let day = Self.weekdayIndex(match[2]) else { continue }
            let allowsToday = match[1].lowercased() == "this"
            let today = calendar.startOfDay(for: now)
            var date = today
            for back in (allowsToday ? 0 : 1)...7 {
                guard let candidate = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
                if calendar.component(.weekday, from: candidate) == day { date = candidate; break }
            }
            if let span = calendar.dateInterval(of: .day, for: date) { intent.append(.date(span, match[0])) }
        }
        for match in take(Self.weekPart) {
            let word = match[2].lowercased()
            let weekend = word.hasPrefix("weekend")
            if !match[1].isEmpty, weekend {
                // The most recent Saturday and Sunday: "this weekend" can be the one going on now.
                let today = calendar.startOfDay(for: now)
                let weekday = calendar.component(.weekday, from: today)
                let sinceSaturday = (weekday + 7 - 7) % 7
                guard var saturday = calendar.date(byAdding: .day, value: -sinceSaturday, to: today) else { continue }
                let current = weekday == 7 || weekday == 1
                if current && match[1].lowercased() != "this", let earlier = calendar.date(byAdding: .day, value: -7, to: saturday) { saturday = earlier }
                if let monday = calendar.date(byAdding: .day, value: 2, to: saturday) {
                    intent.append(.date(DateInterval(start: saturday, end: monday), match[0]))
                }
                continue
            }
            intent.append(weekend ? .weekday([1, 7], "Weekends") : .weekday([2, 3, 4, 5, 6], "Weekdays"))
        }
        var days = Set<Int>()
        var names: [String] = []
        for match in take(Self.anyWeekday) {
            guard let day = Self.weekdayIndex(match[1]), !days.contains(day) else { continue }
            days.insert(day)
            names.append(WorkoutSearchClock.weekdayNames[day - 1].capitalized + "s")
        }
        if !days.isEmpty { intent.append(.weekday(days, names.joined(separator: ", "))) }
    }

    private mutating func addMention(_ match: [String]) {
        let generic = match[0].lowercased().hasPrefix("mention")
        addTextFilter([match[0], generic ? "either" : "notes", match[1]])
    }

    private mutating func addTextFilter(_ pieces: [String]) {
        let word = pieces[1].lowercased()
        var content = pieces[2].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        // "title matches for lake" asks for lake.
        for lead in ["matches for ", "match for ", "matching ", "for "] where content.lowercased().hasPrefix(lead) {
            content.removeFirst(lead.count)
            break
        }
        if word == "mentioned", content.lowercased().hasPrefix("my "), !pieces[0].contains("“"), !pieces[0].contains("\"") {
            content.removeFirst(3)
        }
        guard !content.isEmpty else { return }
        if word == "either" { intent.append(.titleOrNotes(content)); return }
        intent.append(word.hasPrefix("note") || word == "mentioned" ? .notes(content) : .title(content))
    }

    /// Request words and names for a workout or the history itself. They say what to search, not what to find.
    private static let generic: Set<String> = [
        "so", "far", "as", "or", "to", "up", "recorded", "logged", "include", "includes", "including", "involving",
        "pull", "look", "search", "retrieve", "locate", "matches", "match", "matching", "training", "trainings",
        "log", "efforts", "effort", "practice", "known", "runs", "run", "miles", "mile", "km", "kilometers", "history",
        "referencing", "mentioning", "holds", "hold", "held", "came", "come", "containing", "contain", "contains", "there", "are", "recent", "most", "entries", "entry"
    ]

    private static let ignored: Set<String> = [
        "a", "an", "the", "my", "me", "show", "find", "get", "give", "list", "all", "any", "what",
        "was", "were", "is", "i", "did", "do", "which", "who", "that", "where", "when", "whose",
        "it", "they", "their", "with", "of", "at", "near", "in", "from", "on", "during", "workout",
        "workouts", "outing", "outings", "activity", "activities", "session", "sessions", "and", "but", "for", "please", "took", "lasted", "lasting",
        "has", "taking", "than", "by", "through", "via", "like", "started", "starting", "starts", "start", "covered", "covering", "among", "first", "ordered", "sorted", "sort", "i've", "had", "have", "only"
    ]

    private static func isDurationUnit(_ unit: String) -> Bool {
        let unit = unit.lowercased()
        return unit.hasPrefix("h") || unit.hasPrefix("min") || unit.hasPrefix("sec")
    }

    private mutating func addQuantity(_ match: [String]) {
        let spelled = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
                       "seven": 7, "eight": 8, "nine": 9, "ten": 10, "twenty": 20, "thirty": 30,
                       "forty": 40, "fifty": 50, "sixty": 60, "ninety": 90]
        guard let value = Double(match[2]) ?? spelled[match[2].lowercased()].map(Double.init), value.isFinite else {
            intent.append(.unsupported(match[0]))
            return
        }
        let prefix = match[1].lowercased()
        let comparator = prefix.isEmpty || prefix == "at" ? match[4] : prefix
        let op = Self.comparison(comparator)
        let label = op == .about ? "About " + match[0].trimmingCharacters(in: .whitespaces) : match[0]
        let unit = match[3].lowercased()
        if unit == "k" || unit == "km" || unit.hasPrefix("kilo") {
            intent.append(.distance(op, value * 1000, label))
        } else if unit == "mi" || unit.hasPrefix("mile") {
            intent.append(.distance(op, value * DistanceUnit.miles.meters, label))
        } else if unit.hasPrefix("met") {
            intent.append(.distance(op, value, label))
        } else {
            let multiplier: Double = unit.hasPrefix("h") ? 3600 : (unit.hasPrefix("min") ? 60 : 1)
            intent.append(.duration(op, value * multiplier, label))
        }
    }

    /// No comparison word means about that much; "exactly" and "precisely" keep the exact amount.
    private static func comparison(_ comparator: String) -> WorkoutSearchComparison {
        let op: WorkoutSearchComparison
        switch comparator.lowercased() {
        case "exceed", "exceeds", "exceeded", "exceeding", "more than", "past", "beyond", "greater than", "longer than", "above", "over", ">": op = .greater
        case "minimum", "minimum of", "a minimum of", "or greater", "or higher", "or above", "or further", "or farther", "at least", "no fewer than", "not less than", "at or above", "no less than", "no shorter than", "or more", "or longer", "and above", ">=", "≥": op = .atLeast
        case "did not reach", "does not reach", "do not reach", "didn't reach", "didn’t reach", "less than", "fewer than", "shorter than", "under", "below", "<": op = .less
        case "maximum", "maximum of", "a maximum of", "did not exceed", "does not exceed", "do not exceed", "not exceeding", "at most", "no greater than", "not more than", "at or below", "no more than", "no longer than", "up to", "up to and including", "or less", "or fewer", "or shorter", "and below", "<=", "≤": op = .atMost
        case "higher than": op = .greater
        case "lower than": op = .less
        case "": op = .about
        default: op = .equal
        }
        return op
    }

    private mutating func addPace(_ match: [String]) {
        let parts = match[2].split(separator: ":")
        guard let minutes = Double(parts[0]) else { intent.append(.unsupported(match[0])); return }
        let seconds = minutes * 60 + (parts.count > 1 ? Double(parts[1]) ?? 0 : 0)
        guard seconds > 0 else { intent.append(.unsupported(match[0])); return }
        let perMile = match[3].lowercased().hasPrefix("mi")
        let op: WorkoutSearchComparison
        switch match[1].lowercased() {
        case "under", "below", "faster than", "quicker than", "less than", "sub", "better than": op = .less
        case "no slower than", "at most": op = .atMost
        case "over", "above", "slower than", "more than": op = .greater
        case "no faster than", "at least": op = .atLeast
        default: op = .about
        }
        let label = (op == .about ? "About " : "") + match[0].trimmingCharacters(in: .whitespaces)
        intent.append(.pace(op, perMile ? seconds / DistanceUnit.miles.meters * 1000 : seconds, label))
    }

    private mutating func addMetric(label: String, word: String, comparator: String, number: String, unit: String) {
        guard let value = Double(number), value.isFinite else {
            intent.append(.unsupported(label))
            return
        }
        let op = Self.comparison(comparator)
        let word = word.lowercased(), unit = unit.lowercased()
        let text = (op == .about ? "About " : "") + label.trimmingCharacters(in: .whitespaces)
        if word.contains("heart") || word.hasSuffix("hr") || word == "bpm" || unit == "bpm" {
            intent.append(.heartRate(op, value, text))
        } else if word.hasPrefix("calor") || word == "kcal" || unit.hasPrefix("cal") || unit == "kcal" {
            intent.append(.calories(op, value, text))
        } else {
            let feet = unit.hasPrefix("f") || (unit.isEmpty && self.feet)
            intent.append(.climb(op, feet ? value * 0.3048 : value, text))
        }
    }
}
