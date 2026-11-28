import Foundation

/// Place names from the runner's own history, read before any other search word, so "Nob Hill" is a place
/// and not a hills search, and "Saint Louis" finds runs tagged "St. Louis".
enum WorkoutSearchPlaceNames {
    /// Short forms that place names use, each read as the long form.
    private static let shortForms = ["st": "saint", "ste": "sainte", "mt": "mount", "mtn": "mountain",
                                     "ft": "fort", "pt": "point", "pk": "park"]

    /// A place's words, with short forms such as "St." and "Mt" spelled out, so both spellings compare equal.
    static func words(_ name: String) -> [String] {
        WorkoutSearchEngine.words(name).map { shortForms[$0] ?? $0 }
    }

    /// Nicknames for cities, each used only when the runner has run in that city.
    static let nicknames: [String: String] = [
        "sf": "San Francisco, CA", "san fran": "San Francisco, CA", "frisco": "San Francisco, CA",
        "nyc": "New York, NY", "new york city": "New York, NY", "pdx": "Portland, OR",
        "philly": "Philadelphia, PA", "vegas": "Las Vegas, NV", "nola": "New Orleans, LA",
        "atl": "Atlanta, GA", "slc": "Salt Lake City, UT", "okc": "Oklahoma City, OK",
        "abq": "Albuquerque, NM", "bmore": "Baltimore, MD", "chi town": "Chicago, IL", "chitown": "Chicago, IL",
        "nash": "Nashville, TN", "jax": "Jacksonville, FL", "l a": "Los Angeles, CA"
    ]

    /// Words a search reads on its own. A known place made only of these, such as a park called "Long Run",
    /// stays a search, since that's what the words almost always mean.
    private static let searchWords: Set<String> = [
        "long", "run", "runs", "fast", "easy", "hill", "hills", "flat", "morning", "evening", "night", "lunch",
        "half", "marathon", "mile", "miles", "race", "track", "trail", "trails", "last", "week", "weekend"
    ]

    /// The names search can read as places: every city a workout started in and every place a route went
    /// through, as "City, ST" for US cities. Kept per history.
    static func known(in records: [WorkoutSearchRecord]) -> [String] {
        var hasher = Hasher()
        for record in records { hasher.combine(record.place) }
        let signature = hasher.finalize()
        if let kept = cache, kept.signature == signature { return kept.names }
        var names = Set<String>()
        for place in records.compactMap(\.place) {
            if !place.city.isEmpty {
                names.insert(place.city)
                if place.country.uppercased() == "US", !place.state.isEmpty { names.insert(place.city + ", " + place.state.uppercased()) }
            }
            for passed in place.passed ?? [] where !passed.isEmpty { names.insert(passed) }
        }
        let sorted = names.sorted()
        cache = (signature, sorted)
        return sorted
    }

    private static var cache: (signature: Int, names: [String])?

    /// A typed phrase read as a known place.
    struct Found {
        /// Where it was typed, in the query's UTF-16 offsets.
        var range: NSRange
        var name: String
        /// What was typed, when it differs from the name, such as "Saint Louis" for "St. Louis".
        var typed: String?
    }

    /// Known places typed in the query, longest first, with no two overlapping. Only names of two words or
    /// more and nicknames are read here; a one-word city is read later from the words left over.
    static func find(in text: String, known: [String]) -> [Found] {
        guard !known.isEmpty else { return [] }
        let tokens = tokenized(text)
        guard !tokens.isEmpty else { return [] }
        let knownCities = Set(known.map { words($0) })
        var candidates: [(words: [String], name: String)] = []
        for name in known {
            let parts = words(name.components(separatedBy: ",")[0])
            // "Portland, OR" and "Portland" both read as Portland: the shorter name covers it.
            guard parts.count >= 2, !name.contains(","), !Set(parts).isSubset(of: searchWords) else { continue }
            candidates.append((parts, name))
        }
        for (nickname, city) in nicknames where knownCities.contains(words(city)) {
            candidates.append((words(nickname), city))
        }
        candidates.sort { $0.words.count > $1.words.count }
        var taken = [Bool](repeating: false, count: tokens.count)
        var found: [Found] = []
        for candidate in candidates {
            let length = candidate.words.count
            guard length <= tokens.count else { continue }
            for start in 0...(tokens.count - length) where !taken[start..<(start + length)].contains(true) {
                guard tokens[start..<(start + length)].map(\.word) == candidate.words else { continue }
                // "LA" is Louisiana unless it reads as a nickname: in capitals with Los Angeles in the history.
                let first = tokens[start], last = tokens[start + length - 1]
                let range = NSRange(location: first.range.location, length: NSMaxRange(last.range) - first.range.location)
                let typed = (text as NSString).substring(with: range)
                if candidate.words == ["l", "a"], typed != "L.A." && typed != "L A" { continue }
                for index in start..<(start + length) { taken[index] = true }
                let plain = WorkoutSearchEngine.words(typed) == WorkoutSearchEngine.words(candidate.name.components(separatedBy: ",")[0])
                found.append(Found(range: range, name: candidate.name, typed: plain ? nil : typed))
            }
        }
        return found.sorted { $0.range.location < $1.range.location }
    }

    /// The query's words with where each was typed, short forms spelled out.
    private static func tokenized(_ text: String) -> [(word: String, range: NSRange)] {
        let pattern = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#)
        let string = text as NSString
        return pattern.matches(in: text, range: NSRange(location: 0, length: string.length)).compactMap { match in
            let raw = WorkoutSearchEngine.words(string.substring(with: match.range)).first ?? ""
            return raw.isEmpty ? nil : (shortForms[raw] ?? raw, match.range)
        }
    }
}

/// When in the day and week a workout started, in the time zone it started in.
enum WorkoutSearchClock {
    private static var calendars: [String: Calendar] = [:]

    private static func calendar(_ zone: TimeZone?) -> Calendar {
        let zone = zone ?? .current
        if let kept = calendars[zone.identifier] { return kept }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendars[zone.identifier] = calendar
        return calendar
    }

    /// Minutes after local midnight.
    static func minute(of record: WorkoutSearchRecord) -> Int {
        let parts = calendar(record.timeZone).dateComponents([.hour, .minute], from: record.date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// 1 for Sunday through 7 for Saturday, as `Calendar` counts them.
    static func weekday(of record: WorkoutSearchRecord) -> Int {
        calendar(record.timeZone).component(.weekday, from: record.date)
    }

    /// True when a start minute falls inside the window, which can run past midnight, such as 20:00 to 4:00.
    static func contains(_ minute: Int, from start: Int, to end: Int) -> Bool {
        start <= end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    }

    static let weekdayNames = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
}

/// The fastest stretch of a standard distance inside each workout, such as the best 5 km of a 10 km run.
nonisolated enum WorkoutSearchEfforts {
    /// The distances search keeps a best time for, in meters.
    static let distances: [Double] = [400, 800, 1_000, 1_609.344, 3_218.688, 5_000, 10_000, 15_000,
                                      16_093.44, 21_097.5, 42_195]

    /// The stored key for a distance: whole meters.
    static func key(_ meters: Double) -> Int { Int(meters.rounded()) }

    /// The best time for each standard distance the workout covered, from running time and distance at each fix,
    /// leaving out pauses. A stretch never reads across a pause, and the run's own distance scales the track,
    /// so a 5 km run's best 5 km is its whole time.
    static func best(times: [TimeInterval], meters: [Double], stretches: [Int], totalMeters: Double) -> [Int: Double] {
        guard times.count == meters.count, meters.count == stretches.count, meters.count > 1,
              let last = meters.last, last > 0, totalMeters > 0 else { return [:] }
        let scale = totalMeters / last
        let distance = meters.map { $0 * scale }
        // The runs of fixes between pauses. Nothing reads across a pause.
        var pieces: [Range<Int>] = []
        var from = 0
        for index in 1...distance.count where index == distance.count || stretches[index] != stretches[from] {
            if index - from > 1 { pieces.append(from..<index) }
            from = index
        }
        var result: [Int: Double] = [:]
        // At the distance or over it, never under: a 4.99 km run has no 5K. The hundredth of a meter only absorbs
        // rounding from scaling the track.
        for target in distances where target <= totalMeters + 0.01 {
            var best = Double.infinity
            for piece in pieces where distance[piece.upperBound - 1] - distance[piece.lowerBound] >= target - 0.01 {
                var low = piece.lowerBound
                for high in (piece.lowerBound + 1)..<piece.upperBound {
                    guard distance[high] - distance[low] >= target - 0.01 else { continue }
                    while low + 1 < high, distance[high] - distance[low + 1] >= target { low += 1 }
                    // Start part way between two fixes, so the stretch is the distance exactly.
                    let over = max(0, distance[high] - distance[low] - target)
                    let gap = distance[low + 1] - distance[low]
                    let share = gap > 0 ? min(1, over / gap) : 0
                    let startTime = times[low] + (times[low + 1] - times[low]) * share
                    best = min(best, times[high] - startTime)
                }
            }
            // Faster than any runner means a GPS jump, not a best.
            if best.isFinite, best > 0, target / best < 12.5 { result[key(target)] = best }
        }
        return result
    }

    /// A short name for a distance, such as "5K" or "Mile".
    static func name(_ meters: Double) -> String {
        switch key(meters) {
        case 400: "400 m"
        case 800: "800 m"
        case 1_000: "1K"
        case 1_609: "Mile"
        case 3_219: "2 miles"
        case 5_000: "5K"
        case 10_000: "10K"
        case 15_000: "15K"
        case 16_093: "10 miles"
        case 21_098: "Half marathon"
        case 42_195: "Marathon"
        default: "\(Int(meters)) m"
        }
    }

    /// The standard distance nearest to a typed one, when it's within 2%.
    static func standard(near meters: Double) -> Double? {
        distances.first { abs($0 - meters) <= $0 * 0.02 }
    }
}

/// How hard a workout was next to the runner's own others of the same sport: heart rate and pace, each
/// compared with their usual spread. Needs at least three workouts with a value before it counts it.
enum WorkoutSearchIntensity {
    /// Kept while the history's sports, heart rates and paces stay the same, so ranking by effort on each
    /// keystroke doesn't work every runner's spread out again.
    private static var kept: (signature: Int, scores: [UUID: Double])?

    static func scores(_ records: [WorkoutSearchRecord]) -> [UUID: Double] {
        var hasher = Hasher()
        for record in records {
            hasher.combine(record.id)
            hasher.combine(record.sport)
            hasher.combine(record.heartRate)
            hasher.combine(record.pace)
        }
        let signature = hasher.finalize()
        if let kept, kept.signature == signature { return kept.scores }
        let scores = workedOut(records)
        kept = (signature, scores)
        return scores
    }

    private static func workedOut(_ records: [WorkoutSearchRecord]) -> [UUID: Double] {
        var result: [UUID: Double] = [:]
        for sport in Set(records.map(\.sport)) {
            let group = records.filter { $0.sport == sport }
            let heart = standardized(group.compactMap { record in record.heartRate.flatMap { $0 > 0 ? (record.id, $0) : nil } })
            // Faster is harder, so pace counts against its sign.
            let pace = standardized(group.compactMap { record in record.pace.map { (record.id, -$0) } })
            for record in group {
                let parts = [heart[record.id], pace[record.id]].compactMap { $0 }
                if !parts.isEmpty { result[record.id] = parts.reduce(0, +) / Double(parts.count) }
            }
        }
        return result
    }

    private static func standardized(_ values: [(UUID, Double)]) -> [UUID: Double] {
        guard values.count >= 3 else { return [:] }
        let mean = values.reduce(0) { $0 + $1.1 } / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1.1 - mean) * ($1.1 - mean) } / Double(values.count)
        let spread = variance.squareRoot()
        guard spread > 0 else { return [:] }
        return Dictionary(values.map { ($0.0, ($0.1 - mean) / spread) }, uniquingKeysWith: { first, _ in first })
    }
}

/// Which workouts went the same way: the squares of about 150 m a route passed through, compared by how
/// many they share. Worked out on this iPhone from routes already on it.
nonisolated enum WorkoutSearchSimilarity {
    /// About 150 m north to south.
    private static let latitudeStep = 0.00135

    /// The squares a route went through, as sorted numbers.
    static func cells(latitudes: [Double], longitudes: [Double]) -> [Int64] {
        guard latitudes.count == longitudes.count, !latitudes.isEmpty else { return [] }
        var cells = Set<Int64>()
        // One square width for every route in the same 5° band of latitude, so two runs on the same streets
        // always land in the same squares.
        let band = Int64((abs(latitudes.first ?? 0) / 5).rounded(.down))
        let middle = (Double(band) * 5 + 2.5) * .pi / 180
        let longitudeStep = latitudeStep / max(0.2, cos(middle))
        for (latitude, longitude) in zip(latitudes, longitudes) {
            let row = Int64((latitude / latitudeStep).rounded(.down))
            let column = Int64((longitude / longitudeStep).rounded(.down))
            // Band, row and column packed into one number: 6 bits, 28 bits and 30 bits.
            cells.insert((band & 0x3F) << 58 | (row & 0xFFF_FFFF) << 30 | (column & 0x3FFF_FFFF))
        }
        return cells.sorted()
    }

    /// The share of squares two routes have in common, from 0 to 1.
    static func overlap(_ a: [Int64], _ b: [Int64]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var i = 0, j = 0, shared = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] { shared += 1; i += 1; j += 1 }
            else if a[i] < b[j] { i += 1 } else { j += 1 }
        }
        return Double(shared) / Double(a.count + b.count - shared)
    }

    /// At or over this, a workout is a best match for "like this one".
    static let alike = 0.7
}

extension WorkoutSearchSimilarity {
    /// How alike two workouts are, from 0 to 1: mostly the route, then the distance.
    static func score(_ record: WorkoutSearchRecord, like target: WorkoutSearchRecord) -> Double {
        guard record.sport == target.sport, let cells = record.cells, let wanted = target.cells else { return 0 }
        let route = overlap(cells, wanted)
        guard route > 0, target.distance > 0, record.distance > 0 else { return 0 }
        let ratio = min(record.distance, target.distance) / max(record.distance, target.distance)
        return route * 0.7 + ratio * 0.3
    }
}
