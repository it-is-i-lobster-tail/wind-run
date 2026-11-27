import SwiftData
import SwiftUI

struct HistorySearchView: View {
    @Query(sort: \Run.startDateValue, order: .reverse) private var history: [Run]
    /// A search to start with, such as workouts like one run.
    var initial: WorkoutSearchFilter? = nil
    let close: () -> Void
    private let index = WorkoutSearchIndex.shared

    var body: some View {
        let runs = history.filter { $0.status == .complete }
        // Keep SwiftData projection outside the view that observes each keystroke.
        HistorySearchContent(records: runs.map { WorkoutSearchRecord(run: $0, facts: index.facts[$0.runID]) },
                             byID: Dictionary(runs.map { ($0.runID, $0) }, uniquingKeysWith: { first, _ in first }),
                             index: index, initial: initial, close: close)
            .task(id: runs.map(\.runID)) { await index.update(for: runs, pruning: true) }
    }
}

private struct HistorySearchContent: View {
    let records: [WorkoutSearchRecord]
    let byID: [UUID: Run]
    let index: WorkoutSearchIndex
    let initial: WorkoutSearchFilter?
    let close: () -> Void
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
    @State private var recent = WorkoutSearchRecents.load()
    @State private var search = WorkoutSearchSession()
    @AppStorage(WorkoutSearchFeedback.enabledKey) private var feedbackEnabled = false
    @State private var feedbackID = UUID()
    @State private var labeled = false
    @State private var pickingWorkout = false
    @State private var saveFailed = false
    @State private var editedFilters = false
    @State private var showsAllRanked = false
    /// "Fastest" or "longest" ranks every workout, so the top few come first.
    private static let rankedPreview = 5

    var body: some View {
        let result = WorkoutSearchEngine.search(search.intent, in: records)
        NavigationStack {
            List {
                if search.query.isEmpty {
                    if !recent.isEmpty {
                        Section {
                            ForEach(recent, id: \.self) { phrase in
                                Button { search.edit(phrase) } label: { Label(phrase, systemImage: "clock.arrow.circlepath") }
                                    .accessibilityIdentifier("recentSearch")
                            }
                        } header: {
                            HStack {
                                Text("Recent searches")
                                Spacer()
                                Button("Clear") { WorkoutSearchRecents.clear(); recent = [] }
                                    .font(.subheadline).textCase(nil)
                                    .accessibilityIdentifier("clearRecentSearches")
                            }
                        }
                    }
                    Section("Try a search") {
                        ForEach(WorkoutSearchSuggestions.phrases(for: records, unit: unit), id: \.self) { phrase in
                            Button { search.edit(phrase) } label: { Label(phrase, systemImage: "magnifyingglass") }
                                .accessibilityIdentifier("searchSuggestion")
                        }
                    }
                    if feedbackEnabled {
                        NavigationLink("Compare saved search feedback") { SearchFeedbackComparison(records: records) }
                            .disabled(index.locating || index.indexing)
                    }
                    NavigationLink("Workout trends and comparisons") { ProgressHomeView() }
                }
                filters(for: result)
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
                        let ranked = !search.query.isEmpty && result.appliedIntent.sort.ranks
                        // Personal bests are one row per best held, so the list is short and shows whole.
                        let previews = ranked && !showsAllRanked && result.appliedIntent.sort != .personalBests
                        let shown = previews ? Array(result.ids.prefix(Self.rankedPreview)) : result.ids
                        Section(search.query.isEmpty ? "All workouts" : (ranked ? Self.sortLabel(result.appliedIntent) : "Best matches")) {
                            ForEach(shown, id: \.self) { id in
                                if let run = byID[id] { resultRow(run, marks: result.marks[id] ?? [], applied: result.appliedIntent) }
                            }
                            if shown.count < result.ids.count {
                                Button("Show all \(result.ids.count)") { showsAllRanked = true }
                                    .accessibilityIdentifier("showAllRanked")
                            }
                        }
                    }
                    if !search.query.isEmpty && !result.closeIDs.isEmpty && search.pending == nil {
                        Section {
                            ForEach(result.closeIDs, id: \.self) { id in
                                if let run = byID[id] {
                                    resultRow(run, misses: result.misses[id] ?? [], marks: result.marks[id] ?? [], applied: result.appliedIntent)
                                }
                            }
                        } header: {
                            // With no best match, say so above the list, where it reads first.
                            Text(result.ids.isEmpty ? "No exact matches. These come close." : "Close matches")
                        }
                        .accessibilityIdentifier("closeMatches")
                    } else if result.ids.isEmpty && search.pending == nil && !search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if index.indexing && ([.mostClimb, .bestEffort, .personalBests, .recordsSet].contains(search.intent.sort) || search.intent.filters.contains(where: { Self.needsFacts($0) })) {
                            ProgressView("Reading workout routes…")
                        } else if index.locating && (!search.intent.terms.isEmpty || search.intent.filters.contains(where: { if case .place = $0 { true } else { false } })) {
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
            .onAppear {
                search.places = WorkoutSearchPlaceNames.known(in: records)
                if let initial, search.query.isEmpty { search.seed(initial) }
            }
            .onChange(of: WorkoutSearchPlaceNames.known(in: records)) { _, places in search.places = places }
            .onChange(of: search.query) {
                feedbackID = UUID()
                labeled = false
                editedFilters = false
                showsAllRanked = false
            }
            .alert("Could not save feedback", isPresented: $saveFailed) { Button("OK") {} }
            .navigationTitle("Search history")
            .searchable(text: Binding(get: { search.query }, set: { search.edit($0) }),
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Place, date, distance, or workout")
            .onSubmit(of: .search) {
                remember(search.query)
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

    /// "Fastest 5K" rather than "Fastest time", so the chip says which distance it ranks.
    private static func sortLabel(_ intent: WorkoutSearchIntent) -> String {
        if intent.sort == .bestEffort, let meters = intent.effortMeters { return "Fastest " + WorkoutSearchEfforts.name(meters) }
        return intent.sort.label
    }

    /// Filters that read route facts, which a workout only has once it has been indexed.
    private static func needsFacts(_ filter: WorkoutSearchFilter) -> Bool {
        switch filter {
        case .terrain, .climb, .heartRate, .calories, .similar: true
        default: false
        }
    }

    /// Keeps a typed search among the recent ones, on this iPhone only. A search built by the screen isn't typed.
    private func remember(_ query: String) {
        guard initial == nil || query != initial?.label else { return }
        recent = WorkoutSearchRecents.add(query)
    }

    private func saveFeedback(_ expected: UUID?) {
        guard feedbackEnabled else { return }
        do {
            try WorkoutSearchFeedback(id: feedbackID, query: search.query, date: .now,
                                      calendar: .current, expectedWorkout: expected).save()
            labeled = true
        } catch { saveFailed = true }
    }

    /// What search understood, one chip per part. Tapping a chip removes that part of the query.
    @ViewBuilder private func filters(for result: WorkoutSearchResult) -> some View {
        let applied = result.appliedIntent
        if !applied.filters.isEmpty || applied.sort != .newest || !result.notUnderstood.isEmpty || !result.meanings.isEmpty {
            Section("Filters") {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(applied.filters, id: \.self) { filter in
                            chip(chipLabel(filter, readings: result.looseReadings)) {
                                editedFilters = true; search.remove(filter, from: applied)
                            }
                        }
                        if applied.sort != .newest {
                            chip(Self.sortLabel(applied)) { editedFilters = true; search.resetSorting() }
                        }
                        ForEach(result.meanings.keys.sorted(), id: \.self) { word in
                            chip("\(result.meanings[word] ?? word) (from \(word))") { editedFilters = true; search.removeWord(word, from: applied) }
                        }
                        ForEach(result.notUnderstood, id: \.self) { word in
                            chip("Not understood: " + word, muted: true) { editedFilters = true; search.removeWord(word, from: applied) }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    /// A place read from a near spelling says so, such as "Portland (from Portand)".
    private func chipLabel(_ filter: WorkoutSearchFilter, readings: [String: String]) -> String {
        if case .place(let name) = filter, let reading = readings[name] { return reading }
        return filter.label
    }

    private func chip(_ title: String, muted: Bool = false, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack { Text(title.prefix(1).uppercased() + title.dropFirst()); Image(systemName: "xmark.circle.fill") }
                .font(.subheadline)
                .foregroundStyle(muted ? .secondary : .primary)
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

    /// The climb, heart rate or calories a search asked about, so the row shows why it matched or ranks there.
    private func effortEvidence(_ run: Run, marks: [WorkoutSearchPersonalBests.Mark]) -> String? {
        let id = run.runID
        let applied = search.intent
        if applied.sort == .bestEffort, let meters = applied.effortMeters {
            let key = WorkoutSearchEfforts.key(meters)
            // The starred line already says the time of the best one.
            if marks.contains(where: { $0.kind == .effort(key) }) { return nil }
            // A run with no time inside its route stands for the distance when it ran it, or up to 5% over.
            let seconds = index.facts[id]?.bestEfforts?[key] ??
                (run.distanceMeters >= meters && run.distanceMeters <= meters * (1 + WorkoutSearchPersonalBests.wholeRunAllowance)
                    ? run.activeDuration() : nil)
            if let seconds { return "Best \(WorkoutSearchEfforts.name(meters)) \(RunFormat.duration(seconds))" }
        }
        guard let facts = index.facts[id] else { return nil }
        var asked = Set<String>()
        if applied.sort == .hardest || applied.sort == .easiest { asked.insert("heartRate") }
        if search.intent.sort == .mostClimb { asked.insert("climb") }
        for filter in search.intent.filters {
            switch filter {
            case .climb: asked.insert("climb")
            case .heartRate: asked.insert("heartRate")
            case .calories: asked.insert("calories")
            default: break
            }
        }
        var parts: [String] = []
        if asked.contains("climb"), let climb = facts.climb { parts.append("Climb " + RunFormat.elevation(climb, unit: unit)) }
        if asked.contains("heartRate"), let bpm = facts.heartRate { parts.append("Avg HR " + RunFormat.heartRate(bpm)) }
        if asked.contains("calories"), let kcal = facts.calories { parts.append(RunFormat.calories(kcal)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// What a close match fell short on, such as "5.6 km, a bit over 5 km" or "Not in Portland". Rows never show a score.
    private func shortfall(_ misses: [WorkoutSearchMiss], run: Run) -> String? {
        let parts = misses.compactMap { miss -> String? in
            if let term = miss.term {
                if case .missing = miss.kind { return "No “\(term)”" }
                if case .loose(let meaning) = miss.kind, !meaning.isEmpty { return "Says “\(meaning)”" }
                return nil
            }
            guard let filter = miss.filter else { return nil }
            let side: String? = switch miss.kind {
            case .over: "a bit over"
            case .under: "a bit under"
            default: nil
            }
            let facts = index.facts[run.runID]
            switch filter {
            case .distance(_, let target, _):
                return side.map { "\(RunFormat.distance(run.distanceMeters, unit: unit)), \($0) \(RunFormat.distance(target, unit: unit, rounding: .toNearestOrAwayFromZero))" }
            case .duration(_, let target, _):
                return side.map { "\(RunFormat.duration(run.activeDuration())), \($0) \(RunFormat.duration(target))" }
            case .pace(_, let target, _):
                let slower = miss.kind == .over
                return side.map { _ in "\(RunFormat.pace(run.pace(), unit: unit)), a bit \(slower ? "slower" : "faster") than \(RunFormat.pace(target, unit: unit))" }
            case .heartRate(_, let target, _):
                return side.map { "Avg HR \(RunFormat.heartRate(facts?.heartRate)), \($0) \(Int(target))" } ?? "No heart rate"
            case .climb(_, let target, _):
                return side.map { "Climb \(RunFormat.elevation(facts?.climb ?? 0, unit: unit)), \($0) \(RunFormat.elevation(target, unit: unit))" } ?? "No climb recorded"
            case .calories(_, let target, _):
                return side.map { "\(RunFormat.calories(facts?.calories)), \($0) \(Int(target))" } ?? "No calories recorded"
            case .place(let name):
                if case .loose = miss.kind { return nil }
                return "Not in \(name)"
            case .terrain(let terrain):
                return terrain == .flat ? "Has steep stretches" : "No \(terrain.label.components(separatedBy: " · ")[0].lowercased())"
            case .similar: return "Partly the same way"
            case .type(let type): return "Not \(type == "intervals" ? "intervals" : "a \(type) workout")"
            case .title(let x), .notes(let x), .titleOrNotes(let x):
                if case .loose = miss.kind { return "Similar to “\(x)”" }
                return "No “\(x)”"
            default: return nil
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// One starred line per group of bests: "PR · 5K 23:30 · Furthest 21.1 km" for all-time bests (or bests set
    /// at the time, for a "new PR" search), and an outlined star with "Best this year · …" for bests of only the
    /// workouts searched.
    private func markLines(_ marks: [WorkoutSearchPersonalBests.Mark], applied: WorkoutSearchIntent) -> [(text: String, filled: Bool)] {
        guard !marks.isEmpty else { return [] }
        if applied.sort == .recordsSet {
            return [("PR set · " + marks.map(markText).joined(separator: " · "), true)]
        }
        var lines: [(String, Bool)] = []
        let allTime = marks.filter(\.allTime), period = marks.filter { !$0.allTime }
        if !allTime.isEmpty { lines.append(("PR · " + allTime.map(markText).joined(separator: " · "), true)) }
        if !period.isEmpty {
            let span = applied.filters.lazy.compactMap { filter -> String? in
                if case .date(_, let label) = filter { return label } else { return nil }
            }.first
            lines.append(((span.map { "Best \($0)" } ?? "Best of these") + " · " + period.map(markText).joined(separator: " · "), false))
        }
        return lines
    }

    private func markText(_ mark: WorkoutSearchPersonalBests.Mark) -> String {
        switch mark.kind {
        case .effort(let key): "\(WorkoutSearchEfforts.name(Double(key))) \(RunFormat.duration(mark.value))"
        case .distance: "Furthest \(RunFormat.distance(mark.value, unit: unit))"
        case .time: "Longest time \(RunFormat.duration(mark.value))"
        case .pace: "Fastest pace \(RunFormat.pace(mark.value, unit: unit))"
        case .climb: "Most climb \(RunFormat.elevation(mark.value, unit: unit))"
        }
    }

    private func resultRow(_ run: Run, misses: [WorkoutSearchMiss] = [], marks: [WorkoutSearchPersonalBests.Mark] = [],
                           applied: WorkoutSearchIntent) -> some View {
        NavigationLink { RunDetailView(run: run).onAppear { remember(search.query) } } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(run.intervalPlan?.name ?? run.coachWorkout?.title ?? ProgressGroup(run)?.type.name(for: run.sport) ?? run.sport.name)
                    .font(.headline)
                Text("\(RunFormat.distance(run.distanceMeters, unit: unit)) · \(RunFormat.duration(run.activeDuration())) · \(RunFormat.pace(run.pace(), unit: unit))")
                ForEach(markLines(marks, applied: applied), id: \.text) { line in
                    Label(line.text, systemImage: line.filled ? "star.fill" : "star")
                        .font(.subheadline)
                        .foregroundStyle(.tint)
                        .accessibilityLabel((line.filled ? "Personal best. " : "") + line.text)
                        .accessibilityIdentifier("personalBest")
                }
                if let effort = effortEvidence(run, marks: marks) {
                    Text(effort).font(.subheadline)
                }
                if let shortfall = shortfall(misses, run: run) {
                    Text(shortfall).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("closeMatchShortfall")
                }
                Text(RunFormat.startDateAndTime(run.startDate, in: run.recordedTimeZone))
                    .font(.subheadline).foregroundStyle(.secondary)
                if let place = index.city(for: run.runID) {
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
