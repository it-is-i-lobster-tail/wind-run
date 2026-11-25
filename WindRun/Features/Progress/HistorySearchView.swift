import MapKit
import NaturalLanguage
import SwiftData
import SwiftUI

struct HistorySearchView: View {
    @Query(sort: \Run.startDateValue, order: .reverse) private var history: [Run]
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var places: [UUID: String] = [:]
    @State private var locating = false
    private let suggestions = ["Fast pace", "Long distance", "Last week", "Intervals"]

    var body: some View {
        let runs = history.filter { $0.status == .complete }
        let search = WorkoutQuery(query)
        NavigationStack {
            List {
                if search.isEmpty {
                    Section("Try a search") {
                        ForEach(suggestions, id: \.self) { phrase in
                            Button { query = phrase } label: { Label(phrase, systemImage: "magnifyingglass") }
                        }
                    }
                    NavigationLink("Workout trends and comparisons") { ProgressHomeView() }
                }
                let matches = search.isEmpty ? runs : search.results(runs, places: places)
                Section(search.isEmpty ? "All workouts" : search.heading) {
                    ForEach(matches) { run in
                        NavigationLink { RunDetailView(run: run) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(run.intervalPlan?.name ?? run.coachWorkout?.title ?? ProgressGroup(run)?.type.name(for: run.sport) ?? run.sport.name)
                                    .font(.headline)
                                Text("\(RunFormat.distance(run.distanceMeters, unit: unit)) · \(RunFormat.pace(run.pace(), unit: unit))")
                                Text(run.startDate.formatted(date: .abbreviated, time: .shortened))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                if let place = places[run.runIDValue] {
                                    Text(place).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                if matches.isEmpty && !search.isEmpty {
                    if locating { ProgressView("Looking up workout locations…") }
                    else { ContentUnavailableView.search(text: query) }
                }
            }
            .navigationTitle("Search history")
            .searchable(text: $query, prompt: "Date, place, type, or effort")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .task(id: runs.map(\.runIDValue)) { await loadPlaces(for: runs) }
    }

    // Keep resolved start areas across searches without persisting addresses.
    private static let placeCache = NSCache<NSString, NSString>()

    private func loadPlaces(for runs: [Run]) async {
        locating = true
        defer { locating = false }
        for run in runs {
            guard !Task.isCancelled else { return }
            guard let start = run.routeSamplesValue?.min(by: { $0.timestamp < $1.timestamp })?.location else { continue }
            let c = start.coordinate
            guard CLLocationCoordinate2DIsValid(c) else { continue }
            let key = "\(Int((c.latitude * 1000).rounded()))/\(Int((c.longitude * 1000).rounded()))"
            if let cached = Self.placeCache.object(forKey: key as NSString) {
                places[run.runIDValue] = cached as String
            } else if let request = MKReverseGeocodingRequest(location: start),
                      let item = try? await request.mapItems.first {
                guard let address = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true) ?? item.name else { continue }
                Self.placeCache.setObject(address as NSString, forKey: key as NSString)
                places[run.runIDValue] = address
            }
        }
    }
}

struct WorkoutQuery {
    enum Metric { case pace, distance }
    private var words: [String]
    private var metric: Metric?
    private var period: DateInterval?
    private var dayOfMonth: Int?
    private static let embedding = NLEmbedding.wordEmbedding(for: .english)
    private static let ignored: Set<String> = ["a", "the", "my", "me", "show", "find", "with", "of", "at", "near", "in", "from", "on", "during", "workout", "workouts", "and"]
    let isEmpty: Bool
    var heading: String {
        switch metric {
        case .pace: "Fastest average pace"
        case .distance: "Longest distance"
        case nil: "Matching workouts"
        }
    }

    init(_ text: String, now: Date = .now, calendar: Calendar = .current) {
        var input = text
        if let match = input.firstMatch(of: /\b(\d{4})-(\d{2})-(\d{2})\b/),
           let y = Int(match.1), let m = Int(match.2), let d = Int(match.3),
           let date = calendar.date(from: DateComponents(year: y, month: m, day: d)),
           calendar.component(.month, from: date) == m, calendar.component(.day, from: date) == d {
            period = calendar.dateInterval(of: .day, for: date)
            input.removeSubrange(match.range)
        }
        var phrase = " " + Self.words(input).joined(separator: " ") + " "
        isEmpty = text.trimmingCharacters(in: .whitespaces).isEmpty
        for (name, component, offset) in [("today", Calendar.Component.day, 0), ("yesterday", .day, -1),
                                          ("this week", .weekOfYear, 0), ("last week", .weekOfYear, -1),
                                          ("this month", .month, 0), ("last month", .month, -1),
                                          ("this year", .year, 0), ("last year", .year, -1)] {
            if phrase.contains(" " + name + " "), let date = calendar.date(byAdding: component, value: offset, to: now) {
                period = calendar.dateInterval(of: component, for: date)
                phrase = phrase.replacingOccurrences(of: " " + name + " ", with: " ")
                break
            }
        }
        var tokens = Self.words(phrase)
        if tokens.contains(where: { Self.related($0, to: ["fast", "fastest", "quick", "speedy", "faster", "brisk"]) }) {
            metric = .pace
            tokens.removeAll { $0 == "pace" || Self.related($0, to: ["fast", "fastest", "quick", "speedy", "faster", "brisk"]) }
        } else if tokens.contains(where: { ["long", "longest", "longer", "farthest", "furthest", "lengthy"].contains($0) }) {
            metric = .distance
            tokens.removeAll { ["long", "longest", "longer", "farthest", "furthest", "lengthy", "distance", "distances"].contains($0) }
        }
        let months = Set((calendar.monthSymbols + calendar.shortMonthSymbols).flatMap { Self.words($0) })
        if let month = tokens.firstIndex(where: months.contains) {
            for i in [month + 1, month - 1] where tokens.indices.contains(i) {
                if let day = Int(tokens[i]), (1...31).contains(day) {
                    dayOfMonth = day
                    tokens.remove(at: i)
                    break
                }
            }
        }
        words = tokens.filter { !Self.ignored.contains($0) }
    }

    private static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static func related(_ word: String, to anchors: [String]) -> Bool {
        if anchors.contains(word) { return true }
        guard let embedding, embedding.contains(word) else { return false }
        return anchors.contains { embedding.distance(between: word, and: $0) < 0.32 }
    }

    func results(_ runs: [Run], places: [UUID: String]) -> [Run] {
        let matches: [Run] = runs.filter { run in
            if let period, !(period.start..<period.end).contains(run.startDate) { return false }
            if let dayOfMonth, Calendar.current.component(.day, from: run.startDate) != dayOfMonth { return false }
            if words.isEmpty { return true }
            let group = ProgressGroup(run)
            let dates = run.startDate.formatted(.dateTime.year().month(.wide).day().weekday(.wide))
            let abbreviated = run.startDate.formatted(.dateTime.month(.abbreviated).weekday(.abbreviated))
            let sport = run.sport == .cycling ? "cycling cycle bike bicycle ride rides biking" : "running run runs jog jogging"
            let fields: [String?] = [sport, group?.type.rawValue, group?.type.name(for: run.sport), run.intervalPlan?.name,
                          run.coachWorkout?.title, run.kind == .coached ? "coach coached" : nil, run.notesValue, dates, abbreviated, places[run.runIDValue]]
            let terms = Set(Self.words(fields.compactMap { $0 }.joined(separator: " ")))
            return words.allSatisfy { word in terms.contains { $0 == word || (word.count >= 3 && $0.hasPrefix(word)) } }
        }
        switch metric {
        case .pace: return matches.filter { ($0.pace() ?? 0) > 0 }.sorted { ($0.pace() ?? .infinity) < ($1.pace() ?? .infinity) }
        case .distance: return matches.filter { $0.distanceMeters > 0 }.sorted { $0.distanceMeters > $1.distanceMeters }
        case nil: return matches
        }
    }
}
