import Foundation
import Observation

/// Owns the text, visible filters and lifetime of one search submission.
@MainActor @Observable
final class WorkoutSearchSession {
    static let toolSearchKey = "workoutHistoryToolSearch"

    static var modelSearchEnabled: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-workoutSearchRulesOnly") { return false }
        if arguments.contains("-workoutSearchModel") || arguments.contains("-searchUITests") { return true }
        #endif
        return UserDefaults.standard.bool(forKey: toolSearchKey)
    }

    struct Submission: Equatable {
        let id = UUID()
        let text: String
    }

    private(set) var query = ""
    private(set) var intent = WorkoutSearchEngine.parse("")
    private(set) var pending: Submission?
    private(set) var notice: String?

    func edit(_ text: String, now: Date = .now, calendar: Calendar = .current) {
        pending = nil
        notice = nil
        query = text
        intent = WorkoutSearchEngine.parse(text, now: now, calendar: calendar)
    }

    func submitIfEnabled(_ enabled: Bool) {
        if enabled { submit() }
    }

    func submit() {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        notice = nil
        pending = Submission(text: query)
    }

    func interpret(_ submission: Submission,
                   using interpreter: (String) async -> WorkoutInterpretation) async {
        guard pending == submission else { return }
        let response = await interpreter(submission.text)
        // A query can be edited and changed back while inference is running.
        guard !Task.isCancelled, pending == submission else { return }
        pending = nil
        switch response.status {
        case "model", "rules":
            intent = response.intent
        case "unsupported":
            notice = "Try a date, place, workout type, distance, or moving time."
        default:
            notice = "Showing results from standard search."
        }
    }

    func remove(_ filter: WorkoutSearchFilter, from applied: WorkoutSearchIntent? = nil) {
        pending = nil
        notice = nil
        if let applied { intent = applied }
        intent.filters.removeAll { $0 == filter }
    }

    func resetSorting() {
        pending = nil
        notice = nil
        intent.sort = .newest
    }

    func choosePlace(_ place: String) {
        pending = nil
        notice = nil
        // A bare city is resolved from the local history after parsing the query.
        if !intent.filters.contains(where: { if case .place = $0 { true } else { false } }),
           let city = place.split(separator: ",").first,
           intent.terms == WorkoutSearchEngine.words(String(city)) {
            intent.terms = []
        }
        intent.filters.removeAll { if case .place = $0 { true } else { false } }
        intent.filters.append(.place(place))
    }
}
