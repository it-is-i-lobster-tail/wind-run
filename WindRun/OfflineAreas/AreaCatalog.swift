import Foundation

nonisolated struct RouteArea: Hashable {
    let id: String
    let kind: String
    let name: String
    let region: String
}

nonisolated final class AreaCatalog {
    private struct Manifest: Decodable {
        let format: Int
        let digest: String
        let shards: [Shard]
    }
    private struct Shard: Decodable {
        let file: String
        let extent: [Double]
    }
    private struct Reader {
        let extent: [Double]
        let candidates: AreaStatement
        let geometry: AreaStatement
    }
    let revision: String
    private let readers: [Reader]
    private let shapes = NSCache<NSString, AreaGeometry>()

    init(bundle: Bundle = .main) throws {
        guard let manifestURL = bundle.url(forResource: "USAreas", withExtension: "json") else { throw AreaError.invalidBundle }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.format == 1, !manifest.shards.isEmpty else { throw AreaError.invalidBundle }
        revision = manifest.digest
        readers = try manifest.shards.map { shard in
            guard shard.extent.count == 4 else { throw AreaError.invalidBundle }
            let db = try AreaDatabase(manifestURL.deletingLastPathComponent().appendingPathComponent(shard.file))
            return try Reader(extent: shard.extent, candidates: db.statement("""
                SELECT a.rowid, hex(a.id), a.kind, a.name, a.region
                  FROM bounds b JOIN area a ON a.rowid=b.rowid
                 WHERE b.west<=?1 AND b.east>=?1 AND b.south<=?2 AND b.north>=?2
                """), geometry: db.statement("SELECT geometry FROM area WHERE rowid=?"))
        }
        shapes.totalCostLimit = 24 * 1024 * 1024
    }

    func areas(longitude x: Double, latitude y: Double) throws -> [RouteArea] {
        var matches: [RouteArea] = []
        for r in readers where r.extent[0] <= x && x <= r.extent[2] && r.extent[1] <= y && y <= r.extent[3] {
            let q = r.candidates
            q.reset()
            q.bind(x, 1)
            q.bind(y, 2)
            while try q.step() {
                let id = q.text(1)
                let shape: AreaGeometry
                if let cached = shapes.object(forKey: id as NSString) { shape = cached }
                else {
                    r.geometry.reset()
                    r.geometry.bind(q.integer(0), 1)
                    guard try r.geometry.step() else { throw AreaError.invalidBundle }
                    let data = r.geometry.blob(0)
                    shape = try AreaGeometry(data)
                    shapes.setObject(shape, forKey: id as NSString, cost: data.count)
                }
                if shape.contains(x: x, y: y) {
                    matches.append(RouteArea(id: id, kind: q.text(2), name: q.text(3), region: q.text(4)))
                }
            }
        }
        return matches
    }
}
