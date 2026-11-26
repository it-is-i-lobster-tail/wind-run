import SwiftData
import SwiftUI

struct HistorySearchView: View {
    @Query(sort: \Run.startDateValue, order: .reverse) private var history: [Run]
    let close: () -> Void
    private let index = WorkoutSearchIndex.shared

    var body: some View {
        let runs = history.filter { $0.status == .complete }
        // Keep SwiftData projection outside the view that observes each keystroke.
        HistorySearchContent(records: runs.map { WorkoutSearchRecord(run: $0, facts: index.facts[$0.runID]) },
                             byID: Dictionary(runs.map { ($0.runID, $0) }, uniquingKeysWith: { first, _ in first }),
                             index: index, close: close)
            .task(id: runs.map(\.runID)) { await index.update(for: runs, pruning: true) }
    }
}

private struct HistorySearchContent: View {
    let records: [WorkoutSearchRecord]
    let byID: [UUID: Run]
    let index: WorkoutSearchIndex
    let close: () -> Void
    @AppStorage(DistanceUnit.storageKey) private var unit = DistanceUnit.kilometers
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
                            .disabled(index.locating || index.indexing)
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
                        let ranked = !search.query.isEmpty && result.appliedIntent.sort.ranks
                        let shown = ranked && !showsAllRanked ? Array(result.ids.prefix(Self.rankedPreview)) : result.ids
                        Section(search.query.isEmpty ? "All workouts" : (ranked ? result.appliedIntent.sort.label : "Matching workouts")) {
                            ForEach(shown, id: \.self) { id in
                                if let run = byID[id] { resultRow(run) }
                            }
                            if shown.count < result.ids.count {
                                Button("Show all \(result.ids.count)") { showsAllRanked = true }
                                    .accessibilityIdentifier("showAllRanked")
                            }
                        }
                    } else if search.pending == nil && !search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if index.indexing && (search.intent.sort == .mostClimb || search.intent.filters.contains(where: Self.needsFacts)) {
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

    /// Filters that read route facts, which a workout only has once it has been indexed.
    private static func needsFacts(_ filter: WorkoutSearchFilter) -> Bool {
        switch filter {
        case .terrain, .climb, .heartRate, .calories: true
        default: false
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
            HStack { Text(title.prefix(1).uppercased() + title.dropFirst()); Image(systemName: "xmark.circle.fill") }
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

    /// The climb, heart rate or calories a search asked about, so the row shows why it matched or ranks there.
    private func effortEvidence(_ id: UUID) -> String? {
        guard let facts = index.facts[id] else { return nil }
        var asked = Set<String>()
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

    private func resultRow(_ run: Run) -> some View {
        NavigationLink { RunDetailView(run: run) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(run.intervalPlan?.name ?? run.coachWorkout?.title ?? ProgressGroup(run)?.type.name(for: run.sport) ?? run.sport.name)
                    .font(.headline)
                Text("\(RunFormat.distance(run.distanceMeters, unit: unit)) · \(RunFormat.duration(run.activeDuration())) · \(RunFormat.pace(run.pace(), unit: unit))")
                if let effort = effortEvidence(run.runID) {
                    Text(effort).font(.subheadline)
                }
                Text(run.startDate.formatted(date: .abbreviated, time: .shortened))
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
