import CoreLocation
import CryptoKit
import Foundation

nonisolated struct TagFix: Sendable {
    let time: Double
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let paused: Bool

    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    var valid: Bool { CLLocationCoordinate2DIsValid(.init(latitude: latitude, longitude: longitude)) }
}

/// Each database belongs to one completed workout and lives outside the mirrored store.
/// Point memberships and the next point to process commit in the same transaction.
nonisolated final class RouteTagFile {
    let db: AreaDatabase
    private(set) var next: Int

    init(url: URL, revision: String) throws {
        db = try AreaDatabase(url, writable: true)
        try db.exec("""
            CREATE TABLE IF NOT EXISTS job(revision TEXT PRIMARY KEY, next INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS names(area TEXT PRIMARY KEY, kind TEXT, name TEXT, region TEXT);
            CREATE TABLE IF NOT EXISTS hits(point INTEGER, time REAL, area TEXT, PRIMARY KEY(point,area)) WITHOUT ROWID;
            """)
        let job = try db.statement("SELECT revision,next FROM job")
        if try job.step(), job.text(0) == revision {
            next = job.integer(1)
        } else {
            job.reset()
            next = 0
            try db.transaction {
                try db.exec("DELETE FROM hits; DELETE FROM names; DELETE FROM job")
                let insert = try db.statement("INSERT INTO job VALUES(?,0)")
                insert.bind(revision, 1)
                _ = try insert.step()
            }
        }
    }

    func append(through end: Int, hits: [(Int, Double, RouteArea)]) throws {
        try db.transaction {
            let name = try db.statement("INSERT OR IGNORE INTO names VALUES(?,?,?,?)")
            let hit = try db.statement("INSERT INTO hits VALUES(?,?,?)")
            for (index, time, area) in hits {
                name.reset()
                for (i, value) in [area.id,area.kind,area.name,area.region].enumerated() {
                    name.bind(value, Int32(i + 1))
                }
                _ = try name.step()
                hit.reset()
                hit.bind(index, 1)
                hit.bind(time, 2)
                hit.bind(area.id, 3)
                _ = try hit.step()
            }
            let update = try db.statement("UPDATE job SET next=?")
            update.bind(end, 1)
            _ = try update.step()
        }
        next = end
    }

    func tagNextBatch(in fixes: [TagFix], using catalog: AreaCatalog) throws {
        guard next < fixes.count, let start = fixes.first, let end = fixes.last else { return }
        let stop = min(next + 64, fixes.count)
        guard start.valid, end.valid else {
            try append(through: stop, hits: [])
            return
        }
        let firstLocation = start.location, lastLocation = end.location
        var hits: [(Int, Double, RouteArea)] = []
        for i in next..<stop {
            try Task.checkCancellation()
            let fix = fixes[i]
            guard fix.valid, !fix.paused, (0...50).contains(fix.accuracy) else { continue }
            let location = fix.location
            let margin = RunExport.privacyZoneMeters + fix.accuracy
            guard location.distance(from: firstLocation) > margin,
                  location.distance(from: lastLocation) > margin else { continue }
            for area in try catalog.areas(longitude: fix.longitude, latitude: fix.latitude) {
                hits.append((i, fix.time, area))
            }
        }
        try append(through: stop, hits: hits)
    }

    func searchTerms() throws -> String {
        let query = try db.statement("SELECT DISTINCT name,region,kind FROM names ORDER BY name,region,kind")
        var terms = Set<String>()
        while try query.step() {
            terms.insert(query.text(0))
            terms.insert(query.text(1))
            terms.insert(query.text(2))
        }
        return terms.sorted().joined(separator: " ")
    }
}

actor RouteTagWorker {
    static let shared = RouteTagWorker()
    private var catalog: AreaCatalog?
    private func directory() throws -> URL {
        let files = FileManager.default
        var url = try files.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("RoutePointTags", isDirectory: true)
        try files.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        return url
    }

    func prune(keeping ids: Set<UUID>) throws {
        try Task.checkCancellation()
        let dir = try directory()
        for file in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            let prefix = String(file.lastPathComponent.prefix(36))
            if let id = UUID(uuidString: prefix), !ids.contains(id) { try FileManager.default.removeItem(at: file) }
        }
    }

    func tag(id: UUID, fixes: [TagFix]) throws -> String {
        try Task.checkCancellation()
        let catalog = try catalog ?? AreaCatalog()
        self.catalog = catalog
        var digest = SHA256()
        // Include every input that changes membership, including same-count iCloud replacements.
        for fix in fixes {
            var values = [fix.time.bitPattern, fix.latitude.bitPattern, fix.longitude.bitPattern,
                          fix.accuracy.bitPattern, fix.paused ? 1 : 0]
            values.withUnsafeMutableBytes { digest.update(bufferPointer: UnsafeRawBufferPointer($0)) }
        }
        let revision = "1/" + catalog.revision + "/" + Data(digest.finalize()).base64EncodedString()
        let file = try RouteTagFile(url: directory().appendingPathComponent(id.uuidString + ".sqlite"), revision: revision)
        while file.next < fixes.count {
            try file.tagNextBatch(in: fixes, using: catalog)
        }
        return try file.searchTerms()
    }
}
