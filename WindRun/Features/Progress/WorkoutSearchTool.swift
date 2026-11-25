import Foundation
import FoundationModels

@Generable
enum SearchToolTerrain {
    case hills, uphill, downhill
}

@Generable
struct SearchToolSlope {
    var direction: SearchToolTerrain
    @Guide(description: "Exact words from the request describing this slope.")
    var source: String
}

@Generable
struct SearchWorkoutsArguments {
    @Guide(description: "Requested steep slopes. Empty for a search without a terrain requirement.", .maximumCount(2))
    var slopes: [SearchToolSlope]
    @Guide(description: "Other explicit filters or ordering, each with a separate exact source phrase. Empty if none.", .maximumCount(12))
    var filters: [SearchInterpretationClause]
}

/// A session gets exactly one read-only search. Later calls cannot broaden an empty result.
@MainActor
final class WorkoutToolRequest {
    let query: String
    let records: [WorkoutSearchRecord]
    let now: Date
    let calendar: Calendar
    let rules: WorkoutSearchIntent
    private(set) var calls = 0
    private(set) var accepted: WorkoutSearchIntent?
    private var receipt = "No search executed."

    init(query: String, records: [WorkoutSearchRecord], now: Date, calendar: Calendar) {
        self.query = query
        self.records = records
        self.now = now
        self.calendar = calendar
        rules = WorkoutSearchEngine.parse(query, now: now, calendar: calendar)
    }

    func execute(_ args: SearchWorkoutsArguments) -> String {
        guard !Task.isCancelled else { return receipt }
        calls += 1
        guard calls == 1 else { return receipt }
        receipt = "Search arguments rejected. Finish."
        guard args.slopes.count <= 2, args.filters.count <= 12 else { return receipt }
        var remainder = query
        var intent = rules
        for slope in args.slopes {
            let phrase = slope.source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty, let span = remainder.range(of: phrase, options: .caseInsensitive),
                  (span.lowerBound == remainder.startIndex || !remainder[remainder.index(before: span.lowerBound)].isLetter),
                  (span.upperBound == remainder.endIndex || !remainder[span.upperBound].isLetter),
                  let terrain = Self.grounded(slope.direction, phrase: phrase) else { return receipt }
            remainder.replaceSubrange(span, with: " | ")
            intent.append(.terrain(terrain))
        }
        if !args.filters.isEmpty {
            // Preserve literal words (including place names) within every claimed span.
            for filter in args.filters {
                let source = WorkoutSearchEngine.parse(filter.source, now: now, calendar: calendar)
                let terms = Set(source.terms).subtracting(Self.framing)
                switch filter.field {
                case .place, .notes, .title:
                    guard terms.isSubset(of: Set(WorkoutSearchEngine.words(filter.value))) else { return receipt }
                case .sport, .excludingSport, .type, .excludingType:
                    let value = filter.value.lowercased()
                    let expected: WorkoutSearchFilter
                    switch filter.field {
                    case .sport: expected = .sport(value)
                    case .excludingSport: expected = .excludingSport(value)
                    case .type: expected = .type(value)
                    default: expected = .excludingType(value)
                    }
                    guard terms.isEmpty, source.filters.contains(expected) else { return receipt }
                case .sort:
                    guard terms.isEmpty, source.sort.rawValue == filter.value.lowercased(),
                          source.sort != .newest || !Set(WorkoutSearchEngine.words(filter.source))
                            .isDisjoint(with: ["newest", "recent", "latest"]) else { return receipt }
                case .unsupported: return receipt
                case .date, .measurement: guard terms.isEmpty else { return receipt }
                }
            }
            guard let parsed = try? WorkoutIntentInterpreter.validated(args.filters, query: remainder, rules: intent,
                                                                        now: now, calendar: calendar) else { return receipt }
            intent = parsed
        } else {
            intent.terms = WorkoutSearchEngine.parse(remainder, now: now, calendar: calendar).terms
        }
        intent.terms.removeAll(where: Self.framing.contains)
        guard !intent.filters.isEmpty || !intent.terms.isEmpty || intent.sort != .newest else { return receipt }
        let result = WorkoutSearchEngine.search(intent, in: records)
        accepted = intent
        receipt = result.placeChoices.isEmpty ? "Search complete. Match count: \(result.ids.count)." : "Search complete. Place clarification required."
        return receipt
    }

    private static let framing: Set<String> = ["included", "include", "including", "contained", "containing",
                                                "featured", "featuring", "sections", "stretches", "segments"]
    private static func grounded(_ direction: SearchToolTerrain, phrase: String) -> WorkoutSearchTerrain? {
        let up: Set<String> = ["uphill", "up", "incline", "inclines", "climb", "climbs", "climbing", "climbed", "ascent", "ascents"]
        let down: Set<String> = ["downhill", "down", "decline", "declines", "descent", "descents", "descending", "descended"]
        let either: Set<String> = ["hill", "hills", "hilly", "grade", "grades", "slope", "slopes", "terrain"]
        let words = Set(WorkoutSearchEngine.words(phrase))
        let allowed = up.union(down).union(either).union(framing).union(["a", "an", "the", "steep", "sustained", "with", "of", "on"])
        guard words.isSubset(of: allowed) else { return nil }
        switch direction {
        case .uphill: return !words.isDisjoint(with: up) && words.isDisjoint(with: down) ? .uphill : nil
        case .downhill: return !words.isDisjoint(with: down) && words.isDisjoint(with: up) ? .downhill : nil
        case .hills: return !words.isDisjoint(with: either) && words.isDisjoint(with: up.union(down)) ? .hills : nil
        }
    }
}

nonisolated struct SearchWorkoutsTool: Tool {
    let name = "searchWorkouts"
    let description = "Search the user's local workout history with grounded filters and recorded terrain. A zero count is a complete answer."
    let request: WorkoutToolRequest

    func call(arguments: SearchWorkoutsArguments) async throws -> String {
        await request.execute(arguments)
    }
}

enum WorkoutToolSearch {
    static func interpret(_ text: String, records: [WorkoutSearchRecord], now: Date = .now,
                          calendar: Calendar = .current) async -> WorkoutInterpretation {
        let request = WorkoutToolRequest(query: text, records: records, now: now, calendar: calendar)
        func fallback(_ status: String, _ reason: String? = nil, attempted: Bool = false) -> WorkoutInterpretation {
            WorkoutInterpretation(intent: request.rules, status: status, usedModel: attempted, reason: reason, toolCalls: request.calls)
        }
        guard text.count <= 600 else { return fallback("unsupported", "queryLength") }
        guard !request.rules.terms.isEmpty else { return fallback("rules") }
        guard !request.rules.filters.contains(where: { if case .unsupported = $0 { true } else { false } }) else {
            return fallback("unsupported", "unsupportedFilter")
        }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return fallback("unavailable", "modelUnavailable") }
        guard model.supportsLocale(calendar.locale ?? .current) else { return fallback("unavailable", "locale") }
        guard !Task.isCancelled else { return fallback("cancelled") }
        do {
            let session = LanguageModelSession(model: model, tools: [SearchWorkoutsTool(request: request)], instructions: """
                Call searchWorkouts once to answer the workout search. Supply the exact source words for each requirement.
                Use slopes for measured steep terrain. Uphill includes climbing or ascent, downhill includes descent.
                Never infer a place or relax a constraint to get results. After the call, finish with a brief acknowledgement.
                """)
            _ = try await session.respond(to: text, options: GenerationOptions(samplingMode: .greedy, maximumResponseTokens: 512))
            guard !Task.isCancelled else { return fallback("cancelled", attempted: true) }
            guard let intent = request.accepted else {
                return fallback("failed", request.calls == 0 ? "noToolCall" : "invalidArguments", attempted: true)
            }
            return WorkoutInterpretation(intent: intent, status: "model", usedModel: true, toolCalls: request.calls)
        } catch {
            return fallback(Task.isCancelled ? "cancelled" : "failed", "generationError", attempted: true)
        }
    }
}
