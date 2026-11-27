import Foundation

/// One area's outline from the offline pack: polygons with holes, written by `scripts/offline_areas/build.py`
/// as varints. Each ring's points are whole steps of 1e-5 degrees, each stored as the zigzag step from the
/// point before.
///
/// A ray from the point crosses every ring, holes included, so an odd count means inside. Rings are split
/// into blocks of 64 edges with their latitude span, so a query skips most edges of a long state border.
nonisolated final class AreaGeometry {
    static let scale = 100_000.0

    private struct Block {
        var points: [SIMD2<Int32>]
        var south: Int32
        var north: Int32
    }
    private var polygons: [[Block]] = []

    init(_ data: Data) throws {
        try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var offset = 0
            func varint() throws -> UInt64 {
                var value: UInt64 = 0
                var shift: UInt64 = 0
                while true {
                    guard offset < bytes.count, shift < 64 else { throw AreaError.invalidGeometry }
                    let byte = bytes[offset]
                    offset += 1
                    value |= UInt64(byte & 0x7F) << shift
                    if byte & 0x80 == 0 { return value }
                    shift += 7
                }
            }
            func step() throws -> Int64 {
                let raw = try varint()
                return Int64(bitPattern: raw >> 1) ^ -Int64(bitPattern: raw & 1)
            }
            let polygonCount = try varint()
            guard polygonCount <= 100_000 else { throw AreaError.invalidGeometry }
            for _ in 0..<polygonCount {
                let ringCount = try varint()
                guard ringCount >= 1, ringCount <= 100_000 else { throw AreaError.invalidGeometry }
                var blocks: [Block] = []
                for _ in 0..<ringCount {
                    let count = try varint()
                    // Every point takes at least two bytes, which bounds a damaged count.
                    guard count >= 4, count <= UInt64(bytes.count - offset) / 2 else { throw AreaError.invalidGeometry }
                    var x: Int64 = 0, y: Int64 = 0
                    var points: [SIMD2<Int32>] = []
                    points.reserveCapacity(65)
                    for i in 0..<Int(count) {
                        x += try step()
                        y += try step()
                        guard abs(x) <= 18_000_000, abs(y) <= 9_000_000 else { throw AreaError.invalidGeometry }
                        let point = SIMD2(Int32(x), Int32(y))
                        points.append(point)
                        if points.count == 65 || i == Int(count) - 1 {
                            if points.count > 1 {
                                let ys = points.map(\.y)
                                blocks.append(Block(points: points, south: ys.min()!, north: ys.max()!))
                            }
                            points = [point]
                        }
                    }
                }
                polygons.append(blocks)
            }
            guard offset == bytes.count else { throw AreaError.invalidGeometry }
        }
    }

    func contains(longitude: Double, latitude: Double) -> Bool {
        let x = longitude * Self.scale, y = latitude * Self.scale
        for blocks in polygons {
            var inside = false
            for block in blocks where Double(block.south) <= y && y < Double(block.north) {
                for i in 1..<block.points.count {
                    let a = SIMD2<Double>(Double(block.points[i - 1].x), Double(block.points[i - 1].y))
                    let b = SIMD2<Double>(Double(block.points[i].x), Double(block.points[i].y))
                    if (a.y > y) != (b.y > y), x < (b.x - a.x) * (y - a.y) / (b.y - a.y) + a.x {
                        inside.toggle()
                    }
                }
            }
            if inside { return true }
        }
        return false
    }
}
