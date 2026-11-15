//
//  TraceZip.swift
//  Wind Run
//

import Foundation

/// Every trace file in one zip, made in the app's temporary folder for the share sheet and deleted once
/// it closes. Nothing is sent anywhere unless the runner picks somewhere to share it.
nonisolated struct TraceZip: Identifiable, Sendable {
    let url: URL
    var id: URL { url }

    /// What the runner reads before the zip is made.
    static let privacyNote = """
        The zip holds every trace file: a line for each tap, screen, setting change, save and run event, \
        timed in seconds since the app opened, with the app version and the iPhone's model and iOS version.

        It leaves out locations, typed text, workout and step names, notes, weight, heart rate and other \
        health readings, and your iPhone's name.

        Once shared, anyone with the zip can read it.
        """

    private static var folder: URL {
        URL.temporaryDirectory.appending(path: "TraceExport", directoryHint: .isDirectory)
    }

    /// "Wind Run trace logs 2026-11-15".
    static func name(on date: Date = .now) -> String {
        "Wind Run trace logs \(date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()))"
    }

    static func make(from files: TraceFiles = .shared) async throws -> TraceZip {
        try await Task.detached(priority: .userInitiated) {
            deleteMadeZips()
            let manager = FileManager.default
            let work = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try manager.createDirectory(at: work, withIntermediateDirectories: true)
            let zipName = name()
            let copies = try files.copyAll(into: work, folderName: zipName)
            let destination = work.appending(path: "\(zipName).zip")

            // Asking to read a folder "for uploading" has the system zip it, the way Files does.
            var coordinatorError: NSError?
            var copyError: (any Error)?
            NSFileCoordinator().coordinate(readingItemAt: copies, options: .forUploading, error: &coordinatorError) { zipped in
                do {
                    try manager.moveItem(at: zipped, to: destination)
                } catch {
                    copyError = error
                }
            }
            if let error = coordinatorError ?? copyError { throw error }
            try? manager.removeItem(at: copies)
            return TraceZip(url: destination)
        }.value
    }

    /// Deletes every zip made for sharing, which hold copies of the trace files.
    static func deleteMadeZips() {
        try? FileManager.default.removeItem(at: folder)
    }
}
