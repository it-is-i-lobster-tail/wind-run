import Foundation

struct WorkoutSearchPlace: Hashable, Codable {
    var address: String
    var city: String
    var state: String
    var country: String

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

    var pace: Double? {
        guard distance >= 10, duration > 0 else { return nil }
        return duration / (distance / 1000)
    }
}

extension WorkoutSearchRecord {
    /// Works out the route facts on the spot. Screens pass the stored facts from `WorkoutSearchIndex` instead.
    init(run: Run, place: WorkoutSearchPlace?) {
        self.init(run: run, facts: WorkoutSearchFacts(run: run))
        self.place = place
    }

    init(run: Run, facts: WorkoutSearchFacts?) {
        self.init(id: run.runIDValue, date: run.startDate, sport: run.sport.rawValue,
                  type: ProgressGroup(run)?.type.rawValue ?? run.kind.rawValue,
                  title: [run.intervalPlan?.name, run.coachWorkout?.title].compactMap { $0 }.joined(separator: " "),
                  notes: run.notesValue, distance: run.distanceMeters, duration: run.activeDuration(),
                  place: facts?.place, isCoached: run.kind == .coached, terrain: facts?.terrain,
                  climb: facts?.climb, heartRate: facts?.heartRate, calories: facts?.calories)
    }
}

enum WorkoutSearchSort: String, Codable {
    case newest, oldest, longest, fastest, mostClimb

    var label: String {
        switch self {
        case .newest: "Newest first"
        case .oldest: "Oldest first"
        case .longest: "Longest distance"
        case .fastest: "Fastest average pace"
        case .mostClimb: "Most climb"
        }
    }

    /// Superlatives rank every workout, so screens show the top few first.
    var ranks: Bool { self == .longest || self == .fastest || self == .mostClimb }
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
    case distance(WorkoutSearchComparison, Double, String), duration(WorkoutSearchComparison, Double, String)
    case terrain(WorkoutSearchTerrain)
    /// Mean heart rate in beats per minute, climb in meters and active calories.
    case heartRate(WorkoutSearchComparison, Double, String), climb(WorkoutSearchComparison, Double, String)
    case calories(WorkoutSearchComparison, Double, String)
    case unsupported(String)

    var label: String {
        switch self {
        case .sport(let x), .type(let x): x.capitalized
        case .excludingSport(let x), .excludingType(let x): "Exclude " + x
        case .place(let x): x
        case .title(let x): "Title contains “" + x + "”"
        case .titleOrNotes(let x): "Title or notes contain “" + x + "”"
        case .notes(let x): "Notes mention “" + x + "”"
        case .date(_, let x), .duration(_, _, let x), .distance(_, _, let x): x
        case .heartRate(_, _, let x), .climb(_, _, let x), .calories(_, _, let x): x
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
        case .distance(let op, let x, _): record.distance > 0 && op.matches(record.distance, target: x)
        case .duration(let op, let x, _): record.duration > 0 && op.matches(record.duration, target: x)
        case .terrain(let terrain): record.terrain.map { terrain == .hills ? !$0.isEmpty : $0.contains(terrain) } == true
        // Compare whole beats, as rows show them, so "over 150" never lists a 150 bpm average.
        case .heartRate(let op, let x, _): record.heartRate.map { $0 > 0 && op.matches($0.rounded(), target: x) } == true
        case .climb(let op, let x, _): record.climb.map { op.matches($0, target: x) } == true
        case .calories(let op, let x, _): record.calories.map { $0 > 0 && op.matches($0, target: x) } == true
        case .unsupported: false
        }
    }
}

struct WorkoutSearchIntent: Hashable, Codable {
    var filters: [WorkoutSearchFilter] = []
    var terms: [String] = []
    var sort: WorkoutSearchSort = .newest

    mutating func append(_ filter: WorkoutSearchFilter) {
        if !filters.contains(filter) { filters.append(filter) }
    }
}

struct WorkoutSearchResult {
    var ids: [UUID]
    var placeChoices: [String]
    var appliedIntent: WorkoutSearchIntent
}

enum WorkoutSearchEngine {
    static func words(_ string: String) -> [String] {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
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
        // An unqualified saved city is a location. Resolve after places arrive so this also
        // works for saved history and never has to send place names to the interpreter.
        if !intent.terms.isEmpty, let city = records.compactMap(\.place).map(\.city).first(where: {
            !$0.isEmpty && words($0) == intent.terms
        }) {
            intent.append(.place(city))
            intent.terms = []
        }
        for case let .place(name) in intent.filters {
            let cityMatches = records.compactMap(\.place).filter { words($0.city) == words(name) }
            let choices = Set(cityMatches.map(\.cityAndState))
            if choices.count > 1 { return WorkoutSearchResult(ids: [], placeChoices: choices.sorted(), appliedIntent: intent) }
        }
        let matches = records.filter { record in
            guard intent.filters.allSatisfy({ $0.matches(record) }) else { return false }
            if intent.sort == .fastest && record.pace == nil { return false }
            if intent.sort == .longest && record.distance <= 0 { return false }
            if intent.sort == .mostClimb && (record.climb ?? 0) <= 0 { return false }
            if intent.terms.isEmpty { return true }
            let text = [record.sport, record.type, record.title, record.notes, record.place?.searchableText ?? ""]
                .joined(separator: " ")
            return contains(intent.terms.joined(separator: " "), in: text)
        }
        let ordered = matches.sorted { lhs, rhs in
            switch intent.sort {
            case .fastest where lhs.pace != rhs.pace: return (lhs.pace ?? .infinity) < (rhs.pace ?? .infinity)
            case .longest where lhs.distance != rhs.distance: return lhs.distance > rhs.distance
            case .mostClimb where lhs.climb != rhs.climb: return (lhs.climb ?? 0) > (rhs.climb ?? 0)
            case .oldest where lhs.date != rhs.date: return lhs.date < rhs.date
            default:
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        }
        return WorkoutSearchResult(ids: ordered.map(\.id), placeChoices: [], appliedIntent: intent)
    }

    // Consume recognized clauses before treating the remaining words as literal text. Separators
    // keep a location such as "in Portland last month under 1 hour" from swallowing other filters.
    static func parse(_ query: String, now: Date = .now, calendar: Calendar = .current,
                      climbInFeet: Bool = climbInFeet) -> WorkoutSearchIntent {
        var parser = SearchParser(text: query, now: now, calendar: calendar, feet: climbInFeet)
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
    private static let sorting = regex(#"\b(?:(?:(?:went|came|occurred|happened|finished)(?: the)?|had (?:my|the))\s+)?(fastest(?:\s+(?:average\s+)?pace)?|best (?:average |avg )?pace|fast(?:er)?(?:\s+pace)?|quick(?:est)?|speediest|long(?:est|er)?(?:\s+distance)?|farthest|furthest|most (?:distance|ground)|oldest|earliest|first(?: ever)?(?: record(?:ed)?)?(?=\s+(?:a\s+|an\s+|the\s+)?(?:workout|session|outing|run|ride|hike|interval|coached|free|bike))|newest|most recent(?:ly)?|latest)\b"#)
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
        #"(?:\s+(or (?:more|less|longer|shorter|fewer)|and (?:above|below)|minimum|maximum))?"# +
        #"(?:\s+(?:of\s+)?(?:(?:active|moving)(?:\s+time)?|activity)\b)?"#
    )
    private static let isoComponents = #"(\d{4})-(\d{2})-(\d{2})\b"#
    private static let dateISO = regex(#"\b"# + isoComponents)
    private static let cutoffPrefix = #"\b(?:(?:available|recorded|logged|completed)\s+)?(on or before|on or after|(?:before|by) the end of|no later than|as of|as at|up to|through|by|before|after|since)\s+"#
    private static let cutoffISO = regex(cutoffPrefix + isoComponents)
    private static let dateRangeISO = regex(#"\b(?:from|between)\s+"# + isoComponents + #"\s+(?:to|through|and)\s+"# + isoComponents)
    private static let cutoffWeek = regex(cutoffPrefix + #"(?:(?:the )?end of )?week\s+(\d{1,2})\b"#)
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
    private static let terrain = regex(#"\b(?:(?:steep|sustained)\s+)?(hills?|hilly|grades?|uphills?|inclines?|downhills?|declines?)\b"#)
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
    private static let metricUnitOnly = regex(#"(?<![\p{L}\d.])(?:"# + metricComparator + #"\s*)?(\d+(?:\.\d+)?)\s*(bpm|kcal|calories|cal)\b"#)
    private static let mostClimb = regex(#"\b(?:(?:the\s+)?(?:most|highest|biggest|greatest|largest)\s+)?(?:hilliest|climb(?:s|ing|ed)?|elevation(?:\s+gain)?|ascent|vert(?:ical)?(?:\s+gain)?)\b"#)
    private static let hasHeartRate = regex(#"\b(?:(?:the\s+)?(?:highest|lowest|most)\s+)?(?:(?:average|avg|mean)\s+)?(?:heart\s*rate|bpm)\b"#)
    private static let hasCalories = regex(#"\b(?:(?:the\s+)?(?:most|highest)\s+)?(?:calories|kcal)\b"#)
    // Race names stand for their distance, give or take what the course and GPS add.
    private static let raceDistance = regex(#"\b(half[\s-]?marathons?|marathons?)\b"#)
    private static let unsupported = regex(#"\b(?:cadence|weather|temperature|elapsed(?:\s+time)?|rainy|snowy|hardest|easiest|felt|ignore\s+(?:all|previous|prior)|system\s+prompt)\b"#)

    mutating func parse() -> WorkoutSearchIntent {
        let standalone = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if standalone == "IN" || standalone == "OR" || standalone == "ME" {
            intent.append(.place(standalone))
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
        for match in take(Self.dateRangeISO) {
            if let lower = isoDay(Array(match[1...3])), let upper = isoDay(Array(match[4...6])), lower.start < upper.end {
                intent.append(.date(DateInterval(start: lower.start, end: upper.end), match[0]))
            } else { intent.append(.unsupported(match[0])) }
        }
        for match in take(Self.cutoffISO) { addCutoff(match, span: isoDay(Array(match.dropFirst(2)))) }
        for match in take(Self.cutoffNamed) { addCutoff(match, span: namedSpan(month: match[2], day: match[3], year: match[4])) }
        for match in take(Self.cutoffWeek) {
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
            if !name.isEmpty { intent.append(.place(name)) }
        }
        for match in take(Self.terrain) {
            let word = match[1].lowercased()
            if word.hasPrefix("uphill") || word.hasPrefix("incline") { intent.append(.terrain(.uphill)) }
            else if word.hasPrefix("downhill") || word.hasPrefix("decline") { intent.append(.terrain(.downhill)) }
            else { intent.append(.terrain(.hills)) }
        }
        for match in take(Self.sorting) {
            let raw = match[1].lowercased()
            if raw.hasPrefix("fast") || raw.hasPrefix("quick") || raw.hasPrefix("best ") || raw == "speediest" { intent.sort = .fastest }
            else if raw.hasPrefix("long") || raw == "farthest" || raw == "furthest" || raw == "most distance" || raw == "most ground" { intent.sort = .longest }
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
        for match in take(Self.stateCode) { intent.append(.place(match[0])) }
        for match in take(Self.unsupported) { intent.append(.unsupported(match[0])) }
        let hasPlace = intent.filters.contains { if case .place = $0 { true } else { false } }
        intent.terms = WorkoutSearchEngine.words(text).filter { !Self.ignored.contains($0) && !(hasPlace && $0 == "there") }
        return intent
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
        let parts = DateComponents(year: Int(year) ?? calendar.component(.year, from: now), month: index + 1, day: Int(day) ?? 1)
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

    private mutating func addMention(_ match: [String]) {
        let generic = match[0].lowercased().hasPrefix("mention")
        addTextFilter([match[0], generic ? "either" : "notes", match[1]])
    }

    private mutating func addTextFilter(_ pieces: [String]) {
        let word = pieces[1].lowercased()
        var content = pieces[2].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if word == "mentioned", content.lowercased().hasPrefix("my "), !pieces[0].contains("“"), !pieces[0].contains("\"") {
            content.removeFirst(3)
        }
        guard !content.isEmpty else { return }
        if word == "either" { intent.append(.titleOrNotes(content)); return }
        intent.append(word.hasPrefix("note") || word == "mentioned" ? .notes(content) : .title(content))
    }

    private static let ignored: Set<String> = [
        "a", "an", "the", "my", "me", "show", "find", "get", "give", "list", "all", "any", "what",
        "was", "were", "is", "i", "did", "do", "which", "who", "that", "where", "when", "whose",
        "it", "they", "their", "with", "of", "at", "near", "in", "from", "on", "during", "workout",
        "workouts", "outing", "outings", "activity", "activities", "session", "sessions", "and", "but", "for", "please", "took", "lasted", "lasting",
        "has", "taking", "than", "by", "started", "starting", "starts", "start", "covered", "covering", "among", "first", "ordered", "sorted", "sort", "i've", "had", "have", "only"
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
        case "minimum", "minimum of", "a minimum of", "at least", "no fewer than", "not less than", "at or above", "no less than", "no shorter than", "or more", "or longer", "and above", ">=", "≥": op = .atLeast
        case "did not reach", "does not reach", "do not reach", "didn't reach", "didn’t reach", "less than", "fewer than", "shorter than", "under", "below", "<": op = .less
        case "maximum", "maximum of", "a maximum of", "did not exceed", "does not exceed", "do not exceed", "not exceeding", "at most", "no greater than", "not more than", "at or below", "no more than", "no longer than", "up to", "up to and including", "or less", "or fewer", "or shorter", "and below", "<=", "≤": op = .atMost
        case "higher than": op = .greater
        case "lower than": op = .less
        case "": op = .about
        default: op = .equal
        }
        return op
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
