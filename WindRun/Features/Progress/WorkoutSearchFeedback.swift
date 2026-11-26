import Foundation
import SwiftUI

/// The expected workout is an inclusion label. A tester need not select every valid result.
struct WorkoutSearchFeedback: Codable, Identifiable {
    static let enabledKey = "workoutSearchFeedbackEnabled"
    let id: UUID
    let query: String
    let date: Date
    let calendar: Calendar
    let expectedWorkout: UUID?

    private static func file() throws -> URL {
        let manager = FileManager.default
        let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: true)
        var folder = support.appendingPathComponent("SearchFeedback", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        return folder.appendingPathComponent("labels.json")
    }

    static func load() throws -> [Self] {
        do { return try JSONDecoder().decode([Self].self, from: Data(contentsOf: try file())) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
    }

    func save() throws {
        var rows = try Self.load()
        if let index = rows.firstIndex(where: { $0.id == id }) { rows[index] = self }
        else { rows.append(self) }
        try JSONEncoder().encode(rows).write(to: Self.file(), options: [.atomic, .completeFileProtection])
    }

    static func clear() throws {
        let url = try file()
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    func correct(_ result: WorkoutSearchResult) -> Bool {
        guard result.placeChoices.isEmpty else { return false }
        return expectedWorkout.map { result.ids.contains($0) } ?? result.ids.isEmpty
    }
}

struct SearchFeedbackComparison: View {
    let records: [WorkoutSearchRecord]
    @State private var running = false
    @State private var summary = ""
    @State private var hasTotals = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Text("Compare standard search and Apple Intelligence on your labeled searches. Each pair uses the same current workout details and excludes workouts started after you gave feedback.")
            Button("Compare saved searches") { running = true }
                .disabled(running)
            if running { ProgressView("Comparing searches…") }
            if !summary.isEmpty {
                Text(summary).textSelection(.enabled)
                if hasTotals {
                    ShareLink("Share comparison totals", item: summary)
                }
            }
            if let errorMessage { Text(errorMessage) }
        }
        .navigationTitle("Search feedback")
        .task(id: running) {
            guard running else { return }
            defer { running = false }
            do {
                errorMessage = nil
                hasTotals = false
                summary = ""
                let labels = try WorkoutSearchFeedback.load()
                guard !labels.isEmpty else { summary = "No labeled searches yet."; return }
                var positives = 0, negatives = 0, skipped = 0, modelAnswers = 0, attempts = 0
                var rulesHits = 0, modelHits = 0, rulesEmpty = 0, modelEmpty = 0
                for label in labels {
                    try Task.checkCancellation()
                    let history = records.filter { $0.date <= label.date }
                    if let id = label.expectedWorkout, !history.contains(where: { $0.id == id }) {
                        skipped += 1
                        continue
                    }
                    let rules = WorkoutSearchEngine.parse(label.query, now: label.date, calendar: label.calendar)
                    let model = await WorkoutToolSearch.interpret(label.query, records: history, now: label.date, calendar: label.calendar)
                    try Task.checkCancellation()
                    let localCorrect = label.correct(WorkoutSearchEngine.search(rules, in: history))
                    let hybridCorrect = label.correct(WorkoutSearchEngine.search(model.intent, in: history))
                    if label.expectedWorkout == nil {
                        negatives += 1
                        if localCorrect { rulesEmpty += 1 }
                        if hybridCorrect { modelEmpty += 1 }
                    } else {
                        positives += 1
                        if localCorrect { rulesHits += 1 }
                        if hybridCorrect { modelHits += 1 }
                    }
                    if model.usedModel { attempts += 1 }
                    if model.status == "model" { modelAnswers += 1 }
                }
                hasTotals = false
                hasTotals = true
                summary = """
                Expected workout found
                Standard \(rulesHits)/\(positives) · Hybrid \(modelHits)/\(positives)

                Correctly empty
                Standard \(rulesEmpty)/\(negatives) · Hybrid \(modelEmpty)/\(negatives)

                Model attempts \(attempts) · Accepted model responses \(modelAnswers)
                Missing selected workouts skipped \(skipped)
                """
            } catch is CancellationError { }
            catch { errorMessage = "Could not read saved feedback." }
        }
    }
}
