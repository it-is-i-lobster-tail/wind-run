//
//  RunExport.swift
//  Wind Run
//

import CoreLocation
import Foundation
import UniformTypeIdentifiers

/// Every finished run as two CSV files for looking at offline, such as checking Wind Run's distance against
/// another watch: one row per run, and one row per GPS fix.
///
/// Nothing in it says where the runner was, when, or who they are. Left out: coordinates, headings, routes,
/// heights, dates and times of day, heart rate values, notes, workout and plan names, weight, calories, step
/// counts, the run's ids, the names people give their devices, and anything in a sensor's details that looks
/// like a serial number. Positions only appear as the straight-line gap between one fix and the next, with no
/// direction, and time only as seconds from the run's start. Fixes near where a run started or finished, often
/// home, are left out. Runs are numbered oldest first, which is the only trace of when they happened.
enum RunExport {
    /// What the runner reads before the files are made.
    static let privacyNote = """
        The export has each finished run's kind, distances, durations, speeds and GPS accuracy, and the models \
        and software versions of the devices used. Runs are numbered oldest first.

        It leaves out where and when you ran (no coordinates, routes, directions, heights, dates or times), \
        heart rate readings, notes, workout names, weight, calories and device names. GPS points within \
        250 m of where each run started or finished are left out too, as that's often home.

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

    /// How close to where a run started or finished a fix can be and still go in `fixes.csv`. Runs often start
    /// and finish at home, and the distances and pauses near it could help someone who knows the area find it.
    nonisolated static let privacyZoneMeters: CLLocationDistance = 250

    /// The files for `runs`. Only finished runs go in, oldest first, numbered from 1.
    /// `exportedBy` is this device unless given. Fixes closer than `privacyZone` to either end of their run
    /// are left out of `fixes.csv`; the run's totals still count them.
    @MainActor
    static func make(_ runs: [Run], exportedBy: DeviceInfo? = nil, privacyZone: CLLocationDistance = privacyZoneMeters) -> Files {
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

            let ends = [fixes.first, fixes.last].compactMap { $0?.location }
            for (fixIndex, sample) in route.enumerated() {
                let location = fixes[fixIndex].location
                guard ends.allSatisfy({ location.distance(from: $0) >= privacyZone }) else { continue }
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

    /// The bytes of the chosen export. Only a zip too big to write can fail.
    nonisolated static func data(for choice: Choice, from files: Files) throws -> Data {
        switch choice {
        case .runs: Data(files.runs.utf8)
        case .fixes: Data(files.fixes.utf8)
        case .both: try zip(files)
        }
    }

    /// Both files in a zip, holding a folder with `runs.csv` and `fixes.csv`, stored without compression.
    ///
    /// Wind Run writes the zip itself because the system's zips stamp each file with when it was made, in local
    /// time and again in UTC, which says when the export was made and the runner's time zone. These carry
    /// 1 January 1980, the earliest date a zip can hold, and no other details.
    nonisolated static func zip(_ files: Files) throws -> Data {
        var archive = Data()
        var directory = Data()
        let entries = [("runs.csv", files.runs), ("fixes.csv", files.fixes)]
        for (name, text) in entries {
            let path = Data("\(folderName)/\(name)".utf8)
            let contents = Data(text.utf8)
            guard let size = UInt32(exactly: contents.count), let offset = UInt32(exactly: archive.count) else {
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
            shared.appendLittleEndian(UInt16(path.count))
            shared.appendLittleEndian(UInt16(0)) // No extra fields.

            archive.appendLittleEndian(UInt32(0x0403_4B50))
            archive.append(shared)
            archive.append(path)
            archive.append(contents)

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
        guard let directorySize = UInt32(exactly: directory.count), let directoryOffset = UInt32(exactly: archive.count) else {
            throw CocoaError(.fileWriteUnknown)
        }
        archive.append(directory)
        archive.appendLittleEndian(UInt32(0x0605_4B50))
        archive.appendLittleEndian(UInt16(0)) // This disk.
        archive.appendLittleEndian(UInt16(0)) // The directory's disk.
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(UInt16(entries.count))
        archive.appendLittleEndian(directorySize)
        archive.appendLittleEndian(directoryOffset)
        archive.appendLittleEndian(UInt16(0)) // No comment.
        return archive
    }

    /// The CRC-32 a zip keeps for each file.
    nonisolated static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1
            }
        }
        return ~crc
    }

    /// Device details with anything that looks like a serial number or other id taken out. Sensors from other
    /// makers sometimes put one in their model or version: a word with five or more digits, or a long word
    /// mixing letters and digits. Apple's model ids, such as "Watch7,1", and versions, such as "26.1.0", stay.
    ///
    /// A sensor's details come from the sensor itself, so only letters, digits, spaces and `.,()-_/` are kept,
    /// nothing at the start can begin a spreadsheet formula, and the whole is cut to 100 characters.
    static func scrubbed(_ text: String) -> String {
        let words = text.split(separator: " ").filter { word in
            if word.wholeMatch(of: /(iPhone|Watch|iPad)[0-9]{1,3},[0-9]{1,2}/) != nil { return true }
            let digits = word.filter(\.isNumber).count
            let letters = word.filter(\.isLetter).count
            return digits < 5 && !(word.count >= 10 && digits >= 2 && letters >= 2)
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " .,()-_/"))
        var kept = String(String.UnicodeScalarView(words.joined(separator: " ").unicodeScalars.filter(allowed.contains)))
        while let first = kept.first, first == "-" || first == " " {
            kept.removeFirst()
        }
        return String(kept.prefix(100))
    }
}

private extension Data {
    nonisolated mutating func appendLittleEndian<Value: FixedWidthInteger>(_ value: Value) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
