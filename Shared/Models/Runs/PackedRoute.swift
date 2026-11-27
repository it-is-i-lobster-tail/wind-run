//
//  PackedRoute.swift
//  Wind Run
//

import Foundation

/// A finished run's whole route in one compact piece of data, kept on the run (`Run.routeDataValue`).
///
/// Each GPS fix is also its own stored record (`RouteSample`), and each is read through SwiftData and
/// synced to iCloud one by one, which makes a long run slow to open and heavy to sync. Packed, the route is
/// one read and one iCloud file. Nothing is rounded: every field comes back exactly as it was recorded.
///
/// Layout, before compression (LZFSE): the fix count as a 32-bit integer, then each field for every fix in
/// turn (all the times, then all the latitudes, and so on), each a 64-bit float, little-endian. Fields kept
/// together compress better. The stored data is "WRP" and a version byte, then the compressed layout.
nonisolated enum PackedRoute {
    static let version: UInt8 = 1
    private static let magic: [UInt8] = Array("WRP".utf8)
    /// Fields per fix: time, latitude, longitude, altitude, horizontal and vertical accuracy, speed, course,
    /// speed accuracy.
    private static let fields = 9

    /// The route packed, or nil for an empty route.
    static func encode(_ readings: [RouteReading]) -> Data? {
        guard !readings.isEmpty else { return nil }
        var raw = Data(capacity: 4 + readings.count * fields * 8)
        var count = UInt32(readings.count).littleEndian
        withUnsafeBytes(of: &count) { raw.append(contentsOf: $0) }
        let columns: [(RouteReading) -> Double] = [
            { $0.timestamp.timeIntervalSinceReferenceDate },
            \.latitudeValue, \.longitudeValue, \.altitudeValue,
            \.horizontalAccuracyValue, \.verticalAccuracyValue,
            \.speedValue, \.courseValue, \.speedAccuracyValue,
        ]
        for column in columns {
            for reading in readings {
                var bits = column(reading).bitPattern.littleEndian
                withUnsafeBytes(of: &bits) { raw.append(contentsOf: $0) }
            }
        }
        guard let compressed = try? (raw as NSData).compressed(using: .lzfse) as Data else { return nil }
        return Data(magic + [version]) + compressed
    }

    /// The fixes, in the order they were packed, or nil when the data isn't a packed route this version reads.
    static func decode(_ data: Data) -> [RouteReading]? {
        let header = magic.count + 1
        guard data.count > header, Array(data.prefix(magic.count)) == magic, data[data.startIndex + magic.count] == version,
              let raw = try? (data.dropFirst(header) as NSData).decompressed(using: .lzfse) as Data,
              raw.count >= 4 else { return nil }
        return raw.withUnsafeBytes { buffer -> [RouteReading]? in
            let count = Int(UInt32(littleEndian: buffer.loadUnaligned(fromByteOffset: 0, as: UInt32.self)))
            guard raw.count == 4 + count * fields * 8 else { return nil }
            func value(_ field: Int, _ index: Int) -> Double {
                let offset = 4 + (field * count + index) * 8
                return Double(bitPattern: UInt64(littleEndian: buffer.loadUnaligned(fromByteOffset: offset, as: UInt64.self)))
            }
            return (0..<count).map { index in
                RouteReading(
                    timestamp: Date(timeIntervalSinceReferenceDate: value(0, index)),
                    latitude: value(1, index),
                    longitude: value(2, index),
                    altitude: value(3, index),
                    horizontalAccuracy: value(4, index),
                    verticalAccuracy: value(5, index),
                    speed: value(6, index),
                    course: value(7, index),
                    speedAccuracy: value(8, index)
                )
            }
        }
    }
}
