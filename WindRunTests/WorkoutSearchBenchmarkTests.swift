import Compression
import CryptoKit
import Foundation
import FoundationModels
import SwiftData
import XCTest
@testable import WindRun

// Driven by scripts/search-evaluation/run.py. Only the synthetic history and query text enter
// the test process. The host scorer owns the gold file.
final class WorkoutSearchBenchmarkTests: XCTestCase {
    struct Corpus: Decodable {
        struct History: Decodable {
            let id: String
            let workouts: [Workout]
        }
        struct Workout: Decodable {
            let id: UUID
            let sport, kind, workoutType: String
            let startedAt: Date
            let distanceMeters, activeSeconds, elapsedSeconds: Double
            let title, notes: String
            let city, stateCode, countryCode: String?
            let profile: SyntheticSearchRoute?
        }
        struct Query: Decodable {
            let asOf: Date?
            let id, historyID, text: String
        }
        let now: Date
        let timeZone, locale: String
        let firstWeekday: Int
        let histories: [History]
        let queries: [Query]
    }

    struct Observation: Encodable {
        let queryID, lane, action, status: String
        var ids: [UUID]
        var slots: [String: [String]]
        var repeatIndex: Int
        var localMs, finalMs: Double
        var modelAttempted: Bool
        var additionalTerms: [String]
        var placeChoices: [String]
        var toolCalls: Int?
        var reason: String?
    }

    @MainActor
    private struct History {
        var runs: [Run] = []
        var places: [UUID: String] = [:]
        var records: [WorkoutSearchRecord] = []

        init(_ source: Corpus.History, context: ModelContext) throws {
            for row in source.workouts {
                let sport = try XCTUnwrap(WorkoutSport(rawValue: row.sport))
                let kind = try XCTUnwrap(RunKind(rawValue: row.kind))
                let run = Run(kind: kind, sport: sport, startDate: row.startedAt)
                context.insert(run)
                run.runIDValue = row.id
                row.profile?.record(on: run, meters: row.distanceMeters, seconds: row.activeSeconds)
                run.distanceMetersValue = row.distanceMeters
                run.notesValue = row.notes
                if row.workoutType == "distance" { run.goal = .distance(meters: row.distanceMeters) }
                if row.workoutType == "time" { run.goal = .time(seconds: row.activeSeconds) }
                if row.workoutType == "intervals" {
                    let plan = IntervalPlan(name: row.title, createdDate: row.startedAt)
                    context.insert(plan)
                    plan.workoutTypeValue = sport.rawValue
                    let block = plan.addBlock(repeatCount: 4)
                    block.addStep(.work, goal: .distance(meters: 400))
                    block.addStep(.recovery, goal: .time(90))
                    run.intervalPlanValue = plan
                } else if !row.title.isEmpty || kind == .coached {
                    let workout = CoachWorkout(kind: row.workoutType, dayOffset: 0)
                    context.insert(workout)
                    workout.titleValue = row.title
                    run.coachWorkoutValue = workout
                }
                if row.elapsedSeconds > row.activeSeconds {
                    run.pause(at: row.startedAt.addingTimeInterval(row.activeSeconds))
                }
                run.finish(at: row.startedAt.addingTimeInterval(row.elapsedSeconds))
                runs.append(run)
                var place: WorkoutSearchPlace?
                if let city = row.city, let state = row.stateCode {
                    place = WorkoutSearchPlace(address: "\(city), \(state)", city: city, state: state, country: row.countryCode ?? "")
                    places[row.id] = place?.searchableText
                }
                let record = WorkoutSearchRecord(run: run, place: place)
                XCTAssertEqual(record.sport, row.sport)
                XCTAssertEqual(record.type, row.workoutType)
                XCTAssertEqual(record.isCoached, row.kind == "coached")
                XCTAssertEqual(record.title, row.title)
                XCTAssertEqual(record.duration, row.activeSeconds, accuracy: 0.001)
                XCTAssertEqual(record.distance, row.distanceMeters, accuracy: 0.001)
                records.append(record)
            }
            runs.sort { $0.startDate > $1.startDate }
        }
    }

    private func corpus(_ environment: [String: String]) throws -> Corpus {
        let encoded = try XCTUnwrap(environment["WR_SEARCH_CORPUS"])
        let compressed = try XCTUnwrap(Data(base64Encoded: encoded))
        let size = try XCTUnwrap(Int(environment["WR_SEARCH_SIZE"] ?? ""))
        var decoded = Data(count: size)
        let count = decoded.withUnsafeMutableBytes { target in
            compressed.withUnsafeBytes { source in
                compression_decode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, size,
                                          source.bindMemory(to: UInt8.self).baseAddress!, compressed.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        XCTAssertEqual(count, size)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Corpus.self, from: decoded)
    }

    @MainActor
    private func slots(_ intent: WorkoutSearchIntent, calendar: Calendar) -> [String: [String]] {
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
            case .distance(let op, let v, _): (key, value) = ("distance", "\(op.rawValue):\(v)")
            case .duration(let op, let v, _): (key, value) = ("duration", "\(op.rawValue):\(v)")
            case .heartRate(let op, let v, _): (key, value) = ("heartRate", "\(op.rawValue):\(v)")
            case .climb(let op, let v, _): (key, value) = ("climb", "\(op.rawValue):\(v)")
            case .calories(let op, let v, _): (key, value) = ("calories", "\(op.rawValue):\(v)")
            case .unsupported(let v): (key, value) = ("unsupported", v)
            }
            slots[key, default: []].append(value)
        }
        slots["sort"] = [intent.sort.rawValue]
        return slots
    }

    private func elapsed(_ start: ContinuousClock.Instant) -> Double {
        let parts = start.duration(to: .now).components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
    }

    @MainActor
    func testSyntheticSearch() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["WR_SEARCH_CORPUS"] != nil, "Launched by the synthetic search evaluation runner")
        executionTimeAllowance = 7200
        let dataset = try corpus(env)
        let store = WindRunStore(inMemory: true)
        let histories = try Dictionary(uniqueKeysWithValues: dataset.histories.map {
            ($0.id, try History($0, context: store.container.mainContext))
        })
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: dataset.locale)
        calendar.firstWeekday = dataset.firstWeekday
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: dataset.timeZone))
        let lanes = Set(try XCTUnwrap(env["WR_SEARCH_LANES"]).split(separator: ","))
        let repeated = Set((env["WR_SEARCH_REPEAT"] ?? "").split(separator: ",").map(String.init))
        var observations: [Observation] = []
        let available = SystemLanguageModel.default.availability
        for pass in 0..<3 {
            for query in dataset.queries where pass == 0 || repeated.contains(query.id) {
                var history = try XCTUnwrap(histories[query.historyID])
                let now = query.asOf ?? dataset.now
                if query.asOf != nil {
                    history.records.removeAll { $0.date > now }
                    history.runs.removeAll { $0.startDate > now }
                }
                if pass == 0 && lanes.contains("legacy") {
                    let start = ContinuousClock.now
                    let result = WorkoutQuery(query.text, now: now, calendar: calendar)
                        .results(history.runs, places: history.places)
                    let ms = elapsed(start)
                    observations.append(Observation(queryID: query.id, lane: "legacy", action: result.isEmpty ? "empty" : "results",
                                                    status: "legacy", ids: result.map(\.runIDValue), slots: [:],
                                                    repeatIndex: pass, localMs: ms, finalMs: ms, modelAttempted: false, additionalTerms: [], placeChoices: []))
                }
                let start = ContinuousClock.now
                let rule = WorkoutSearchEngine.parse(query.text, now: now, calendar: calendar)
                let local = WorkoutSearchEngine.search(rule, in: history.records)
                let localMs = elapsed(start)
                func observation(_ result: WorkoutSearchResult, lane: String,
                                 status: String, attempted: Bool, ms: Double, reason: String? = nil) -> Observation {
                    let action = !result.placeChoices.isEmpty ? "clarify" : result.ids.isEmpty ? "empty" : "results"
                    return Observation(queryID: query.id, lane: lane, action: action, status: status, ids: result.ids,
                                       slots: slots(result.appliedIntent, calendar: calendar), repeatIndex: pass,
                                       localMs: localMs, finalMs: ms, modelAttempted: attempted, additionalTerms: result.appliedIntent.terms, placeChoices: result.placeChoices, reason: reason)
                }
                if pass == 0 && lanes.contains("rules") {
                    observations.append(observation(local, lane: "rules", status: "rules", attempted: false, ms: localMs))
                }
                for lane in ["toolHybrid", "rulesOnly"] where pass == 0 && lanes.contains(Substring(lane)) {
                    let timer = ContinuousClock.now
                    let screen = WorkoutSearchSession()
                    screen.edit(query.text, now: now, calendar: calendar)
                    screen.submitIfEnabled(lane == "toolHybrid")
                    var parsed = WorkoutInterpretation(intent: screen.intent, status: "rules", usedModel: false)
                    if let submission = screen.pending {
                        await screen.interpret(submission) { text in
                            parsed = await WorkoutToolSearch.interpret(text, records: history.records, now: now, calendar: calendar)
                            return parsed
                        }
                    }
                    let result = WorkoutSearchEngine.search(screen.intent, in: history.records)
                    var row = observation(result, lane: lane, status: parsed.status, attempted: parsed.usedModel,
                                          ms: elapsed(timer), reason: parsed.reason)
                    row.toolCalls = parsed.toolCalls
                    observations.append(row)
                }
                for lane in ["hybrid", "forcedModel"] where lanes.contains(Substring(lane)) {
                    let modelStart = ContinuousClock.now
                    let parsed = await WorkoutIntentInterpreter.interpret(query.text, now: now, calendar: calendar,
                                                                         forceModel: lane == "forcedModel")
                    let result = WorkoutSearchEngine.search(parsed.intent, in: history.records)
                    observations.append(observation(result, lane: lane, status: parsed.status,
                                                    attempted: parsed.usedModel, ms: localMs + elapsed(modelStart), reason: parsed.reason))
                }
            }
        }
        struct Payload: Encodable {
            let os, hardware, modelAvailability, locale, promptVersion, instructionHash: String
            let observations: [Observation]
        }
        let data = try JSONEncoder().encode(Payload(os: ProcessInfo.processInfo.operatingSystemVersionString,
                                                  hardware: env["SIMULATOR_MODEL_IDENTIFIER"] ?? "physical device",
                                                  modelAvailability: String(describing: available), locale: dataset.locale,
                                                  promptVersion: WorkoutIntentInterpreter.promptVersion,
                                                  instructionHash: SHA256.hash(data: Data(WorkoutIntentInterpreter.instructions.utf8))
                                                    .map { String(format: "%02x", $0) }.joined(),
                                                  observations: observations))
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "SyntheticSearchResults"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
