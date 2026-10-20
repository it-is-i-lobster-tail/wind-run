//
//  RunDataGate.swift
//  Wind Run
//

import Foundation

/// Why a run gets no pace analysis, or doesn't count at all (FB-2).
enum DataGateReason: String, Codable, Hashable {
    /// Under 500 m: dropped.
    case tooShort
    /// Over 100 km: dropped.
    case tooLong
    /// Another app's copy of a Wind Run run: the same run, never an extra one.
    case duplicate
    /// More than 20% of moving time with poor GPS.
    case poorGPS
    /// Marked "bad data" (AD-1), or FB-3's "Watch or GPS problem".
    case badData
    /// Entered by hand or recorded without GPS: volume in minutes only.
    case manual
    /// A free run-walk with no step data: walk breaks would read as fade.
    case runWalkWithoutSteps
    /// The halves' climb differs by 20 m or more: the hill explanation instead of pace analysis (FB-5).
    case hilly
}

/// The data gate's verdict for one run, with its reasons (FB-2).
struct DataCheck: Hashable {
    var gate: DataGate
    var reasons: [DataGateReason]
    /// Pace from the belt or the runner's distance, compared only with treadmill runs.
    var treadmill: Bool

    var allowsPaceAnalysis: Bool { gate == .passes }

    var hilly: Bool { reasons.contains(.hilly) }

    /// Patchy GPS or a bad-data mark: FB-5's data message.
    var dataProblem: Bool { reasons.contains(.poorGPS) || reasons.contains(.badData) }
}

/// FB-2: every run passes these checks before any pace analysis.
enum RunDataGate {
    static let minimumMeters = 500.0
    static let maximumMeters = 100_000.0
    static let poorGPSShare = 0.20
    /// FB-2's climb rule, until an elevation model gives grade-adjusted pace.
    static let climbDifference = 20.0
    /// Differences of 5% or less are never treated as real change.
    static let noise = 0.05

    static func check(_ run: LoggedRun, runs: [LoggedRun]) -> DataCheck {
        if isDuplicate(run, runs: runs) { return DataCheck(gate: .dropped, reasons: [.duplicate], treadmill: false) }
        if run.meters > 0, run.meters < minimumMeters { return DataCheck(gate: .dropped, reasons: [.tooShort], treadmill: false) }
        if run.meters > maximumMeters { return DataCheck(gate: .dropped, reasons: [.tooLong], treadmill: false) }
        let treadmill = run.source == .treadmill || run.checkIn?.treadmill == true
        var reasons: [DataGateReason] = []
        if run.source == .manual || run.meters <= 0 { reasons.append(.manual) }
        if run.checkIn?.badData == true || run.checkIn?.effectiveWhatHappened == .dataProblem { reasons.append(.badData) }
        if !treadmill, (run.track?.poorGPSShare ?? 0) > poorGPSShare { reasons.append(.poorGPS) }
        if isRunWalk(run), !(run.steps ?? []).contains(where: \.isWork) { reasons.append(.runWalkWithoutSteps) }
        if !treadmill, isHilly(run) { reasons.append(.hilly) }
        return DataCheck(gate: reasons.isEmpty ? .passes : .volumeOnly, reasons: reasons, treadmill: treadmill)
    }

    /// The runs the coach counts: duplicates and runs under 500 m or over 100 km are dropped (FB-2).
    static func usableRuns(_ runs: [LoggedRun]) -> [LoggedRun] {
        runs.filter { check($0, runs: runs).gate != .dropped }
    }

    /// A run that overlaps another the coach prefers: Wind Run's own over another app's, then the longer one.
    static func isDuplicate(_ run: LoggedRun, runs: [LoggedRun]) -> Bool {
        runs.contains { other in
            guard other.id != run.id, max(run.start, other.start) < min(run.end, other.end) else { return false }
            let runOwn = run.source != .otherApp
            let otherOwn = other.source != .otherApp
            if runOwn != otherOwn { return otherOwn }
            if other.movingSeconds != run.movingSeconds { return other.movingSeconds > run.movingSeconds }
            return other.id.uuidString < run.id.uuidString
        }
    }

    static func isRunWalk(_ run: LoggedRun) -> Bool {
        run.checkIn?.runWalk == true || (run.walkingSeconds ?? 0) > 0
    }

    /// FB-2: halves whose climb differs by 20 m or more.
    static func isHilly(_ run: LoggedRun) -> Bool {
        guard let track = run.track else { return false }
        return abs(track.climbFirstHalf - track.climbSecondHalf) >= climbDifference
    }
}

/// Distance against moving time through a run or a segment, from its splits, linear inside each split.
struct PaceProfile: Hashable {
    /// Cumulative meters and seconds at each split boundary, from (0, 0).
    private(set) var meters: [Double]
    private(set) var seconds: [Double]

    init?(splits: [Split]) {
        let usable = splits.filter { $0.meters > 0 && $0.seconds > 0 }
        guard !usable.isEmpty else { return nil }
        var meters = [0.0]
        var seconds = [0.0]
        for split in usable {
            meters.append(meters[meters.count - 1] + split.meters)
            seconds.append(seconds[seconds.count - 1] + split.seconds)
        }
        self.meters = meters
        self.seconds = seconds
    }

    var totalMeters: Double { meters[meters.count - 1] }
    var totalSeconds: Double { seconds[seconds.count - 1] }

    /// Seconds per km over the whole profile.
    var pace: Double { totalSeconds / totalMeters * 1_000 }

    /// Moving seconds at a distance.
    func time(at distance: Double) -> Double {
        interpolate(distance, from: meters, to: seconds)
    }

    /// Distance at a moving time.
    func distance(at time: Double) -> Double {
        interpolate(time, from: seconds, to: meters)
    }

    /// Seconds per km between two distances, or nil for a stretch under 100 m.
    func pace(from start: Double, to end: Double) -> Double? {
        let start = start.clamped(to: 0 ... totalMeters)
        let end = end.clamped(to: 0 ... totalMeters)
        guard end - start >= 100 else { return nil }
        return (time(at: end) - time(at: start)) / (end - start) * 1_000
    }

    /// Seconds per km between two moving times.
    func pace(fromTime start: Double, toTime end: Double) -> Double? {
        pace(from: distance(at: start), to: distance(at: end))
    }

    private func interpolate(_ value: Double, from keys: [Double], to values: [Double]) -> Double {
        guard value > keys[0] else { return values[0] }
        for index in 1 ..< keys.count where value <= keys[index] {
            let span = keys[index] - keys[index - 1]
            let fraction = span > 0 ? (value - keys[index - 1]) / span : 1
            return values[index - 1] + fraction * (values[index] - values[index - 1])
        }
        return values[values.count - 1]
    }
}
