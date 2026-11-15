//
//  RunExport.swift
//  Wind Run
//

import Foundation
import UniformTypeIdentifiers

/// Every finished run as two CSV files for looking at offline, such as checking Wind Run's distance against
/// another watch: one row per run, and one row per GPS fix.
///
/// Nothing in it says where the runner was, when, or who they are. Left out: coordinates, headings, routes,
/// heights, dates and times of day, heart rate values, notes, workout and plan names, weight, calories, step
/// counts, the run's ids, the names people give their devices, and anything in a sensor's details that looks
/// like a serial number. Positions only appear as the straight-line gap between one fix and the next, with no
/// direction, and time only as seconds from the run's start. Runs are numbered oldest first, which is the only
/// trace of when they happened.
enum RunExport {
    /// What the runner reads before the files are made.
    static let privacyNote = """
        The export has each finished run's kind, distances, durations, speeds and GPS accuracy, and the models \
        and software versions of the devices used. Runs are numbered oldest first.

        It leaves out where and when you ran (no coordinates, routes, directions, heights, dates or times), \
        heart rate readings, notes, workout names, weight, calories and device names.

        Once saved, anyone you share the files with can read them.
        """

    nonisolated struct Files: Equatable, Sendable {
        /// One row per run.
        var runs: String
        /// One row per GPS fix.
        var fixes: String
    }

    static let runColumns = [
        "run", "kind", "data_from",
        "recorded_on", "recorder_model", "recorder_os", "recorder_app",
        "received_by_model", "received_by_os", "received_by_app",
        "heart_rate_devices", "heart_rate_sources", "heart_rate_readings",
        "distance_m", "distance_method", "gps_track_m", "apple_distance_m",
        "recomputed_distance_m", "recomputed_gps_track_m",
        "active_s", "paused_s", "elapsed_s", "pauses",
        "fixes", "fixes_with_speed", "spikes", "median_horizontal_accuracy_m",
        "exported_by_model", "exported_by_os", "exported_by_app",
    ]

    static let fixColumns = [
        "run", "fix", "seconds", "active", "gap_m",
        "horizontal_accuracy_m", "vertical_accuracy_m", "speed_mps", "speed_accuracy_mps",
        "spike", "counted_m", "counted_by",
    ]

    /// The files for `runs`. Only finished runs go in, oldest first, numbered from 1.
    /// `exportedBy` is this device unless given.
    @MainActor
    static func make(_ runs: [Run], exportedBy: DeviceInfo? = nil) -> Files {
        // `DeviceInfo.current` needs the main actor, which a default argument can't reach.
        let exportedBy = exportedBy ?? .current
        let finished = runs.filter { $0.status == .complete }.sorted { $0.startDate < $1.startDate }

        var runRows = [runColumns.joined(separator: ",")]
        var fixRows = [fixColumns.joined(separator: ",")]
        for (index, run) in finished.enumerated() {
            let runNumber = "\(index + 1)"
            let route = run.route
            let pauses = run.pauses
            let fixes = route.map(DistanceEstimator.Fix.init)
            let isActive: (Date) -> Bool = { time in !pauses.contains { $0.contains(time) } }
            let measured = MeasuredRoute(fixes, isActive: isActive)
            let devices = run.devices
            let end = run.endDate ?? run.startDate
            let accuracies = route.map(\.horizontalAccuracyValue).filter { $0 >= 0 }.sorted()
            let sources = Set(run.heartRateSamples.compactMap(\.sourceValue)).sorted()

            let runFields: [String] = [
                runNumber,
                run.kind.rawValue,
                devices?.dataFrom ?? "unknown",
                devices?.recorder.kind.name ?? "",
                devices?.recorder.model ?? "",
                devices?.recorder.system ?? "",
                devices?.recorder.app ?? "",
                devices?.receivedBy?.model ?? "",
                devices?.receivedBy?.system ?? "",
                devices?.receivedBy?.app ?? "",
                (devices?.heartRate ?? []).map { scrubbed($0.details) }.joined(separator: "; "),
                sources.joined(separator: "; "),
                "\(run.heartRateSamples.count)",
                number(run.distanceMeters),
                run.distanceMethod ?? "gps-track",
                run.gpsTrackMeters.map { number($0) } ?? "",
                run.appleDistanceMeters.map { number($0) } ?? "",
                number(measured.meters),
                number(measured.trackMeters),
                number(run.activeDuration(), decimals: 1),
                number(run.pausedDuration(), decimals: 1),
                number(end.timeIntervalSince(run.startDate), decimals: 1),
                "\(pauses.count)",
                "\(route.count)",
                "\(fixes.filter(\.hasUsableSpeed).count)",
                "\(measured.steps.filter(\.isSpike).count)",
                accuracies.isEmpty ? "" : number(accuracies[accuracies.count / 2], decimals: 1),
                exportedBy.model ?? "",
                exportedBy.system ?? "",
                exportedBy.app ?? "",
            ]
            runRows.append(row(runFields))

            for (fixIndex, sample) in route.enumerated() {
                let step = measured.steps[fixIndex]
                let fields: [String] = [
                    runNumber,
                    "\(fixIndex + 1)",
                    number(sample.timestamp.timeIntervalSince(run.startDate), decimals: 1),
                    isActive(sample.timestamp) ? "1" : "0",
                    number(step.gap),
                    number(sample.horizontalAccuracyValue, decimals: 1),
                    number(sample.verticalAccuracyValue, decimals: 1),
                    sample.speedValue >= 0 ? number(sample.speedValue) : "",
                    sample.speedAccuracyValue >= 0 ? number(sample.speedAccuracyValue) : "",
                    step.isSpike ? "1" : "0",
                    number(step.meters),
                    step.counting.rawValue,
                ]
                fixRows.append(row(fields))
            }
        }
        return Files(runs: runRows.joined(separator: "\n") + "\n", fixes: fixRows.joined(separator: "\n") + "\n")
    }

    /// A number with a dot for the decimal point whatever the region, so any tool can read it.
    static func number(_ value: Double, decimals: Int = 2) -> String {
        guard value.isFinite else { return "" }
        return String(format: "%.\(decimals)f", value)
    }

    /// One CSV line, quoting any field that needs it.
    static func row(_ fields: [String]) -> String {
        fields.map { escape($0) }.joined(separator: ",")
    }

    static func escape(_ field: String) -> String {
        let special: Set<Unicode.Scalar> = [",", "\"", "\n", "\r"]
        guard field.unicodeScalars.contains(where: special.contains) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// The name of the folder inside the zip. It carries no date, so a shared copy doesn't say when it was made.
    nonisolated static let folderName = "Wind Run runs"

    /// What the runner can export: either file on its own, or both in a zip.
    nonisolated enum Choice: String, CaseIterable, Identifiable {
        case runs
        case fixes
        case both

        var id: String { rawValue }

        var title: String {
            switch self {
            case .runs: "Runs (runs.csv)"
            case .fixes: "GPS Points (fixes.csv)"
            case .both: "Both as a Zip"
            }
        }

        /// The suggested file name, without a date; Files adds the extension.
        var filename: String {
            switch self {
            case .runs: "Wind Run runs"
            case .fixes: "Wind Run GPS points"
            case .both: "Wind Run export"
            }
        }

        var contentType: UTType {
            self == .both ? .zip : .commaSeparatedText
        }
    }

    /// The bytes of the chosen export.
    nonisolated static func data(for choice: Choice, from files: Files) throws -> Data {
        switch choice {
        case .runs: Data(files.runs.utf8)
        case .fixes: Data(files.fixes.utf8)
        case .both: try zip(files)
        }
    }

    /// Both files in a zip, holding a folder with `runs.csv` and `fixes.csv`. The system makes the zip, so no
    /// library is needed: reading a folder "for uploading" hands back a zipped copy of it.
    nonisolated static func zip(_ files: Files) throws -> Data {
        let manager = FileManager.default
        let parent = manager.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let folder = parent.appending(path: folderName, directoryHint: .isDirectory)
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: parent) }
        try Data(files.runs.utf8).write(to: folder.appending(path: "runs.csv"))
        try Data(files.fixes.utf8).write(to: folder.appending(path: "fixes.csv"))

        var coordinatorError: NSError?
        var zipped: Result<Data, any Error> = .failure(CocoaError(.fileWriteUnknown))
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinatorError) { url in
            zipped = Result { try Data(contentsOf: url) }
        }
        if let coordinatorError { throw coordinatorError }
        return try zipped.get()
    }

    /// Device details with anything that looks like a serial number or other id taken out. Sensors from other
    /// makers sometimes put one in their model or version: a word with five or more digits, or a long word
    /// mixing letters and digits. Apple's model ids, such as "Watch7,1", and versions, such as "26.1.0", stay.
    static func scrubbed(_ text: String) -> String {
        text.split(separator: " ").filter { word in
            if word.wholeMatch(of: /(iPhone|Watch|iPad)[0-9]{1,3},[0-9]{1,2}/) != nil { return true }
            let digits = word.filter(\.isNumber).count
            let letters = word.filter(\.isLetter).count
            return digits < 5 && !(word.count >= 10 && digits >= 2 && letters >= 2)
        }
        .joined(separator: " ")
    }
}
