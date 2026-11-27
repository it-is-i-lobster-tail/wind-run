//
//  LocalCache.swift
//  Wind Run
//

import Foundation

/// What Wind Run keeps only to be quick, and can always work out again from the runs: the search index,
/// the run pages' summaries held in memory and leftover files made for sharing. Runs, settings, recent
/// searches and trace logs aren't cache and are never cleared here.
@MainActor
enum LocalCache {
    /// Bytes the cache takes up on this device.
    static func size() -> Int {
        WorkoutSearchIndex.fileSize() + temporaryFiles().reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
    }

    static func clear() async {
        RunDerivedCache.shared.removeAll()
        for url in temporaryFiles() { try? FileManager.default.removeItem(at: url) }
        await WorkoutSearchIndex.shared.clear()
        Trace.log(.app, "Cache cleared")
    }

    /// Summary images and trace exports left in the temporary folder, which the system would remove in time.
    private static func temporaryFiles() -> [URL] {
        let folder = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return names.filter { url in
            let name = url.lastPathComponent
            return (name.hasPrefix("Workout-") && url.pathExtension == "png") || name == "TraceExport"
        }
    }
}
