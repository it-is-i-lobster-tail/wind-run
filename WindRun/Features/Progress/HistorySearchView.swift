import MapKit
import NaturalLanguage
import SwiftData
import SwiftUI

struct HistorySearchView: View {
    @Query(sort: \Run.startDateValue, order: .reverse) private var history: [Run]
    let close: () -> Void
    @State private var locations = WorkoutSearchLocations()

    var body: some View {
        let runs = history.filter { $0.status == .complete }
        // Keep SwiftData projection outside the view that observes each keystroke.
        HistorySearchContent(records: runs.map { WorkoutSearchRecord(run: $0, place: locations.details[$0.runID]) },
                             byID: Dictionary(runs.map { ($0.runID, $0) }, uniquingKeysWith: { first, _ in first }),
                             locations: locations, close: close)
            .task(id: runs.map(\.runID)) { await locations.loadPlaces(for: runs) }
    }
}

private struct HistorySearchContent: View {
    let records: [WorkoutSearchRecord]
    let byID: [UUID: Run]
    let locations: WorkoutSearchLocations
    let close: () -> Void
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @State private var search = WorkoutSearchSession()
    @AppStorage(WorkoutSearchFeedback.enabledKey) private var feedbackEnabled = false
    @State private var feedbackID = UUID()
    @State private var labeled = false
    @State private var pickingWorkout = false
    @State private var saveFailed = false
    @State private var editedFilters = false
    private let suggestions = ["Fast pace", "Runs over 5 km", "Last week", "Intervals"]

    var body: some View {
        let result = WorkoutSearchEngine.search(search.intent, in: records)
        NavigationStack {
            List {
                if search.query.isEmpty {
                    Section("Try a search") {
                        ForEach(suggestions, id: \.self) { phrase in
                            Button { search.edit(phrase) } label: { Label(phrase, systemImage: "magnifyingglass") }
                        }
                    }
                    if feedbackEnabled {
                        NavigationLink("Compare saved search feedback") { SearchFeedbackComparison(records: records) }
                            .disabled(locations.locating)
                    }
                    NavigationLink("Workout trends and comparisons") { ProgressHomeView() }
                }
                filters(for: result.appliedIntent)
                if search.pending != nil {
                    ProgressView("Interpreting search…")
                } else if let notice = search.notice {
                    Text(notice).font(.footnote).foregroundStyle(.secondary)
                }
                if !result.placeChoices.isEmpty {
                    Section("Which starting place?") {
                        ForEach(result.placeChoices, id: \.self) { place in
                            Button(place) { editedFilters = true; search.choosePlace(place) }
                        }
                    }
                } else {
                    if !result.ids.isEmpty || search.query.isEmpty {
                        Section(search.query.isEmpty ? "All workouts" : "Matching workouts") {
                            ForEach(result.ids, id: \.self) { id in
                                if let run = byID[id] { resultRow(run) }
                            }
                        }
                    } else if search.pending == nil && !search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if locations.locating && (!search.intent.terms.isEmpty || search.intent.filters.contains(where: { if case .place = $0 { true } else { false } })) {
                            ProgressView("Looking up workout locations…")
                        } else {
                            if feedbackEnabled && !editedFilters {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("No matching workouts").font(.headline)
                                    Text("Your recorded workout history has no matches for this search.")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                if labeled { Label("Feedback saved", systemImage: "checkmark") }
                                else {
                                    Button("No match is right") { saveFeedback(nil) }
                                    Button("I expected a workout") { pickingWorkout = true }.disabled(records.isEmpty)
                                }
                            } else {
                                ContentUnavailableView("No matching workouts", systemImage: "magnifyingglass",
                                                       description: Text("Your recorded workout history has no matches for this search."))
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $pickingWorkout) {
                NavigationStack {
                    List(records, id: \.id) { row in
                        Button {
                            saveFeedback(row.id)
                            pickingWorkout = false
                        } label: {
                            VStack(alignment: .leading) {
                                Text(row.title.isEmpty ? row.sport.capitalized : row.title)
                                Text("\(row.date.formatted()) · \(RunFormat.distance(row.distance, unit: unit))")
                            }
                        }
                        .accessibilityIdentifier("feedbackWorkout")
                    }
                    .navigationTitle("Expected workout")
                    .toolbar { Button("Cancel") { pickingWorkout = false } }
                }
            }
            .onChange(of: search.query) {
                feedbackID = UUID()
                labeled = false
                editedFilters = false
            }
            .alert("Could not save feedback", isPresented: $saveFailed) { Button("OK") {} }
            .navigationTitle("Search history")
            .searchable(text: Binding(get: { search.query }, set: { search.edit($0) }),
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Place, date, distance, or workout")
            .onSubmit(of: .search) {
                search.submitIfEnabled(WorkoutSearchSession.modelSearchEnabled)
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", action: close) } }
        }
        .task(id: search.pending) {
            guard let submission = search.pending else { return }
            await search.interpret(submission) { text in
                #if DEBUG
                if ProgressDemo.testsSearch {
                    if ProcessInfo.processInfo.arguments.contains("-holdSearchInterpretation") {
                        // Editing the query cancels this task. Keep the fixture pending until
                        // that edit so the UI test does not race the simulator's event delivery.
                        let (events, continuation) = AsyncStream<Void>.makeStream()
                        defer { continuation.finish() }
                        for await _ in events {}
                    }
                    return WorkoutInterpretation(intent: WorkoutSearchEngine.parse("intervals"), status: "model", usedModel: true)
                }
                #endif
                return await WorkoutToolSearch.interpret(text, records: records)
            }
        }
    }

    private func saveFeedback(_ expected: UUID?) {
        guard feedbackEnabled else { return }
        do {
            try WorkoutSearchFeedback(id: feedbackID, query: search.query, date: .now,
                                      calendar: .current, expectedWorkout: expected).save()
            labeled = true
        } catch { saveFailed = true }
    }

    @ViewBuilder private func filters(for applied: WorkoutSearchIntent) -> some View {
        if !applied.filters.isEmpty || applied.sort != .newest {
            Section("Filters") {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(applied.filters, id: \.self) { filter in
                            chip(filter.label) { editedFilters = true; search.remove(filter, from: applied) }
                        }
                        if applied.sort != .newest {
                            chip(applied.sort.label) { editedFilters = true; search.resetSorting() }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func chip(_ title: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack { Text(title); Image(systemName: "xmark.circle.fill") }
                .font(.subheadline)
                .padding(.horizontal, 10).frame(minHeight: 44)
                .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove \(title)")
    }

    private func noteEvidence(_ notes: String) -> String? {
        for case let .notes(phrase) in search.intent.filters {
            for term in phrase.split(separator: " ") {
                if let match = notes.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) {
                    let start = notes.index(match.lowerBound, offsetBy: -28, limitedBy: notes.startIndex) ?? notes.startIndex
                    return (start == notes.startIndex ? "" : "…") + notes[start...].prefix(160)
                }
            }
        }
        return nil
    }

    private func resultRow(_ run: Run) -> some View {
        NavigationLink { RunDetailView(run: run) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(run.intervalPlan?.name ?? run.coachWorkout?.title ?? ProgressGroup(run)?.type.name(for: run.sport) ?? run.sport.name)
                    .font(.headline)
                Text("\(RunFormat.distance(run.distanceMeters, unit: unit)) · \(RunFormat.duration(run.activeDuration())) · \(RunFormat.pace(run.pace(), unit: unit))")
                Text(run.startDate.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline).foregroundStyle(.secondary)
                if let place = locations.cities[run.runID] {
                    Text(place).font(.caption).foregroundStyle(.secondary)
                }
                if let excerpt = noteEvidence(run.notesValue) {
                    Text(excerpt).lineLimit(2).font(.caption)
                }
            }
        }
        .accessibilityIdentifier("workoutSearchResult")
    }
}

@MainActor @Observable
final class WorkoutSearchLocations {
    var details: [UUID: WorkoutSearchPlace] = [:]
    var places: [UUID: String] = [:]
    var cities: [UUID: String] = [:]
    var locating = false

    // Keep resolved start areas across searches without persisting addresses.
    private final class Place {
        let details: WorkoutSearchPlace
        let city: String?
        init(details: WorkoutSearchPlace, city: String?) {
            self.details = details
            self.city = city
        }
    }
    private static let placeCache = NSCache<NSString, Place>()

    func loadPlaces(for runs: [Run]) async {
        locating = true
        defer { locating = false }
        #if DEBUG
        if ProgressDemo.testsSearch && ProgressDemo.isRequested {
            for (index, run) in runs.enumerated() {
                let state = index.isMultiple(of: 2) ? "ME" : "OR"
                let city = "Portland, " + state
                cities[run.runID] = city
                places[run.runID] = city
                details[run.runID] = WorkoutSearchPlace(address: city, city: "Portland", state: state, country: "US")
            }
            return
        }
        #endif
        for run in runs {
            guard !Task.isCancelled else { return }
            guard let start = run.startLocation else { continue }
            let c = start.coordinate
            let key = "\(Int((c.latitude * 1000).rounded()))/\(Int((c.longitude * 1000).rounded()))"
            if let cached = Self.placeCache.object(forKey: key as NSString) {
                details[run.runIDValue] = cached.details
                places[run.runIDValue] = cached.details.address
                cities[run.runIDValue] = cached.city
            } else if let request = MKReverseGeocodingRequest(location: start),
                      let item = try? await request.mapItems.first {
                guard let address = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true) ?? item.name else { continue }
                let city = item.addressRepresentations?.cityWithContext(.short) ?? item.addressRepresentations?.cityName
                let region = item.addressRepresentations?.region?.identifier
                let terms = Self.searchAddress(address, city: city, region: region)
                let name = item.addressRepresentations?.cityName ?? ""
                let state = region == "US" ? Self.stateCode(address, city: city) : nil
                let place = WorkoutSearchPlace(address: terms, city: name, state: state ?? "", country: region ?? "")
                details[run.runIDValue] = place
                Self.placeCache.setObject(Place(details: place, city: city), forKey: key as NSString)
                cities[run.runIDValue] = city
                places[run.runIDValue] = terms
            }
        }
    }

    // MapKit formats US city context as "City, ST". Keep the displayed address and index both forms.
    static func searchAddress(_ address: String, city: String?, region: String?) -> String {
        guard region == "US", let code = stateCode(address, city: city), let state = stateNames[code] else { return address }
        return "\(address) \(code) \(state)"
    }

    private static func stateCode(_ address: String, city: String?) -> String? {
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
            let sport = switch run.sport {
            case .cycling: "cycling cycle bike bicycle ride rides biking"
            case .running: "running run runs jog jogging"
            case .hiking: "hike hikes hiked hiking"
            }
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
