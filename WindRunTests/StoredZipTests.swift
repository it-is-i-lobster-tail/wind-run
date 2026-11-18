//
//  StoredZipTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The zip's central directory and its end record, which unzippers read to find the files: every count,
/// size and offset has to point where the files really are.
@MainActor
struct StoredZipTests {
    private let entries: [(path: String, contents: String)] = [
        ("Folder/a.txt", "hello"),
        ("Folder/b.csv", "x,y\n1,2\n"),
        ("c", ""),
    ]

    private func zipBytes() throws -> [UInt8] {
        [UInt8](try StoredZip.make(entries.map { StoredZip.Entry(path: $0.path, data: Data($0.contents.utf8)) }))
    }

    private func uint16(_ bytes: [UInt8], _ at: Int) -> Int {
        Int(bytes[at]) | Int(bytes[at + 1]) << 8
    }

    private func uint32(_ bytes: [UInt8], _ at: Int) -> Int {
        uint16(bytes, at) | uint16(bytes, at + 2) << 16
    }

    private func text(_ bytes: [UInt8], from start: Int, count: Int) -> String {
        String(decoding: bytes[start ..< start + count], as: UTF8.self)
    }

    @Test func theEndRecordCountsTheFilesAndFindsTheDirectory() throws {
        let bytes = try zipBytes()
        let end = bytes.count - 22
        #expect(uint32(bytes, end) == 0x0605_4B50)
        #expect(uint16(bytes, end + 8) == entries.count)
        #expect(uint16(bytes, end + 10) == entries.count)
        let directorySize = uint32(bytes, end + 12)
        let directoryOffset = uint32(bytes, end + 16)
        #expect(directoryOffset + directorySize == end)
        #expect(uint32(bytes, directoryOffset) == 0x0201_4B50)
        // No comment.
        #expect(uint16(bytes, end + 20) == 0)
    }

    @Test func eachDirectoryEntryPointsAtItsFile() throws {
        let bytes = try zipBytes()
        let end = bytes.count - 22
        var position = uint32(bytes, end + 16)
        for entry in entries {
            #expect(uint32(bytes, position) == 0x0201_4B50)
            let pathLength = uint16(bytes, position + 28)
            #expect(text(bytes, from: position + 46, count: pathLength) == entry.path)
            #expect(uint32(bytes, position + 24) == entry.contents.utf8.count)

            let local = uint32(bytes, position + 42)
            #expect(uint32(bytes, local) == 0x0403_4B50)
            let localPathLength = uint16(bytes, local + 26)
            #expect(localPathLength == pathLength)
            #expect(text(bytes, from: local + 30, count: localPathLength) == entry.path)
            // No extra field, so the contents follow the name.
            #expect(uint16(bytes, local + 28) == 0)
            #expect(text(bytes, from: local + 30 + localPathLength, count: entry.contents.utf8.count) == entry.contents)

            // No extra field or comment after the name.
            position += 46 + pathLength
        }
        #expect(position == end)
    }

    @Test func theFirstFileStartsTheZip() throws {
        let bytes = try zipBytes()
        #expect(uint32(bytes, 0) == 0x0403_4B50)
        let directoryOffset = uint32(bytes, bytes.count - 22 + 16)
        #expect(uint32(bytes, directoryOffset + 42) == 0)
    }

    @Test func noFilesIsJustTheEndRecord() throws {
        let bytes = [UInt8](try StoredZip.make([]))
        #expect(bytes.count == 22)
        #expect(uint32(bytes, 0) == 0x0605_4B50)
        #expect(uint16(bytes, 8) == 0)
        #expect(uint32(bytes, 12) == 0)
        #expect(uint32(bytes, 16) == 0)
    }
}
