//
//  StoredZip.swift
//  Wind Run
//

import Foundation

/// A zip of files stored as they are, without compression, written by Wind Run itself.
///
/// The system's zips stamp each file with when it was made, in local time and again in UTC, which says when
/// the zip was made and the runner's time zone. These carry 1 January 1980 at midnight, the earliest date a
/// zip can hold, and nothing else about the files: no owner, permissions or extra fields.
nonisolated enum StoredZip {
    /// One file in the zip: where it goes, such as "Folder/file.csv", and its bytes, read only as it goes in.
    struct Entry {
        var path: String
        var contents: () throws -> Data

        init(path: String, contents: @escaping () throws -> Data) {
            self.path = path
            self.contents = contents
        }

        init(path: String, data: Data) {
            self.init(path: path) { data }
        }
    }

    /// The zip's bytes.
    static func make(_ entries: [Entry]) throws -> Data {
        var archive = Data()
        try write(entries) { archive.append($0) }
        return archive
    }

    /// Writes the zip a piece at a time through `output`, reading each file only as it goes in, so a big set
    /// of files never sits in memory at once. Throws when it's too big for a plain zip: over 4 GB, or more
    /// than 65,535 files.
    static func write(_ entries: [Entry], to output: (Data) throws -> Void) throws {
        guard let count = UInt16(exactly: entries.count) else { throw CocoaError(.fileWriteUnknown) }
        var directory = Data()
        var written = 0
        for entry in entries {
            let path = Data(entry.path.utf8)
            let contents = try entry.contents()
            guard let size = UInt32(exactly: contents.count),
                  let offset = UInt32(exactly: written),
                  let pathLength = UInt16(exactly: path.count) else {
                throw CocoaError(.fileWriteUnknown)
            }
            // What the local header and the directory both say about the file.
            var shared = Data()
            shared.appendLittleEndian(UInt16(20)) // Version needed: 2.0.
            shared.appendLittleEndian(UInt16(0)) // No flags.
            shared.appendLittleEndian(UInt16(0)) // Stored, not compressed.
            shared.appendLittleEndian(UInt16(0)) // Time: midnight.
            shared.appendLittleEndian(UInt16(0x21)) // Date: 1 January 1980.
            shared.appendLittleEndian(crc32(contents))
            shared.appendLittleEndian(size)
            shared.appendLittleEndian(size)
            shared.appendLittleEndian(pathLength)
            shared.appendLittleEndian(UInt16(0)) // No extra fields.

            var header = Data()
            header.appendLittleEndian(UInt32(0x0403_4B50))
            header.append(shared)
            header.append(path)
            try output(header)
            try output(contents)
            written += header.count + contents.count

            directory.appendLittleEndian(UInt32(0x0201_4B50))
            directory.appendLittleEndian(UInt16(20)) // Made by: MS-DOS, version 2.0, so no owner or permissions.
            directory.append(shared)
            directory.appendLittleEndian(UInt16(0)) // No comment.
            directory.appendLittleEndian(UInt16(0)) // Disk 0.
            directory.appendLittleEndian(UInt16(0)) // Internal attributes.
            directory.appendLittleEndian(UInt32(0)) // External attributes.
            directory.appendLittleEndian(offset)
            directory.append(path)
        }
        guard let directorySize = UInt32(exactly: directory.count), let directoryOffset = UInt32(exactly: written) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var end = directory
        end.appendLittleEndian(UInt32(0x0605_4B50))
        end.appendLittleEndian(UInt16(0)) // This disk.
        end.appendLittleEndian(UInt16(0)) // The directory's disk.
        end.appendLittleEndian(count)
        end.appendLittleEndian(count)
        end.appendLittleEndian(directorySize)
        end.appendLittleEndian(directoryOffset)
        end.appendLittleEndian(UInt16(0)) // No comment.
        try output(end)
    }

    /// The CRC-32 a zip keeps for each file, worked out a byte at a time from a table.
    static func crc32(_ data: Data) -> UInt32 {
        let table = crcTable
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { bytes in
            for byte in bytes {
                crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return ~crc
    }

    /// What each byte does to the CRC, worked out once.
    private static let crcTable: [UInt32] = (0 ..< 256).map { index in
        var crc = UInt32(index)
        for _ in 0 ..< 8 {
            crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
        }
        return crc
    }
}

private extension Data {
    nonisolated mutating func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
