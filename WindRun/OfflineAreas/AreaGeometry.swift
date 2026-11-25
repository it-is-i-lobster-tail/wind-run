import Foundation

/// WKB polygons and multipolygons. A ray crosses both exterior rings and holes.
/// Blocks let a latitude query skip most edges of long city and state borders.
nonisolated final class AreaGeometry {
    private struct Block {
        var points: [SIMD2<Double>]
        var south: Double
        var north: Double
    }
    private var polygons: [[Block]] = []

    init(_ data: Data) throws {
        try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var offset = 0
            func read<T: FixedWidthInteger>(_ type: T.Type, little: Bool) throws -> T {
                guard bytes.count - offset >= MemoryLayout<T>.size else { throw AreaError.invalidGeometry }
                defer { offset += MemoryLayout<T>.size }
                let value = bytes.loadUnaligned(fromByteOffset: offset, as: type)
                return little ? T(littleEndian: value) : T(bigEndian: value)
            }
            func decode(allowMulti: Bool) throws {
                let endian = try read(UInt8.self, little: true)
                guard endian <= 1 else { throw AreaError.invalidGeometry }
                let little = endian == 1
                let type = try read(UInt32.self, little: little)
                let count = try read(UInt32.self, little: little)
                if type == 6 && allowMulti {
                    for _ in 0..<count { try decode(allowMulti: false) }
                    return
                }
                guard type == 3 else { throw AreaError.invalidGeometry }
                var blocks: [Block] = []
                for _ in 0..<count {
                    let n = Int(try read(UInt32.self, little: little))
                    guard n >= 4, n <= (bytes.count - offset) / 16 else { throw AreaError.invalidGeometry }
                    var points: [SIMD2<Double>] = []
                    for i in 0..<n {
                        let x = Double(bitPattern: try read(UInt64.self, little: little))
                        let y = Double(bitPattern: try read(UInt64.self, little: little))
                        guard x.isFinite, y.isFinite else { throw AreaError.invalidGeometry }
                        points.append(.init(x,y))
                        if points.count == 65 || i == n - 1 {
                            if points.count > 1 {
                                blocks.append(Block(points: points, south: points.map(\.y).min()!, north: points.map(\.y).max()!))
                            }
                            points = [.init(x,y)]
                        }
                    }
                }
                polygons.append(blocks)
            }
            try decode(allowMulti: true)
            guard offset == bytes.count else { throw AreaError.invalidGeometry }
        }
    }

    func contains(x: Double, y: Double) -> Bool {
        for blocks in polygons {
            var inside = false
            for block in blocks where block.south <= y && y < block.north {
                for i in 1..<block.points.count {
                    let a = block.points[i - 1], b = block.points[i]
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
