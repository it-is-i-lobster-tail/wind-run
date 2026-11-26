import CoreLocation
import Foundation
import MapKit
import OSLog
import SwiftData

/// What search needs from a workout that is slow to work out: the steep stretches, climb, mean heart rate,
/// calories and the start's town. Worked out once per workout and kept by `WorkoutSearchIndex`.
struct WorkoutSearchFacts: Codable, Equatable {
    /// Changes whenever the run's route, heights or totals change, so its facts are worked out again.
    var fingerprint: String
    var terrain: Set<WorkoutSearchTerrain>
    /// Meters, from the same climb count the run detail shows. Nil when the run has no heights.
    var climb: Double?
    var heartRate: Double?
    var calories: Double?
    var place: WorkoutSearchPlace?
    /// The town shown under a workout, such as "Portland, OR".
    var city: String?
    /// True once the start has been looked up, even when there was nothing to find.
    var placeChecked = false

    init(run: Run) {
        fingerprint = Self.fingerprint(of: run)
        terrain = WorkoutSearchGrades.directions(in: run)
        climb = run.altitudeTrack.map { Run.climbAndDrop($0).gain }
        heartRate = run.heartRateStats?.mean
        calories = run.activeCaloriesValue
    }

    /// Only stored values, so this never loads the run's route or heart rate.
    static func fingerprint(of run: Run) -> String {
        ["1", run.statusValue.rawValue, String(run.distanceMetersValue),
         String(run.endDateValue?.timeIntervalSinceReferenceDate ?? 0), String(run.altitudeDataValue?.count ?? 0),
         String(run.activeCaloriesValue ?? -1)].joined(separator: "|")
    }
}

/// Search facts for every finished workout, kept in a file on this iPhone so search opens at once.
///
/// The file is left out of iCloud, device backups and every export. A workout is worked out the first time a
/// screen needs it, a few at a time so the screen stays smooth, and again only when it changes.
@MainActor @Observable
final class WorkoutSearchIndex {
    static let shared = WorkoutSearchIndex()

    private(set) var facts: [UUID: WorkoutSearchFacts] = [:]
    /// True while workouts are being worked out or their starts looked up.
    private(set) var indexing = false
    private(set) var locating = false

    private var loaded = false
    private var busy = false
    private let persists: Bool

    init(persists: Bool = !WindRunSchema.runsInMemory) {
        #if DEBUG
        self.persists = persists && !ProgressDemo.isRequested
        #else
        self.persists = persists
        #endif
    }

    func city(for id: UUID) -> String? { facts[id]?.city }

    /// Brings these runs' facts up to date. With `pruning`, runs not in the list are forgotten, so pass every
    /// finished run.
    func update(for runs: [Run], pruning: Bool = false) async {
        while busy {
            try? await Task.sleep(for: .milliseconds(50))
            if Task.isCancelled { return }
        }
        busy = true
        defer { busy = false }
        load()
        if pruning {
            let ids = Set(runs.map(\.runIDValue))
            if facts.keys.contains(where: { !ids.contains($0) }) {
                facts = facts.filter { ids.contains($0.key) }
                save()
            }
        }
        #if DEBUG
        if ProgressDemo.testsSearch && ProgressDemo.isRequested {
            demoPlaces(for: runs)
            return
        }
        #endif
        await refreshFacts(for: runs)
        await lookUpStarts(for: runs)
    }

    /// Drops a deleted run's facts straight away, so its start's address isn't kept.
    func forget(_ id: UUID) {
        load()
        guard facts.removeValue(forKey: id) != nil else { return }
        save()
    }

    private func refreshFacts(for runs: [Run]) async {
        let stale = runs.filter { run in
            run.status == .complete && facts[run.runIDValue]?.fingerprint != WorkoutSearchFacts.fingerprint(of: run)
        }
        guard !stale.isEmpty else { return }
        indexing = true
        defer { indexing = false }
        for run in stale {
            if Task.isCancelled { break }
            // A run deleted while this waited has no store any more.
            guard run.modelContext != nil, !run.isDeleted else { continue }
            var entry = WorkoutSearchFacts(run: run)
            if let old = facts[run.runIDValue], old.placeChecked {
                // An edited or synced run keeps its start, so keep the town already found.
                entry.place = old.place
                entry.city = old.city
                entry.placeChecked = old.placeChecked
            }
            facts[run.runIDValue] = entry
            // One route at a time, so the screen keeps drawing while a long history is read.
            await Task.yield()
        }
        save()
    }

    // MapKit lookups are rate limited, so each start is asked about once and the answer kept.
    private func lookUpStarts(for runs: [Run]) async {
        let unchecked = runs.filter { facts[$0.runIDValue].map { !$0.placeChecked } == true }
        guard !unchecked.isEmpty else { return }
        locating = true
        defer {
            locating = false
            save()
        }
        var nearby: [String: (WorkoutSearchPlace?, String?)] = [:]
        for run in unchecked {
            if Task.isCancelled { return }
            guard run.modelContext != nil, !run.isDeleted else { continue }
            let id = run.runIDValue
            guard let start = run.startLocation else {
                facts[id]?.placeChecked = true
                continue
            }
            let c = start.coordinate
            let key = "\(Int((c.latitude * 1000).rounded()))/\(Int((c.longitude * 1000).rounded()))"
            if let known = nearby[key] {
                facts[id]?.place = known.0
                facts[id]?.city = known.1
                facts[id]?.placeChecked = true
                continue
            }
            guard let request = MKReverseGeocodingRequest(location: start) else {
                facts[id]?.placeChecked = true
                continue
            }
            let item: MKMapItem?
            do {
                item = try await request.mapItems.first
            } catch {
                // Offline or asked too often: try the rest next time.
                Logger.persistence.info("Stopped looking up workout starts for now")
                return
            }
            let found = item.flatMap(Self.place(of:))
            nearby[key] = (found?.place, found?.city)
            guard facts[id] != nil else { continue }
            facts[id]?.place = found?.place
            facts[id]?.city = found?.city
            facts[id]?.placeChecked = true
        }
    }

    private static func place(of item: MKMapItem) -> (place: WorkoutSearchPlace, city: String?)? {
        guard let address = item.addressRepresentations?.fullAddress(includingRegion: false, singleLine: true) ?? item.name else { return nil }
        let city = item.addressRepresentations?.cityWithContext(.short) ?? item.addressRepresentations?.cityName
        let region = item.addressRepresentations?.region?.identifier
        let terms = WorkoutSearchLocations.searchAddress(address, city: city, region: region)
        let name = item.addressRepresentations?.cityName ?? ""
        let state = region == "US" ? WorkoutSearchLocations.stateCode(address, city: city) : nil
        return (WorkoutSearchPlace(address: terms, city: name, state: state ?? "", country: region ?? ""), city)
    }

    #if DEBUG
    private func demoPlaces(for runs: [Run]) {
        for (index, run) in runs.enumerated() {
            let state = index.isMultiple(of: 2) ? "ME" : "OR"
            var entry = facts[run.runIDValue] ?? WorkoutSearchFacts(run: run)
            entry.place = WorkoutSearchPlace(address: "Portland, " + state, city: "Portland", state: state, country: "US")
            entry.city = "Portland, " + state
            entry.placeChecked = true
            facts[run.runIDValue] = entry
        }
    }
    #endif

    // MARK: Storage

    private struct Stored: Codable {
        var version: Int
        var facts: [UUID: WorkoutSearchFacts]
    }

    private static let version = 1

    private static func file() throws -> URL {
        let manager = FileManager.default
        let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var folder = support.appendingPathComponent("WorkoutSearch", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        return folder.appendingPathComponent("index.json")
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard persists else { return }
        do {
            let stored = try JSONDecoder().decode(Stored.self, from: Data(contentsOf: Self.file()))
            if stored.version == Self.version { facts = stored.facts }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
        } catch {
            // A damaged or older index is rebuilt from the runs.
            Logger.persistence.error("Workout search index could not be read")
        }
    }

    private func save() {
        guard persists else { return }
        do {
            let data = try JSONEncoder().encode(Stored(version: Self.version, facts: facts))
            try data.write(to: Self.file(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Logger.persistence.error("Workout search index could not be saved")
        }
    }
}

extension WorkoutSearchRecord {
    /// Works out the route facts on the spot. Screens pass the stored facts from `WorkoutSearchIndex` instead.
    init(run: Run, place: WorkoutSearchPlace?) {
        self.init(run: run, facts: WorkoutSearchFacts(run: run))
        self.place = place
    }

    init(run: Run, facts: WorkoutSearchFacts?) {
        self.init(id: run.runIDValue, date: run.startDate, sport: run.sport.rawValue,
                  type: ProgressGroup(run)?.type.rawValue ?? run.kind.rawValue,
                  title: [run.intervalPlan?.name, run.coachWorkout?.title].compactMap { $0 }.joined(separator: " "),
                  notes: run.notesValue, distance: run.distanceMeters, duration: run.activeDuration(),
                  place: facts?.place, isCoached: run.kind == .coached, terrain: facts?.terrain,
                  climb: facts?.climb, heartRate: facts?.heartRate, calories: facts?.calories)
    }
}
