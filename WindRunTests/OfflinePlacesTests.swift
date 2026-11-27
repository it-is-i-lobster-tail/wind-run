import CoreLocation
import Foundation
import Testing
@testable import WindRun

/// A small made-up pack in the same layout `scripts/offline_areas/build.py` writes, so these tests don't
/// need the real one.
enum TestAreaPack {
    struct Area {
        var kind: String
        var name: String
        var region = ""
        /// Polygons, each a list of rings of (longitude, latitude).
        var polygons: [[[(Double, Double)]]]
    }

    static func box(west: Double, south: Double, east: Double, north: Double) -> [[(Double, Double)]] {
        [[(west, south), (east, south), (east, north), (west, north), (west, south)]]
    }

    static func encode(_ polygons: [[[(Double, Double)]]]) -> Data {
        var out = Data()
        func varint(_ value: UInt64) {
            var value = value
            repeat {
                var byte = UInt8(value & 0x7F)
                value >>= 7
                if value != 0 { byte |= 0x80 }
                out.append(byte)
            } while value != 0
        }
        func zigzag(_ value: Int64) -> UInt64 { UInt64(bitPattern: (value << 1) ^ (value >> 63)) }
        varint(UInt64(polygons.count))
        for rings in polygons {
            varint(UInt64(rings.count))
            for ring in rings {
                varint(UInt64(ring.count))
                var px: Int64 = 0, py: Int64 = 0
                for (x, y) in ring {
                    let qx = Int64((x * AreaGeometry.scale).rounded()), qy = Int64((y * AreaGeometry.scale).rounded())
                    varint(zigzag(qx - px))
                    varint(zigzag(qy - py))
                    px = qx
                    py = qy
                }
            }
        }
        return out
    }

    static func make(_ areas: [Area], revision: String = "test-1", format: String = AreaPack.format) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        let db = try AreaDatabase(url, writable: true)
        try db.exec("""
            CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE area(kind TEXT NOT NULL, name TEXT NOT NULL, region TEXT NOT NULL, geometry BLOB NOT NULL);
            CREATE VIRTUAL TABLE bounds USING rtree(rowid, west, east, south, north);
            """)
        try db.exec("INSERT INTO meta VALUES('format', '\(format)'), ('digest', '\(revision)'), ('release', 'test')")
        for (index, area) in areas.enumerated() {
            let insert = try db.statement("INSERT INTO area(rowid, kind, name, region, geometry) VALUES(?, ?, ?, ?, ?)")
            insert.bind(index + 1, 1)
            insert.bind(area.kind, 2)
            insert.bind(area.name, 3)
            insert.bind(area.region, 4)
            insert.bind(encode(area.polygons), 5)
            _ = try insert.step()
            let points = area.polygons.flatMap { $0[0] }
            let bounds = try db.statement("INSERT INTO bounds VALUES(?, ?, ?, ?, ?)")
            bounds.bind(index + 1, 1)
            bounds.bind(points.map(\.0).min()!, 2)
            bounds.bind(points.map(\.0).max()!, 3)
            bounds.bind(points.map(\.1).min()!, 4)
            bounds.bind(points.map(\.1).max()!, 5)
            _ = try bounds.step()
        }
        return url
    }

    /// Made-up Portland: Oregon, the city, a neighborhood around home and a park to the west.
    static func portland(revision: String = "test-1") throws -> URL {
        try make([
            Area(kind: "state", name: "Oregon", region: "US-OR", polygons: [box(west: -124, south: 42, east: -116, north: 46)]),
            Area(kind: "city", name: "Portland", region: "US-OR", polygons: [box(west: -122.84, south: 45.43, east: -122.47, north: 45.65)]),
            Area(kind: "neighborhood", name: "Pearl District", polygons: [box(west: -122.69, south: 45.52, east: -122.67, north: 45.54)]),
            Area(kind: "park", name: "Forest Park", polygons: [box(west: -122.80, south: 45.53, east: -122.73, north: 45.60)])
        ], revision: revision)
    }
}

struct OfflinePlacesTests {
    /// Home, in the Pearl District.
    static let home = (latitude: 45.530, longitude: -122.680)

    /// Fixes heading west from home into Forest Park and back, one about every 30 m.
    static func outAndBack(from start: (latitude: Double, longitude: Double) = home, westKilometers: Double = 6) -> [PlaceFix] {
        let step = 0.03 / (111.32 * cos(start.latitude * .pi / 180))
        let count = Int(westKilometers / 0.03)
        let out = (0...count).map { PlaceFix(latitude: start.latitude, longitude: start.longitude - Double($0) * step, accuracy: 5, paused: false) }
        return out + out.reversed()
    }

    @Test func outlinesHaveHolesAndSeveralParts() throws {
        let data = TestAreaPack.encode([
            [[(0, 0), (4, 0), (4, 4), (0, 4), (0, 0)], [(1, 1), (3, 1), (3, 3), (1, 3), (1, 1)]],
            [[(8, 8), (9, 8), (9, 9), (8, 9), (8, 8)]]
        ])
        let shape = try AreaGeometry(data)
        #expect(shape.contains(longitude: 0.5, latitude: 2))
        #expect(!shape.contains(longitude: 2, latitude: 2))
        #expect(shape.contains(longitude: 8.5, latitude: 8.5))
        #expect(!shape.contains(longitude: 7, latitude: 7))
        #expect(throws: AreaError.self) { try AreaGeometry(data.prefix(data.count - 1)) }
    }

    @Test func aPackInAnotherLayoutIsRefused() throws {
        let url = try TestAreaPack.make([], format: "1")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: AreaError.self) { try AreaPack(url: url) }
    }

    @Test func routeGetsEveryPlaceItWentThroughButNotHome() throws {
        let url = try TestAreaPack.portland()
        defer { try? FileManager.default.removeItem(at: url) }
        let pack = try AreaPack(url: url)
        let found = try #require(try RoutePlaces.of(Self.outAndBack(), pack: pack))
        #expect(found.inUS)
        // The first point out of the zone is still in the Pearl District, about 250 m west of home.
        #expect(Set(found.start.map(\.name)) == ["Oregon", "Portland", "Pearl District"])
        #expect(found.passed.map(\.name) == ["Forest Park"])
        let place = try #require(found.searchPlace)
        #expect(place.city == "Portland")
        #expect(place.state == "OR")
        #expect(place.passed == ["Forest Park"])
        #expect(found.displayCity == "Portland, OR")
        #expect(place.matchesName("Pearl District"))
        #expect(place.matchesName("Oregon"))
        #expect(!place.matchesName("Forest Park"))
        #expect(place.passesThrough("Forest Park"))
    }

    @Test func noPlaceComesFromInsideThePrivacyZone() throws {
        let url = try TestAreaPack.portland()
        defer { try? FileManager.default.removeItem(at: url) }
        let pack = try AreaPack(url: url)
        // 200 m out and back: every point is within 250 m of the start and the end.
        let found = try #require(try RoutePlaces.of(Self.outAndBack(westKilometers: 0.2), pack: pack))
        #expect(found.inUS)
        #expect(found.start.isEmpty)
        #expect(found.passed.isEmpty)
        #expect(found.searchPlace == nil)

        // A run that ends inside Forest Park never tags the park from its last 250 m.
        let oneWay = Array(Self.outAndBack(westKilometers: 4.0).prefix(Int(4.0 / 0.03) + 1))
        let parkEdge = -122.73
        let ended = try #require(try RoutePlaces.of(oneWay, pack: pack))
        #expect(oneWay.last!.longitude < parkEdge)
        let lastTagged = oneWay.filter { $0.location.distance(from: oneWay.last!.location) > RoutePlaces.privacyZone + 5 }
        #expect(ended.passed.contains { $0.name == "Forest Park" } == (lastTagged.last!.longitude < parkEdge))
        #expect(RoutePlaces.privacyZone == RunExport.privacyZoneMeters)
    }

    @Test func pausedAndInaccurateFixesAreSkipped() throws {
        let url = try TestAreaPack.portland()
        defer { try? FileManager.default.removeItem(at: url) }
        let pack = try AreaPack(url: url)
        let fixes = Self.outAndBack().map { fix in
            var fix = fix
            // Everything in the park is paused or blurry.
            if fix.longitude < -122.73 { fix.paused = fix.longitude < -122.76; fix.accuracy = fix.paused ? 5 : 80 }
            return fix
        }
        let found = try #require(try RoutePlaces.of(fixes, pack: pack))
        #expect(found.passed.isEmpty)
    }

    @Test func aStartOutsideThePackIsNotInTheUS() throws {
        let url = try TestAreaPack.portland()
        defer { try? FileManager.default.removeItem(at: url) }
        let pack = try AreaPack(url: url)
        let found = try #require(try RoutePlaces.of(Self.outAndBack(from: (49.28, -123.12)), pack: pack))
        #expect(!found.inUS)
        #expect(found.searchPlace == nil)
        #expect(try RoutePlaces.of([], pack: pack) == nil)
    }

    @Test func appleIsAskedAboutAPointFiftyToOneHundredFiftyMetersAway() {
        let start = CLLocationCoordinate2D(latitude: 51.5007, longitude: -0.1246)
        var distances: [Double] = []
        for _ in 0..<500 {
            let point = StartLookupPoint.near(start)
            distances.append(CLLocation(latitude: point.latitude, longitude: point.longitude)
                .distance(from: CLLocation(latitude: start.latitude, longitude: start.longitude)))
        }
        #expect(distances.allSatisfy { (49.5...150.5).contains($0) })
        // Spread over the range, not one fixed offset.
        #expect(distances.min()! < 70 && distances.max()! > 130)
        // Near the date line the longitude stays in range.
        let east = StartLookupPoint.near(CLLocationCoordinate2D(latitude: 0, longitude: 179.9995))
        #expect((-180...180).contains(east.longitude))
    }

    @Test @MainActor func taggingWaitsDuringARunOnHalfABattery() {
        #expect(PlaceTaggingGate.wait(runUnderWay: true, batteryLevel: 0.5, lowPowerMode: false, thermal: .nominal) == .runOnLowBattery)
        #expect(PlaceTaggingGate.wait(runUnderWay: true, batteryLevel: 0.2, lowPowerMode: false, thermal: .nominal) == .runOnLowBattery)
        #expect(PlaceTaggingGate.wait(runUnderWay: true, batteryLevel: 0.51, lowPowerMode: false, thermal: .nominal) == nil)
        #expect(PlaceTaggingGate.wait(runUnderWay: false, batteryLevel: 0.2, lowPowerMode: false, thermal: .nominal) == nil)
        // Unknown, as in the simulator.
        #expect(PlaceTaggingGate.wait(runUnderWay: true, batteryLevel: -1, lowPowerMode: false, thermal: .nominal) == nil)
        #expect(PlaceTaggingGate.wait(runUnderWay: false, batteryLevel: 1, lowPowerMode: true, thermal: .nominal) == .lowPowerMode)
        #expect(PlaceTaggingGate.wait(runUnderWay: false, batteryLevel: 1, lowPowerMode: false, thermal: .serious) == .hot)
    }

    @Test @MainActor func aStartThatPassedThroughRanksBelowOneThatStartedThere() {
        let started = WorkoutSearchRecord(id: UUID(), date: .now, sport: "running", type: "free", title: "", notes: "",
                                          distance: 5_000, duration: 1_500,
                                          place: WorkoutSearchPlace(address: "Forest Park, Portland, OR", city: "Portland", state: "OR", country: "US"))
        let through = WorkoutSearchRecord(id: UUID(), date: .now.addingTimeInterval(-86_400), sport: "running", type: "free", title: "",
                                          notes: "", distance: 5_000, duration: 1_500,
                                          place: WorkoutSearchPlace(address: "Pearl District, Portland, OR", city: "Portland", state: "OR",
                                                                    country: "US", passed: ["Forest Park"]))
        let elsewhere = WorkoutSearchRecord(id: UUID(), date: .now.addingTimeInterval(-2 * 86_400), sport: "running", type: "free", title: "",
                                            notes: "", distance: 5_000, duration: 1_500,
                                            place: WorkoutSearchPlace(address: "Pearl District, Portland, OR", city: "Portland", state: "OR", country: "US"))
        let result = WorkoutSearchEngine.search(WorkoutSearchEngine.parse("runs in Forest Park"), in: [through, elsewhere, started])
        #expect(result.ids == [started.id, through.id])
    }
}

@MainActor
struct OfflinePlacesIndexTests {
    private let container = WindRunSchema.makeContainer(inMemory: true)

    private func run(startingDaysAgo days: Double, from start: (latitude: Double, longitude: Double)) -> Run {
        let date = Date.now.addingTimeInterval(-days * 86_400)
        let run = Run(startDate: date)
        container.mainContext.insert(run)
        for (second, fix) in OfflinePlacesTests.outAndBack(from: start).enumerated() {
            run.record(RouteSample(timestamp: date.addingTimeInterval(Double(second) * 10), latitude: fix.latitude,
                                   longitude: fix.longitude, altitude: 10, horizontalAccuracy: 5, verticalAccuracy: 4))
        }
        run.finish(at: date.addingTimeInterval(4_000))
        return run
    }

    @Test func usRunsAreTaggedOfflineAndOthersAskAppleOnceNewestFirst() async throws {
        let url = try TestAreaPack.portland()
        defer { try? FileManager.default.removeItem(at: url) }
        var asked: [CLLocationCoordinate2D] = []
        let index = WorkoutSearchIndex(persists: false, places: PlaceTagger(url: url)) { point in
            asked.append(point)
            return (WorkoutSearchPlace(address: "Vancouver, BC", city: "Vancouver", state: "", country: "CA"), "Vancouver, BC")
        }
        let portland = run(startingDaysAgo: 3, from: OfflinePlacesTests.home)
        let older = run(startingDaysAgo: 10, from: (49.28, -123.12))
        let newer = run(startingDaysAgo: 1, from: (45.42, -75.69))
        await index.update(for: [older, portland, newer], pruning: true)
        await index.placesSettled()

        let tagged = try #require(index.facts[portland.runID])
        #expect(tagged.city == "Portland, OR")
        #expect(tagged.place?.passed == ["Forest Park"])
        #expect(tagged.placeFromApple == false)
        #expect(tagged.placeRevision == "test-1")

        // Only the two runs outside the pack were looked up, the newer one first, never at the start itself.
        #expect(asked.count == 2)
        let newerStart = try #require(newer.startLocation)
        let olderStart = try #require(older.startLocation)
        let first = CLLocation(latitude: asked[0].latitude, longitude: asked[0].longitude)
        let second = CLLocation(latitude: asked[1].latitude, longitude: asked[1].longitude)
        #expect((49.5...150.5).contains(first.distance(from: newerStart)))
        #expect((49.5...150.5).contains(second.distance(from: olderStart)))
        #expect(index.facts[older.runID]?.placeFromApple == true)
        #expect(index.facts[older.runID]?.city == "Vancouver, BC")

        // Indexing again asks nothing.
        await index.update(for: [older, portland, newer])
        await index.placesSettled()
        #expect(asked.count == 2)
        #expect(index.locating == false)
    }

    @Test func aNewPackTagsAgainButKeepsApplesAnswers() async throws {
        let first = try TestAreaPack.portland(revision: "test-1")
        let second = try TestAreaPack.portland(revision: "test-2")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        var asked = 0
        let lookup: @MainActor (CLLocationCoordinate2D) async throws -> (WorkoutSearchPlace, String?)? = { _ in
            asked += 1
            return (WorkoutSearchPlace(address: "Ottawa, ON", city: "Ottawa", state: "", country: "CA"), "Ottawa, ON")
        }
        let portland = run(startingDaysAgo: 3, from: OfflinePlacesTests.home)
        let ottawa = run(startingDaysAgo: 1, from: (45.42, -75.69))
        let before = WorkoutSearchIndex(persists: false, places: PlaceTagger(url: first), appleLookup: lookup)
        await before.update(for: [portland, ottawa])
        await before.placesSettled()
        #expect(asked == 1)

        // The same facts, read by a build with a newer pack.
        let after = WorkoutSearchIndex(persists: false, places: PlaceTagger(url: second), appleLookup: lookup)
        after.restore(before.facts)
        await after.update(for: [portland, ottawa])
        await after.placesSettled()
        #expect(asked == 1)
        #expect(after.facts[portland.runID]?.placeRevision == "test-2")
        #expect(after.facts[ottawa.runID]?.placeRevision == "test-2")
        #expect(after.facts[ottawa.runID]?.city == "Ottawa, ON")
    }

    @Test func appleRefusingStopsLookupsUntilNextLaunch() async throws {
        let url = try TestAreaPack.portland()
        defer { try? FileManager.default.removeItem(at: url) }
        struct Refused: Error {}
        var asked = 0
        let index = WorkoutSearchIndex(persists: false, places: PlaceTagger(url: url)) { _ in
            asked += 1
            throw Refused()
        }
        let runs = [run(startingDaysAgo: 1, from: (45.42, -75.69)), run(startingDaysAgo: 2, from: (49.28, -123.12))]
        await index.update(for: runs)
        await index.placesSettled()
        #expect(asked == 1)
        #expect(runs.allSatisfy { index.facts[$0.runID]?.placeChecked == false })
    }
}

/// Checks on the real pack. They run wherever `scripts/offline_areas/fetch.sh` put it in the app, as CI does.
struct BundledAreaPackTests {
    static var hasPack: Bool { Bundle.main.url(forResource: AreaPack.fileName, withExtension: "sqlite") != nil }

    @Test(.enabled(if: hasPack)) func knownPlacesLandInTheRightAreas() throws {
        let pack = try #require(AreaPack.bundled())
        let park = try pack.areas(latitude: 37.7694, longitude: -122.4862)
        #expect(park.contains { $0.kind == .park && $0.name == "Golden Gate Park" })
        #expect(park.contains { $0.kind == .state && $0.name == "California" })
        let oakland = try pack.areas(latitude: 37.8044, longitude: -122.2711)
        #expect(oakland.contains { $0.kind == .city && $0.name == "Oakland" && $0.region == "US-CA" })
        #expect(try pack.areas(latitude: 49.30, longitude: -123.14).isEmpty)
    }

    @Test(.enabled(if: hasPack)) func packStaysUnderFortyMegabytes() throws {
        let url = try #require(Bundle.main.url(forResource: AreaPack.fileName, withExtension: "sqlite"))
        let size = try #require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        #expect(size < 40 * 1024 * 1024)
    }

    @Test(.enabled(if: hasPack)) func aTwoHourRouteIsTaggedQuickly() throws {
        let pack = try #require(AreaPack.bundled())
        // About 2 hours at one fix a second through San Francisco.
        let fixes = (0..<7_200).map { i in
            PlaceFix(latitude: 37.70 + Double(i) * 0.000_01, longitude: -122.50 + Double(i) * 0.000_02, accuracy: 5, paused: false)
        }
        _ = try RoutePlaces.of(Array(fixes.prefix(100)), pack: pack)
        let clock = ContinuousClock()
        let took = try clock.measure { _ = try RoutePlaces.of(fixes, pack: pack) }
        // The doc's target is 50 ms on an iPhone 15; the simulator on a CI runner gets more room.
        #expect(took < .milliseconds(500))
    }
}
