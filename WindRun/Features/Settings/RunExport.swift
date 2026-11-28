//
//  RunExport.swift
//  Wind Run
//

import CoreLocation
import Foundation
import UniformTypeIdentifiers

/// Every finished run as two CSV files for looking at offline, such as checking Wind Run's distance against
/// another watch: one row per run, and one row per GPS point.
///
/// Nothing in it says where the runner was, when, or who they are. Left out: coordinates, headings, routes,
/// heights, dates and times of day, heart rate values, notes, workout and plan names, weight, calories, step
/// counts, the run's ids, the names people give their devices, and anything in a sensor's details that looks
/// like a serial number. Positions only appear as the straight-line gap between one point and the next, with
/// no direction, and time only as seconds from the run's start. Points near where a run started or finished,
/// often home, or near places the runner pinned, are left out. Runs are numbered oldest first, which is the
/// only trace of when they happened.
///
/// Each run is copied out of the store on the main actor (`Record`) and the files are made from the copies
/// off it (`Maker`), a run at a time, so a long history doesn't hold up the screen.
nonisolated enum RunExport {
    struct Files: Equatable, Sendable {
        /// One row per run.
        var runs: String
        /// One row per GPS point.
        var points: String
        /// The rows in `points`, and the GPS points left out for being near where a run started or finished.
        var pointRows = 0
        var pointsLeftOut = 0
    }

    static let runColumns = [
        "run", "kind", "data_from",
        "recorder_kind", "recorder_model", "recorder_os", "recorder_app",
        "received_by_model", "received_by_os", "received_by_app",
        "heart_rate_devices", "heart_rate_sources", "heart_rate_readings",
        "distance_m", "distance_method", "gps_track_m", "apple_distance_m",
        "recomputed_distance_m", "recomputed_gps_track_m",
        "active_s", "paused_s", "elapsed_s", "pauses",
        "points", "points_with_speed", "spikes", "median_horizontal_accuracy_m",
        "exported_by_model", "exported_by_os", "exported_by_app", "workout_type",
        "weather_temp_c", "weather_feels_like_c", "weather_humidity_pct", "weather_cloud_cover_pct",
        "weather_wind_mps", "weather_gust_mps", "weather_wind_from_deg", "weather_condition", "weather_at",
    ]

    static let pointColumns = [
        "run", "point", "seconds", "active", "gap_m",
        "horizontal_accuracy_m", "vertical_accuracy_m", "speed_mps", "speed_accuracy_mps",
        "spike", "counted_m", "counted_by",
    ]

    /// How close to where a run started or finished a point can be and still go in `gps_points.csv`, unless the
    /// runner picks another distance or pins places instead (`ExportPrivacy`). Runs often start and finish at
    /// home, and the distances and pauses near it could help someone who knows the area find it.
    static let privacyZoneMeters: CLLocationDistance = ExportPrivacy.defaultMeters

    /// The files for `runs`, all at once. Only finished runs go in, oldest first, numbered from 1.
    /// `exportedBy` is this device unless given. Points closer than `privacyZone` to either end of their run
    /// are left out of `gps_points.csv`; the run's totals still count them. `hiding`, when given, says what to
    /// leave out instead.
    @MainActor
    static func make(
        _ runs: [Run],
        exportedBy: DeviceInfo? = nil,
        privacyZone: CLLocationDistance = privacyZoneMeters,
        hiding: ExportPrivacy? = nil
    ) -> Files {
        // `DeviceInfo.current` needs the main actor, which a default argument can't reach.
        var builder = Builder(exportedBy: exportedBy ?? .current, hiding: hiding ?? .startAndFinish(privacyZone))
        for run in finished(runs) {
            builder.add(Record(run))
        }
        return builder.files
    }

    /// The runs that go in an export: the finished ones, oldest first.
    @MainActor
    static func finished(_ runs: [Run]) -> [Run] {
        runs.filter { $0.status == .complete }.sorted { $0.startDate < $1.startDate }
    }

    /// What the export needs from one run, copied out of the store so the files can be made off the main
    /// actor.
    struct Record: Sendable {
        var start: Date
        var end: Date
        var sport: WorkoutSport
        var kind: String
        var devices: RunDevices?
        var heartRateSources: [String]
        var heartRateReadings: Int
        var distanceMeters: Double
        var distanceMethod: String?
        var gpsTrackMeters: Double?
        var appleDistanceMeters: Double?
        var activeSeconds: TimeInterval
        var pausedSeconds: TimeInterval
        /// When each pause started and ended. One that never ended runs on forever.
        var pauses: [(start: Date, end: Date)]
        /// The GPS fixes in the order they were taken.
        var fixes: [DistanceEstimator.Fix]
        /// Each fix's vertical accuracy, in step with `fixes`.
        var verticalAccuracies: [Double]
        /// The run's weather from Apple Weather, which holds no place or time of day of its own worth keeping.
        var weather: RunWeather?

        @MainActor
        init(_ run: Run) {
            let route = run.route
            // Only counted and their sources named, so they aren't put in order.
            let readings = run.heartRateSamplesValue ?? []
            start = run.startDate
            end = run.endDate ?? run.startDate
            sport = run.sport
            kind = run.kind.rawValue
            devices = run.devices
            heartRateSources = Set(readings.compactMap(\.sourceValue)).sorted()
            heartRateReadings = readings.count
            distanceMeters = run.distanceMeters
            distanceMethod = run.distanceMethod
            gpsTrackMeters = run.gpsTrackMeters
            appleDistanceMeters = run.appleDistanceMeters
            activeSeconds = run.activeDuration()
            pausedSeconds = run.pausedDuration()
            pauses = run.pauses.map { (start: $0.startDate, end: $0.endDate ?? .distantFuture) }
            fixes = route.map(DistanceEstimator.Fix.init)
            verticalAccuracies = route.map(\.verticalAccuracyValue)
            weather = run.weather
        }
    }

    /// Makes the files a run at a time, numbering the runs in the order they're added.
    struct Builder {
        let exportedBy: DeviceInfo
        let hiding: ExportPrivacy
        private var runs = RunExport.runColumns.joined(separator: ",") + "\n"
        private var points = RunExport.pointColumns.joined(separator: ",") + "\n"
        private var runCount = 0
        private var pointRows = 0
        private var pointsLeftOut = 0

        init(exportedBy: DeviceInfo, hiding: ExportPrivacy = .standard) {
            self.exportedBy = exportedBy
            self.hiding = hiding
        }

        var files: Files {
            Files(runs: runs, points: points, pointRows: pointRows, pointsLeftOut: pointsLeftOut)
        }

        mutating func add(_ record: Record) {
            runCount += 1
            let runNumber = "\(runCount)"
            let fixes = record.fixes
            let active = RunExport.activeFlags(of: fixes.map(\.time), pauses: record.pauses)
            let measured = MeasuredRoute(fixes, active: active, sport: record.sport)
            runs += RunExport.row(runFields(record, number: runNumber, measured: measured)) + "\n"

            let centers = hiding.centers(first: fixes.first?.location, last: fixes.last?.location)
            for (index, fix) in fixes.enumerated() {
                guard hiding.shows(fix.location, centers: centers) else {
                    pointsLeftOut += 1
                    continue
                }
                let fields = pointFields(fix, index: index, number: runNumber, record: record, step: measured.steps[index], active: active[index])
                points += RunExport.row(fields) + "\n"
                pointRows += 1
            }
        }

        /// The run's row in `runs.csv`, a field for each of `runColumns`, in its order.
        private func runFields(_ record: Record, number: String, measured: MeasuredRoute) -> [String] {
            let fixes = record.fixes
            let devices = record.devices
            let accuracies = fixes.map(\.horizontalAccuracy).filter { $0 >= 0 }.sorted()
            return [
                number,
                record.kind,
                devices?.dataFrom ?? "unknown",
                devices?.recorder.kind.name ?? "",
                devices?.recorder.model ?? "",
                devices?.recorder.system ?? "",
                devices?.recorder.app ?? "",
                devices?.receivedBy?.model ?? "",
                devices?.receivedBy?.system ?? "",
                devices?.receivedBy?.app ?? "",
                (devices?.heartRate ?? []).map { RunExport.scrubbed($0.details) }.joined(separator: "; "),
                record.heartRateSources.joined(separator: "; "),
                "\(record.heartRateReadings)",
                RunExport.number(record.distanceMeters),
                record.distanceMethod ?? "gps-track",
                record.gpsTrackMeters.map { RunExport.number($0) } ?? "",
                record.appleDistanceMeters.map { RunExport.number($0) } ?? "",
                RunExport.number(measured.meters),
                RunExport.number(measured.trackMeters),
                RunExport.number(record.activeSeconds, decimals: 1),
                RunExport.number(record.pausedSeconds, decimals: 1),
                RunExport.number(record.end.timeIntervalSince(record.start), decimals: 1),
                "\(record.pauses.count)",
                "\(fixes.count)",
                "\(fixes.filter(\.hasUsableSpeed).count)",
                "\(measured.steps.filter(\.isSpike).count)",
                accuracies.isEmpty ? "" : RunExport.number(accuracies[accuracies.count / 2], decimals: 1),
                exportedBy.model ?? "",
                exportedBy.system ?? "",
                exportedBy.app ?? "",
                record.sport.rawValue,
            ] + Self.weatherFields(record.weather)
        }

        /// The weather columns, empty for a run without weather. No clock time: "finish" or "hour" says only
        /// which reading it is.
        static func weatherFields(_ weather: RunWeather?) -> [String] {
            guard let weather else { return Array(repeating: "", count: 9) }
            return [
                RunExport.number(weather.temperature, decimals: 1),
                weather.feelsLike.map { RunExport.number($0, decimals: 1) } ?? "",
                RunExport.number(weather.humidity * 100, decimals: 0),
                RunExport.number(weather.cloudCover * 100, decimals: 0),
                RunExport.number(weather.windSpeed, decimals: 1),
                weather.windGust.map { RunExport.number($0, decimals: 1) } ?? "",
                RunExport.number(weather.windFrom, decimals: 0),
                weather.condition,
                weather.isCurrent ? "finish" : "hour",
            ]
        }

        /// A point's row in `gps_points.csv`, a field for each of `pointColumns`, in its order.
        private func pointFields(
            _ fix: DistanceEstimator.Fix,
            index: Int,
            number: String,
            record: Record,
            step: DistanceEstimator.Step,
            active: Bool
        ) -> [String] {
            [
                number,
                "\(index + 1)",
                RunExport.number(fix.time.timeIntervalSince(record.start), decimals: 1),
                active ? "1" : "0",
                RunExport.number(step.gap),
                RunExport.number(fix.horizontalAccuracy, decimals: 1),
                RunExport.number(record.verticalAccuracies[index], decimals: 1),
                fix.speed >= 0 ? RunExport.number(fix.speed) : "",
                fix.speedAccuracy >= 0 ? RunExport.number(fix.speedAccuracy) : "",
                step.isSpike ? "1" : "0",
                RunExport.number(step.meters),
                step.counting.rawValue,
            ]
        }
    }

    /// A `Builder` on its own actor, so the main actor only copies each run out of the store and the rest
    /// happens off it.
    actor Maker {
        private var builder: Builder

        init(exportedBy: DeviceInfo, hiding: ExportPrivacy = .standard) {
            builder = Builder(exportedBy: exportedBy, hiding: hiding)
        }

        func add(_ record: Record) {
            builder.add(record)
        }

        /// The files so far, and the bytes of `choice` made from them.
        func export(_ choice: Choice) throws -> (files: Files, data: Data) {
            let files = builder.files
            return (files, try RunExport.data(for: choice, from: files))
        }
    }

    /// Whether each of `times`, oldest first, fell outside every pause. Walks the pauses alongside the times,
    /// rather than looking through every pause for each one.
    static func activeFlags(of times: [Date], pauses: [(start: Date, end: Date)]) -> [Bool] {
        // Pauses that overlap are joined, so one walk passes them in order. A pause holds its start, not its
        // end, so one that ends before it starts holds nothing.
        var joined: [(start: Date, end: Date)] = []
        for pause in pauses.sorted(by: { $0.start < $1.start }) where pause.end > pause.start {
            if let last = joined.last, pause.start <= last.end {
                joined[joined.count - 1].end = max(last.end, pause.end)
            } else {
                joined.append(pause)
            }
        }
        var flags: [Bool] = []
        flags.reserveCapacity(times.count)
        var next = 0
        for time in times {
            while next < joined.count, joined[next].end <= time { next += 1 }
            flags.append(!(next < joined.count && joined[next].start <= time))
        }
        return flags
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
    static let folderName = "Wind Run runs"

    /// What the runner can export: either file on its own, or both in a zip.
    enum Choice: String, CaseIterable, Identifiable {
        case runs
        case points
        case both

        var id: String { rawValue }

        var title: String {
            switch self {
            case .runs: "Runs"
            case .points: "GPS Points"
            case .both: "Both as a Zip"
            }
        }

        /// What the file holds. GPS Points says what `hiding` leaves out, in the runner's `unit`.
        @MainActor
        func fileDescription(hiding: ExportPrivacy = .standard, unit: DistanceUnit = .kilometers) -> String? {
            switch self {
            case .runs: "One row per finished run, with distance, duration, and device model."
            case .points: "Speed and accuracy for each GPS reading. We leave out coordinates and \(hiding.leftOutText(unit: unit))."
            case .both: nil
            }
        }

        /// The suggested file name, without a date; Files adds the extension.
        var filename: String {
            switch self {
            case .runs: "Wind Run runs"
            case .points: "Wind Run GPS points"
            case .both: "Wind Run export"
            }
        }

        var contentType: UTType {
            self == .both ? .zip : .commaSeparatedText
        }
    }

    /// The bytes of the chosen export. Only a zip too big to write can fail.
    static func data(for choice: Choice, from files: Files) throws -> Data {
        switch choice {
        case .runs: Data(files.runs.utf8)
        case .points: Data(files.points.utf8)
        case .both: try zip(files)
        }
    }

    /// Both files in a zip, holding a folder with `runs.csv` and `gps_points.csv`, written by `StoredZip` so
    /// they carry no date or time zone.
    static func zip(_ files: Files) throws -> Data {
        try StoredZip.make([
            StoredZip.Entry(path: "\(folderName)/runs.csv", data: Data(files.runs.utf8)),
            StoredZip.Entry(path: "\(folderName)/gps_points.csv", data: Data(files.points.utf8)),
        ])
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
