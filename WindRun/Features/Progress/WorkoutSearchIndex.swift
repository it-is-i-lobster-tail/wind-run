import CoreData
import CoreLocation
import Foundation
import MapKit
import OSLog
import SwiftData

/// What search needs from a workout that is slow to work out: the steep stretches, climb, mean heart rate,
/// calories and the places it went through. Worked out once per workout and kept by `WorkoutSearchIndex`.
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
    /// The offline pack this workout's places were worked out with, so a new pack tags it again. Nil for
    /// workouts indexed before the pack shipped.
    var placeRevision: String?
    /// True when the place came from Apple Maps, for a start outside the US. Kept across new packs, so
    /// Apple is asked about each workout once.
    var placeFromApple: Bool?
    /// The fastest time over each standard distance inside the run, in seconds, keyed by whole meters.
    var bestEfforts: [Int: Double]?
    /// The squares of about 150 m the route went through, for "like this run". Kept only in this file.
    var cells: [Int64]?

    /// Works the route facts out here and now. The index works them out away from the screen instead.
    init(run: Run) {
        self.init(run: run, route: WorkoutSearchRouteFacts.make(WorkoutSearchRouteFacts.Input(run: run)))
    }

    init(run: Run, route: WorkoutSearchRouteFacts) {
        fingerprint = Self.fingerprint(of: run)
        terrain = route.terrain
        climb = route.climb
        bestEfforts = route.bestEfforts
        cells = route.cells
        heartRate = run.heartRateStats?.mean
        calories = run.activeCaloriesValue
    }

    /// Only stored values, so this never loads the run's route or heart rate. It changes only when something
    /// the facts are worked out from changes: finishing, the distance, the end, the heights, the calories or
    /// the packed route. A changed title or note doesn't need the route read again: search reads those live.
    static func fingerprint(of run: Run) -> String {
        // "2" added best efforts and route squares, so every run is read again once.
        ["2", run.statusValue.rawValue, String(run.distanceMetersValue),
         String(run.endDateValue?.timeIntervalSinceReferenceDate ?? 0), String(run.altitudeDataValue?.count ?? 0),
         String(run.activeCaloriesValue ?? -1), String(run.routePackedCountValue ?? -1)].joined(separator: "|")
    }
}

/// What a route gives search: steep stretches, climb, best efforts and the squares it went through. Worked out
/// away from the screen, from values read out of the store first, since a long route takes a while to walk.
nonisolated struct WorkoutSearchRouteFacts: Sendable {
    var terrain: Set<WorkoutSearchTerrain>
    var climb: Double?
    var bestEfforts: [Int: Double]
    var cells: [Int64]

    /// Everything the facts need, copied out of the run. A packed route is copied as its data and unpacked
    /// away from the screen; an older run's fixes are read out of their records here.
    struct Input: Sendable {
        var packed: Data?
        var readings: [RouteReading]
        var clock: PauseClock
        var usesEstimator: Bool
        var sport: WorkoutSport
        var meters: Double
        var barometer: Data?

        @MainActor init(run: Run) {
            if run.routePackedCountValue != nil, let data = run.routeDataValue {
                packed = data
                readings = []
            } else {
                packed = nil
                readings = run.sampleReadings
            }
            clock = run.pauseClock
            usesEstimator = run.distanceMethod != nil
            sport = run.sport
            meters = run.distanceMeters
            barometer = run.altitudeDataValue
        }
    }

    static func make(_ input: Input) -> WorkoutSearchRouteFacts {
        let readings = input.packed.flatMap(PackedRoute.decode) ?? input.readings
        let fixes = Run.activeRoute(readings, clock: input.clock, usesEstimator: input.usesEstimator, sport: input.sport)
        let barometer = input.barometer.flatMap { try? JSONDecoder().decode([AltitudeSample].self, from: $0) } ?? []
        return WorkoutSearchRouteFacts(
            terrain: WorkoutSearchGrades.directions(fixes: fixes, barometer: barometer),
            climb: Run.altitudeTrack(for: fixes, barometer: barometer).map { Run.climbAndDrop($0).gain },
            bestEfforts: WorkoutSearchEfforts.best(times: fixes.map(\.time), meters: fixes.map(\.meters),
                                                   stretches: fixes.map(\.stretch), totalMeters: input.meters),
            cells: WorkoutSearchSimilarity.cells(latitudes: fixes.map(\.sample.latitudeValue),
                                                 longitudes: fixes.map(\.sample.longitudeValue)))
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
    /// True while workouts are being worked out.
    private(set) var indexing = false
    /// True while workouts are still being given places, in the background.
    private(set) var locating = false

    private var loaded = false
    private var busy = false
    private let persists: Bool
    /// The finished runs last handed over, so a save or a sync can bring just the changed ones up to date.
    @ObservationIgnored private var known: [Run] = []
    @ObservationIgnored private var changeTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(persists: Bool = !WindRunSchema.runsInMemory, places: PlaceTagger = .bundled,
         appleLookup: @escaping @MainActor (CLLocationCoordinate2D) async throws -> (WorkoutSearchPlace, String?)? = WorkoutSearchIndex.appleMapsPlace) {
        self.places = places
        self.appleLookup = appleLookup
        #if DEBUG
        self.persists = persists && !ProgressDemo.isRequested
        #else
        self.persists = persists
        #endif
        // A save here or a change from iCloud may have changed a run's route or totals. Shortly after, the
        // runs whose fingerprint changed are read again; the rest are left alone.
        let center = NotificationCenter.default
        observers = [ModelContext.didSave, .NSPersistentStoreRemoteChange].map { name in
            center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                guard let index = self else { return }
                Task { @MainActor in index.runsChanged() }
            }
        }
    }

    private func runsChanged() {
        guard loaded, !known.isEmpty else { return }
        changeTask?.cancel()
        changeTask = Task { [weak self] in
            // Saves come in bursts while a run is finished or a sync lands: wait for them to settle.
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            let runs = self.known.filter { $0.modelContext != nil && !$0.isDeleted }
            await self.update(for: runs)
        }
    }

    /// Forgets every fact and place found, deletes the file and starts again from the runs. Places found by
    /// Apple Maps for workouts outside the US are asked for again.
    func clear() async {
        placeTask?.cancel()
        placeTask = nil
        placeQueue = []
        nearby = [:]
        facts = [:]
        locating = false
        loaded = true
        if persists, let file = try? Self.file() { try? FileManager.default.removeItem(at: file) }
        let runs = known.filter { $0.modelContext != nil && !$0.isDeleted }
        if !runs.isEmpty { await update(for: runs) }
    }

    /// How much the index file takes up on this iPhone, in bytes.
    nonisolated static func fileSize() -> Int {
        guard let url = try? file() else { return 0 }
        return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
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
        let finished = runs.filter { $0.status == .complete }
        if pruning || known.isEmpty { known = finished }
        else {
            let have = Set(known.map(\.runIDValue))
            known += finished.filter { !have.contains($0.runIDValue) }
        }
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
        schedulePlaces(for: runs)
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
            // The store is read here; walking the route happens away from the screen.
            let input = WorkoutSearchRouteFacts.Input(run: run)
            let route = await Task.detached(priority: .utility) { WorkoutSearchRouteFacts.make(input) }.value
            guard run.modelContext != nil, !run.isDeleted else { continue }
            var entry = WorkoutSearchFacts(run: run, route: route)
            if let old = facts[run.runIDValue], old.placeChecked {
                // An edited or synced run keeps its start, so keep the town already found until its places
                // are worked out again from the new route.
                entry.place = old.place
                entry.city = old.city
                entry.placeChecked = old.placeChecked
                entry.placeFromApple = old.placeFromApple
            }
            facts[run.runIDValue] = entry
            // One route at a time, so the screen keeps drawing while a long history is read.
            await Task.yield()
        }
        save()
    }

    // MARK: Places

    /// Workouts still to be given places, newest first.
    @ObservationIgnored private var placeQueue: [Run] = []
    @ObservationIgnored private var placeTask: Task<Void, Never>?
    /// Set when Apple Maps refused a lookup, so the rest wait for the next launch.
    @ObservationIgnored private var appleRefused = false
    /// Apple's answers this session, by the start rounded to about 100 m, so runs from the same spot are
    /// asked about once. Never saved.
    @ObservationIgnored private var nearby: [String: (WorkoutSearchPlace?, String?)] = [:]
    private let places: PlaceTagger
    private let appleLookup: @MainActor (CLLocationCoordinate2D) async throws -> (WorkoutSearchPlace, String?)?
    /// Saves after this many workouts, so a long first pass that is cut short keeps most of its work.
    private nonisolated static let saveEvery = 10
    /// The pause between two workouts, so tagging never keeps the processor busy.
    nonisolated static let pauseBetween: Duration = .milliseconds(150)
    /// How long to wait before checking again when tagging has to wait, such as on a low battery mid-run.
    nonisolated static let waitRetry: Duration = .seconds(300)

    /// The pack revision workouts should be tagged with. "none" when this build has no pack.
    private var wantedRevision: String { places.revision ?? "none" }

    private func needsPlaces(_ entry: WorkoutSearchFacts) -> Bool {
        !entry.placeChecked || entry.placeRevision != wantedRevision
    }

    /// Queues the workouts that still need places, newest first, and starts tagging in the background if it
    /// isn't already going. Nothing waits for it: it goes at background priority, a workout at a time, and
    /// picks up where it left off on the next launch.
    private func schedulePlaces(for runs: [Run]) {
        let queued = Set(placeQueue.map(\.runIDValue))
        let waiting = runs.filter { run in
            guard let entry = facts[run.runIDValue], !queued.contains(run.runIDValue) else { return false }
            return needsPlaces(entry)
        }
        guard !waiting.isEmpty else { return }
        placeQueue.append(contentsOf: waiting)
        placeQueue.sort { $0.startDate > $1.startDate }
        locating = true
        guard placeTask == nil else { return }
        placeTask = Task.detached(priority: .background) { [weak self] in
            await self?.tagQueuedPlaces()
        }
    }

    /// Starts from facts saved by another index, as a later launch would. For tests.
    func restore(_ saved: [UUID: WorkoutSearchFacts]) {
        loaded = true
        facts = saved
    }

    /// Waits until every queued workout has its places. For tests.
    func placesSettled() async {
        await placeTask?.value
    }

    nonisolated private func tagQueuedPlaces() async {
        var sinceSave = 0
        while !Task.isCancelled {
            if let wait = await PlaceTaggingGate.wait() {
                await placesWait(wait)
                try? await Task.sleep(for: Self.waitRetry)
                continue
            }
            guard let job = await nextPlaceJob() else { break }
            let found: RoutePlaces?
            do {
                found = try await places.places(for: job.fixes)
            } catch {
                await placesFailed()
                found = nil
            }
            await finish(job, offline: found)
            sinceSave += 1
            if sinceSave >= Self.saveEvery {
                sinceSave = 0
                await save()
            }
            try? await Task.sleep(for: Self.pauseBetween)
        }
        await placesDone()
    }

    private struct PlaceJob: Sendable {
        var id: UUID
        var fixes: [PlaceFix]
        var start: CLLocationCoordinate2D?
    }

    /// The next workout to tag, with its route copied out of the store.
    private func nextPlaceJob() -> PlaceJob? {
        while !placeQueue.isEmpty {
            let run = placeQueue.removeFirst()
            // A run deleted while this waited has no store any more.
            guard run.modelContext != nil, !run.isDeleted, let entry = facts[run.runIDValue], needsPlaces(entry) else {
                continue
            }
            // Each fix read once, from the packed route when there is one, and pauses found by binary search.
            let clock = run.pauseClock
            let readings = run.routeReadings
            let fixes = readings.map { sample in
                PlaceFix(latitude: sample.latitudeValue, longitude: sample.longitudeValue,
                         accuracy: sample.horizontalAccuracyValue, paused: clock.contains(sample.timestamp))
            }
            return PlaceJob(id: run.runIDValue, fixes: fixes, start: Run.startLocation(in: readings)?.coordinate)
        }
        // Done here rather than after the loop, so a workout queued from now on starts a new pass.
        placeTask = nil
        locating = false
        return nil
    }

    private func finish(_ job: PlaceJob, offline: RoutePlaces?) async {
        guard facts[job.id] != nil else { return }
        let revision = wantedRevision
        if let offline, offline.inUS {
            facts[job.id]?.place = offline.searchPlace
            facts[job.id]?.city = offline.displayCity
            facts[job.id]?.placeFromApple = false
            facts[job.id]?.placeChecked = true
            facts[job.id]?.placeRevision = revision
            return
        }
        guard let start = job.start else {
            // No route, so there is no place.
            facts[job.id]?.place = nil
            facts[job.id]?.city = nil
            facts[job.id]?.placeChecked = true
            facts[job.id]?.placeRevision = revision
            return
        }
        if facts[job.id]?.placeFromApple == true, facts[job.id]?.placeChecked == true {
            // Outside the US and already asked once: keep Apple's answer with the new pack.
            facts[job.id]?.placeRevision = revision
            return
        }
        guard !appleRefused else { return }
        let key = "\(Int((start.latitude * 1000).rounded()))/\(Int((start.longitude * 1000).rounded()))"
        let answer: (WorkoutSearchPlace?, String?)
        if let known = nearby[key] {
            answer = known
        } else {
            do {
                // Never the start itself: a random point 50 to 150 m away.
                let found = try await appleLookup(StartLookupPoint.near(start))
                answer = (found?.0, found?.1)
                nearby[key] = answer
            } catch {
                // Offline or asked too often: try the rest on the next launch.
                Logger.persistence.info("Stopped looking up workout starts for now")
                appleRefused = true
                return
            }
        }
        guard facts[job.id] != nil else { return }
        facts[job.id]?.place = answer.0
        facts[job.id]?.city = answer.1
        facts[job.id]?.placeFromApple = true
        facts[job.id]?.placeChecked = true
        facts[job.id]?.placeRevision = revision
    }

    private func placesWait(_ wait: PlaceTaggingGate.Wait) {
        Logger.persistence.info("Workout places wait: \(String(describing: wait), privacy: .public)")
        save()
    }

    private func placesFailed() {
        Logger.persistence.error("Workout places could not be read from the offline pack")
    }

    private func placesDone() {
        save()
    }

    /// Asks Apple Maps for the town at a point. Only used for starts outside the offline pack.
    static func appleMapsPlace(at point: CLLocationCoordinate2D) async throws -> (WorkoutSearchPlace, String?)? {
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: point.latitude, longitude: point.longitude)) else {
            return nil
        }
        return try await request.mapItems.first.flatMap(place(of:))
    }

    private static func place(of item: MKMapItem) -> (WorkoutSearchPlace, String?)? {
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

    nonisolated private static func file() throws -> URL {
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
                  climb: facts?.climb, heartRate: facts?.heartRate, calories: facts?.calories,
                  timeZone: run.recordedTimeZone, bestEfforts: facts?.bestEfforts, cells: facts?.cells)
    }
}
