import Foundation

// Replays search queries straight against the search engine source, with no simulator.
// Route profiles become the terrain and climb facts the app's index would store for them.
struct Corpus: Decodable {
    struct History: Decodable { let id: String; let workouts: [Workout] }
    struct Workout: Decodable {
        let id: UUID
        let sport, kind, workoutType: String
        let startedAt: Date
        let distanceMeters, activeSeconds: Double
        let title, notes: String
        let city, stateCode, countryCode: String?
        let profile: String?
    }
    struct Query: Decodable { let asOf: Date?; let id, historyID, text: String }
    let now: Date
    let timeZone, locale: String
    let firstWeekday: Int
    let histories: [History]
    let queries: [Query]
}

struct Observation: Encodable {
    let queryID, action: String
    let ids, closeIDs: [UUID]
    let placeChoices, notUnderstood, additionalTerms: [String]
    let slots: [String: [String]]
    let ms: Double
}

// The same slot names the simulator benchmark reports.
func slots(_ intent: WorkoutSearchIntent, calendar: Calendar) -> [String: [String]] {
    var slots: [String: [String]] = [:]
    func day(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    for filter in intent.filters {
        let key: String
        let value: String
        switch filter {
        case .terrain(let v): (key, value) = ("terrain", v.rawValue)
        case .sport(let v): (key, value) = ("sport", v)
        case .excludingSport(let v): (key, value) = ("excludingSport", v)
        case .type(let v): (key, value) = ("type", v)
        case .excludingType(let v): (key, value) = ("excludingType", v)
        case .place(let v): (key, value) = ("place", v)
        case .title(let v): (key, value) = ("title", v)
        case .titleOrNotes(let v): (key, value) = ("titleOrNotes", v)
        case .notes(let v): (key, value) = ("notes", v)
        case .date(let v, _): (key, value) = ("date", day(v.start) + "/" + day(v.end))
        case .dayOfMonth(let v, _, _): (key, value) = ("dayOfMonth", String(v))
        case .distance(let op, let v, _): (key, value) = ("distance", "\(op.rawValue):\(v)")
        case .duration(let op, let v, _): (key, value) = ("duration", "\(op.rawValue):\(v)")
        case .heartRate(let op, let v, _): (key, value) = ("heartRate", "\(op.rawValue):\(v)")
        case .climb(let op, let v, _): (key, value) = ("climb", "\(op.rawValue):\(v)")
        case .calories(let op, let v, _): (key, value) = ("calories", "\(op.rawValue):\(v)")
        case .pace(let op, let v, _): (key, value) = ("pace", "\(op.rawValue):\(v)")
        case .timeOfDay(let from, let to, _): (key, value) = ("timeOfDay", "\(from)-\(to)")
        case .weekday(let days, _): (key, value) = ("weekday", days.sorted().map(String.init).joined(separator: ","))
        case .similar(let id, _): (key, value) = ("similar", id?.uuidString ?? "latest")
        case .sky(let v, _): (key, value) = ("sky", v.rawValue)
        case .temperature(let op, let v, _): (key, value) = ("temperature", "\(op.rawValue):\(v)")
        case .wind(let op, let v, _): (key, value) = ("wind", "\(op.rawValue):\(v)")
        case .unsupported(let v): (key, value) = ("unsupported", v)
        }
        slots[key, default: []].append(value)
    }
    slots["sort"] = [intent.sort.rawValue]
    return slots
}

func record(_ w: Corpus.Workout) -> WorkoutSearchRecord {
    var place: WorkoutSearchPlace?
    if let city = w.city, let state = w.stateCode {
        place = WorkoutSearchPlace(address: "\(city), \(state)", city: city, state: state, country: w.countryCode ?? "")
    }
    let length = min(w.distanceMeters, 1000)
    var terrain: Set<WorkoutSearchTerrain>? = []
    var climb: Double? = 0
    switch w.profile ?? "unknown" {
    case "climb": terrain = length >= 100 ? [.uphill] : []; climb = length * 0.09
    case "descent": terrain = length >= 100 ? [.downhill] : []
    case "outBack": terrain = length >= 200 ? [.uphill, .downhill] : []; climb = length / 2 * 0.09
    case "unknown": climb = nil
    default: break
    }
    return WorkoutSearchRecord(id: w.id, date: w.startedAt, sport: w.sport, type: w.workoutType, title: w.title,
                               notes: w.notes, distance: w.distanceMeters, duration: w.activeSeconds, place: place,
                               isCoached: w.kind == "coached", terrain: terrain, climb: climb, timeZone: zone)
}

// Workouts start in the corpus's time zone, as the app's do in the zone they were recorded in.
nonisolated(unsafe) var zone: TimeZone? = nil
let arguments = CommandLine.arguments
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let corpus = try decoder.decode(Corpus.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
var calendar = Calendar(identifier: .gregorian)
calendar.locale = Locale(identifier: corpus.locale)
calendar.firstWeekday = corpus.firstWeekday
calendar.timeZone = TimeZone(identifier: corpus.timeZone)!
zone = calendar.timeZone
let histories = Dictionary(uniqueKeysWithValues: corpus.histories.map { ($0.id, $0.workouts.map(record)) })
var observations: [Observation] = []
for query in corpus.queries {
    let now = query.asOf ?? corpus.now
    let records = histories[query.historyID]!.filter { query.asOf == nil || $0.date <= now }
    let start = Date()
    let intent = WorkoutSearchEngine.parse(query.text, now: now, calendar: calendar, climbInFeet: false,
                                           places: WorkoutSearchPlaceNames.known(in: records))
    let result = WorkoutSearchEngine.search(intent, in: records)
    let ms = Date().timeIntervalSince(start) * 1000
    if let wanted = ProcessInfo.processInfo.environment["WR_DEBUG_TEXT"], query.text == wanted {
        print("intent:", intent.filters.map(\.label), "terms:", intent.terms, "sort:", intent.sort)
        let byID = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
        for match in WorkoutSearchScoring.score(intent, records: records).matches.sorted(by: { $0.score > $1.score }) {
            let r = byID[match.id]!
            print(String(format: "%.3f", match.score), r.date, r.type, Int(r.distance), Int(r.duration), r.place?.city ?? "-", r.title, "|", r.notes, match.misses)
        }
    }
    let action = !result.placeChoices.isEmpty ? "clarify" : result.ids.isEmpty ? "empty" : "results"
    observations.append(Observation(queryID: query.id, action: action, ids: result.ids, closeIDs: result.closeIDs,
                                    placeChoices: result.placeChoices, notUnderstood: result.notUnderstood,
                                    additionalTerms: result.appliedIntent.terms,
                                    slots: slots(result.appliedIntent, calendar: calendar), ms: ms))
}
let encoder = JSONEncoder()
try encoder.encode(observations).write(to: URL(fileURLWithPath: arguments[2]))

// Typing speed: score 1,000 workouts per keystroke, with the query parsed once as the screen caches it.
if ProcessInfo.processInfo.environment["WR_PERF"] != nil, let history = corpus.histories.first {
    var thousand: [WorkoutSearchRecord] = []
    while thousand.count < 1000 {
        for var r in histories[history.id]! where thousand.count < 1000 {
            r.id = UUID()
            thousand.append(r)
        }
    }
    for text in ["tempo rnu", "runs over 5 km in Portand", "hilly runs last month", "river", "fastest 10k"] {
        let intent = WorkoutSearchEngine.parse(text, now: corpus.now, calendar: calendar)
        var times: [Double] = []
        for _ in 0..<30 {
            let start = Date()
            _ = WorkoutSearchEngine.search(intent, in: thousand)
            times.append(Date().timeIntervalSince(start) * 1000)
        }
        times.sort()
        print(text, String(format: "median %.2f ms, worst %.2f ms", times[15], times[29]))
    }
}
