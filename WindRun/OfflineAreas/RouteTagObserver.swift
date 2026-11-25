import OSLog
import Foundation
import SwiftData
import SwiftUI

@MainActor @Observable
final class RouteSearchTerms {
    static let shared = RouteSearchTerms()
    var byRun: [UUID: String] = [:]
}

@ModelActor
actor RouteTagSource {
    func fixes(for id: UUID) throws -> [TagFix]? {
        var query = FetchDescriptor<Run>(predicate: #Predicate { $0.runIDValue == id })
        query.fetchLimit = 1
        guard let run = try modelContext.fetch(query).first, run.statusValue == .complete else { return nil }
        let pauses = (run.pausesValue ?? []).map { ($0.startDateValue, $0.endDateValue ?? .distantFuture) }
        let route = (run.routeSamplesValue ?? []).sorted { $0.timestampValue < $1.timestampValue }
        return route.map { sample in
            let time = sample.timestampValue
            return TagFix(time: time.timeIntervalSinceReferenceDate, latitude: sample.latitudeValue,
                          longitude: sample.longitudeValue, accuracy: sample.horizontalAccuracyValue,
                          paused: pauses.contains { $0.0 <= time && time < $0.1 })
        }
    }
}

/// Starts at completion or import. Returning to the foreground also retries unfinished work.
/// SwiftData objects stay in their owning context. Only plain values cross to the worker.
struct RouteTagObserver: View {
    @Environment(\.scenePhase) private var phase
    @Environment(\.modelContext) private var context
    @Query(sort: \Run.startDateValue, order: .reverse) private var runs: [Run]
    @State private var finished: [UUID: Ticket] = [:]

    @State private var foregroundRevision = 0

    private struct Ticket: Hashable {
        let id: UUID
        let points: Int
        let pauses: Int
    }

    var body: some View {
        let complete = runs.filter { $0.status == .complete }
        let tickets = complete.map { Ticket(id: $0.runIDValue, points: $0.routeSamplesValue?.count ?? 0,
                                             pauses: $0.pausesValue?.count ?? 0) }
        Color.clear.frame(width: 0, height: 0)
            .onChange(of: phase) { _, new in
                if new == .active {
                    finished.removeAll()
                    foregroundRevision += 1
                }
            }
            .task(id: Work(tickets: tickets, foregroundRevision: foregroundRevision)) {
                let ids = Set(tickets.map(\.id))
                let labels = RouteSearchTerms.shared
                labels.byRun = labels.byRun.filter { ids.contains($0.key) }
                finished = finished.filter { ids.contains($0.key) }
                do {
                    try await RouteTagWorker.shared.prune(keeping: ids)
                    let container = context.container
                    let source = await Task.detached(priority: .utility) { RouteTagSource(modelContainer: container) }.value
                    for ticket in tickets where finished[ticket.id] != ticket {
                        try Task.checkCancellation()
                        labels.byRun.removeValue(forKey: ticket.id)
                        do {
                            guard let fixes = try await source.fixes(for: ticket.id), fixes.count == ticket.points else { continue }
                            let terms = try await RouteTagWorker.shared.tag(id: ticket.id, fixes: fixes)
                            try Task.checkCancellation()
                            labels.byRun[ticket.id] = terms
                            finished[ticket.id] = ticket
                        } catch is CancellationError {
                            return
                        } catch {
                            Logger.persistence.error("Could not index a finished workout")
                        }
                    }
                } catch is CancellationError {
                    // The next foreground session or updated route resumes the last committed batch.
                } catch {
                    Logger.persistence.error("Offline route tags could not be updated")
                }
            }
    }

    private struct Work: Equatable {
        var tickets: [Ticket]
        var foregroundRevision: Int
    }
}
