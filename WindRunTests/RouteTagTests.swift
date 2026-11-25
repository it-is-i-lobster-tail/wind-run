import Foundation
import Testing
@testable import WindRun

struct RouteTagTests {
    @Test func polygonHolesAreOutsideAndMultiPolygonIsAUnion() throws {
        var data = Data()
        func write<T>(_ value: T) { withUnsafeBytes(of: value) { data.append(contentsOf: $0) } }
        func polygon(_ rings: [[(Double, Double)]]) {
            write(UInt8(1)); write(UInt32(3).littleEndian); write(UInt32(rings.count).littleEndian)
            for ring in rings {
                write(UInt32(ring.count).littleEndian)
                for (x,y) in ring { write(x.bitPattern.littleEndian); write(y.bitPattern.littleEndian) }
            }
        }
        write(UInt8(1)); write(UInt32(6).littleEndian); write(UInt32(2).littleEndian)
        polygon([[(0,0),(4,0),(4,4),(0,4),(0,0)], [(1,1),(3,1),(3,3),(1,3),(1,1)]])
        polygon([[(8,8),(9,8),(9,9),(8,9),(8,8)]])
        let geometry = try AreaGeometry(data)
        #expect(geometry.contains(x: 0.5, y: 2))
        #expect(!geometry.contains(x: 2, y: 2))
        #expect(geometry.contains(x: 8.5, y: 8.5))
        #expect(!geometry.contains(x: 7, y: 7))
    }

    @Test func bundledFullResolutionAreasOverlap() throws {
        let catalog = try AreaCatalog()
        let areas = try catalog.areas(longitude: -122.48, latitude: 37.77)
        #expect(areas.contains { $0.kind == "park" && $0.name == "Golden Gate Park" })
        let oakland = try catalog.areas(longitude: -122.2711, latitude: 37.8044)
        #expect(oakland.contains { $0.kind == "city" && $0.name == "Oakland" && $0.region == "US-CA" })
        #expect(areas.contains { $0.kind == "state" && $0.name == "California" })
        #expect(try catalog.areas(longitude: -123.14, latitude: 49.30).isEmpty)
    }

    @Test func resumeThenInvalidatePointMemberships() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let catalog = try AreaCatalog()
        // Fictional route with a mid-run return to the start, a pause, and a poor GPS fix.
        let fixes = (0..<70).map { i in
            let lon: Double = [0,40].contains(i) ? -122.51 : (i == 69 ? -122.45 : -122.48)
            return TagFix(time: Double(i), latitude: 37.77, longitude: lon, accuracy: i == 42 ? 200 : 5, paused: i == 41)
        }
        do {
            let initial = try RouteTagFile(url: url, revision: "one")
            try initial.tagNextBatch(in: fixes, using: catalog)
            #expect(initial.next == 64)
        }
        let resumed = try RouteTagFile(url: url, revision: "one")
        #expect(resumed.next == 64)
        try resumed.tagNextBatch(in: fixes, using: catalog)
        #expect(resumed.next == 70)
        #expect(try resumed.searchTerms().contains("Golden Gate Park"))
        let hidden = try resumed.db.statement("SELECT COUNT(*) FROM hits WHERE point IN (0,40,41,42,69)")
        #expect(try hidden.step() && hidden.integer(0) == 0)
        hidden.reset()
        let final = try resumed.db.statement("SELECT COUNT(*) FROM hits WHERE point=68")
        #expect(try final.step() && final.integer(0) > 0)
        final.reset()
        let replaced = try RouteTagFile(url: url, revision: "changed")
        #expect(replaced.next == 0)
        #expect(try replaced.searchTerms().isEmpty)
    }
}
