import Foundation

/// A named area from the offline pack.
nonisolated struct RouteArea: Hashable, Sendable {
    enum Kind: String, Sendable, CaseIterable {
        case park, neighborhood, city, state, territory
    }

    let kind: Kind
    let name: String
    /// Such as "US-OR". Empty for parks and neighborhoods.
    let region: String

    /// The two-letter state for a state, territory or city, such as "OR".
    var stateCode: String? {
        guard region.hasPrefix("US-") else { return nil }
        return String(region.dropFirst(3))
    }
}

/// The offline US area pack, `USAreas.sqlite` in the app bundle.
///
/// The file comes from `scripts/offline_areas/build.py` and is downloaded into the bundle by
/// `scripts/offline_areas/fetch.sh` at build time; it is never in git. A build without it still works, and
/// history search falls back to Apple Maps for every start. The file is read from disk a page at a time,
/// never loaded whole, and outlines are kept in a small cache while a batch of workouts is tagged.
nonisolated final class AreaPack {
    static let fileName = "USAreas"
    /// The layout this app reads. `build.py` writes the same number.
    static let format = "2"

    /// Changes with every pack, so workouts are tagged again when a new one ships.
    let revision: String
    let release: String

    private let database: AreaDatabase
    private let candidates: AreaStatement
    private let geometry: AreaStatement
    private let shapes = NSCache<NSNumber, AreaGeometry>()

    init(url: URL) throws {
        database = try AreaDatabase(url)
        let meta = try database.statement("SELECT key, value FROM meta")
        var values: [String: String] = [:]
        while try meta.step() { values[meta.text(0)] = meta.text(1) }
        guard values["format"] == Self.format, let digest = values["digest"], !digest.isEmpty else {
            throw AreaError.invalidBundle
        }
        revision = digest
        release = values["release"] ?? ""
        candidates = try database.statement("""
            SELECT a.rowid, a.kind, a.name, a.region
              FROM bounds b JOIN area a ON a.rowid = b.rowid
             WHERE b.west <= ?1 AND b.east >= ?1 AND b.south <= ?2 AND b.north >= ?2
            """)
        geometry = try database.statement("SELECT geometry FROM area WHERE rowid = ?")
        shapes.totalCostLimit = 8 * 1024 * 1024
    }

    /// The pack in the app bundle, or nil when this build has none.
    static func bundled(_ bundle: Bundle = .main) -> AreaPack? {
        guard let url = bundle.url(forResource: fileName, withExtension: "sqlite") else { return nil }
        return try? AreaPack(url: url)
    }

    /// The bundled pack's revision without keeping it open, or nil when this build has none.
    static func bundledRevision(_ bundle: Bundle = .main) -> String? {
        bundled(bundle)?.revision
    }

    /// Every area this point is inside.
    func areas(latitude: Double, longitude: Double) throws -> [RouteArea] {
        var matches: [RouteArea] = []
        candidates.reset()
        candidates.bind(longitude, 1)
        candidates.bind(latitude, 2)
        while try candidates.step() {
            let row = candidates.integer(0)
            guard let kind = RouteArea.Kind(rawValue: candidates.text(1)) else { continue }
            let shape: AreaGeometry
            if let cached = shapes.object(forKey: row as NSNumber) {
                shape = cached
            } else {
                geometry.reset()
                geometry.bind(row, 1)
                guard try geometry.step() else { throw AreaError.invalidBundle }
                let data = geometry.blob(0)
                shape = try AreaGeometry(data)
                shapes.setObject(shape, forKey: row as NSNumber, cost: data.count * 4)
            }
            if shape.contains(longitude: longitude, latitude: latitude) {
                matches.append(RouteArea(kind: kind, name: candidates.text(2), region: candidates.text(3)))
            }
        }
        return matches
    }
}
