//
//  RunExport.swift
//  Wind Run
//

import Foundation

/// Every finished run as two CSV files for looking at offline, such as checking Wind Run's distance against
/// another watch: one row per run, and one row per GPS fix.
///
/// Nothing in it says where the runner was or who they are. Left out: coordinates, headings, routes, the
/// start time of day, heart rate values, notes, workout and plan names, weight, calories, step counts, the
/// run's ids and the names people give their devices. Positions only appear as the straight-line gap between
/// one fix and the next, with no direction, and heights only as the change from the run's first fix.
enum RunExport {
    /// What the runner reads before the files are made.
    static let privacyNote = """
        The export has each finished run's date, kind, distances, times, speeds, GPS accuracy, height changes, \
        and the models and software versions of the devices used.

        It leaves out where you ran (no coordinates, routes or directions), start times, heart rate readings, \
        notes, workout names, weight and calories.

        Once saved, anyone you share the files with can read them.
        """

    nonisolated struct Files: Equatable, Sendable {
        /// One row per run.
        var runs: String
        /// One row per GPS fix.
        var fixes: String
    }

    static let runColumns = [
        "run", "date", "kind", "data_from",
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
        "altitude_change_m", "spike", "counted_m", "counted_by",
    ]

    /// The files for `runs`. Only finished runs go in, oldest first, numbered from 1.
    @MainActor
    static func make(_ runs: [Run], exportedBy: DeviceInfo = .current, timeZone: TimeZone = .current) -> Files {
        let finished = runs.filter { $0.status == .complete }.sorted { $0.startDate < $1.startDate }
        let dayFormat = Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day()

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
            let firstAltitude = route.first { $0.verticalAccuracyValue >= 0 }?.altitudeValue
            let accuracies = route.map(\.horizontalAccuracyValue).filter { $0 >= 0 }.sorted()
            let sources = Set(run.heartRateSamples.compactMap(\.sourceValue)).sorted()

            let runFields: [String] = [
                runNumber,
                run.startDate.formatted(dayFormat),
                run.kind.rawValue,
                devices?.dataFrom ?? "unknown",
                devices?.recorder.kind.name ?? "",
                devices?.recorder.model ?? "",
                devices?.recorder.system ?? "",
                devices?.recorder.app ?? "",
                devices?.receivedBy?.model ?? "",
                devices?.receivedBy?.system ?? "",
                devices?.receivedBy?.app ?? "",
                (devices?.heartRate ?? []).map(\.details).joined(separator: "; "),
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
                let altitudeChange: String = if let firstAltitude, sample.verticalAccuracyValue >= 0 {
                    number(sample.altitudeValue - firstAltitude, decimals: 1)
                } else {
                    ""
                }
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
                    altitudeChange,
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
        fields.map(escape).joined(separator: ",")
    }

    static func escape(_ field: String) -> String {
        let special: Set<Unicode.Scalar> = [",", "\"", "\n", "\r"]
        guard field.unicodeScalars.contains(where: special.contains) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// "Wind Run runs 2026-11-15".
    static func folderName(on date: Date = .now, timeZone: TimeZone = .current) -> String {
        "Wind Run runs \(date.formatted(Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day()))"
    }
}
