//
//  RunSummary.swift
//  Wind Run
//

import Foundation

/// One step of a structured run as it was run, named the way the runner met it.
struct RunSection: Identifiable, Equatable {
    /// The step's place in the run's step log.
    let id: Int
    /// "Warm up", "Work 2", "Recover", "Walk" or "Cool down".
    let name: String
    /// A hard step, drawn in the accent color.
    let isWork: Bool
    /// Where the step started and ended in running time.
    let startTime: TimeInterval
    let endTime: TimeInterval
    let meters: Double

    var seconds: TimeInterval { max(0, endTime - startTime) }

    /// Seconds per kilometer, or nil when the step covered too little ground to say.
    var pace: TimeInterval? {
        guard meters >= 10, seconds > 0 else { return nil }
        return seconds / (meters / 1_000)
    }
}

/// Pace at one moment of the run, against time spent running.
struct PacePoint: Hashable {
    let activeTime: TimeInterval
    var secondsPerKilometer: Double
    /// Which unbroken stretch of the line it's on. A stop or a walk too slow to chart starts the next one.
    var segment = 0
}

/// Steps a minute at one moment of the run, against time spent running.
struct CadencePoint: Hashable {
    let activeTime: TimeInterval
    var stepsPerMinute: Double
    /// Which unbroken stretch of the line it's on. A stretch with no steps counted starts the next one.
    var segment = 0
}


/// Height above sea level at one moment of the run, against time spent running.
struct ElevationPoint: Hashable {
    let activeTime: TimeInterval
    var meters: Double
    var segment = 0
}

/// How much the run climbed and dropped, and the profile to chart.
struct ElevationSummary: Equatable {
    let gain: Double
    let loss: Double
    let profile: [ElevationPoint]
    /// The profile is the climb from the start, not height above the sea, when GPS never gave a level.
    var isRelative = false
}

extension Run {
    var chartPauseBuffers: ChartPauseBuffers {
        ChartPauseBuffers(pauses.map { ($0.startDate, $0.endDate) })
    }

    /// Both use the same active clock. Only the drawn series drops the transitions around pauses.
    func heartRateChart(buffers: ChartPauseBuffers) -> (points: [HeartRatePoint], stats: HeartRateStats?) {
        var raw: [HeartRatePoint] = []
        var plotted: [HeartRatePoint] = []
        for sample in heartRateSamples {
            var point = heartRatePoint(sample)
            raw.append(point)
            if let segment = buffers.segment(from: sample.timestamp, through: sample.timestamp) {
                point.segment = segment
                plotted.append(point)
            }
        }
        return (plotted.chartSmoothed(value: \.beatsPerMinute, segment: \.segment), Self.heartRateStats(of: raw))
    }

    /// A chart point this much further on than the spacing between points means some were left out
    /// there, so the line breaks.
    static let chartGapFactor = 1.5
    /// Each pace and cadence point is taken over this many seconds before it.
    static let chartWindow: TimeInterval = 30

    /// The time between pace and cadence points: about one every 10 seconds, so a long run doesn't draw
    /// thousands of points.
    static func chartSpacing(span: TimeInterval) -> TimeInterval {
        max(10, span / 400)
    }

    /// Whether a point at `time` is far enough past the one before, at `lastTime`, that some were left out
    /// between them, so the line breaks there.
    static func startsNewChartSegment(at time: TimeInterval, after lastTime: TimeInterval, spacing: TimeInterval) -> Bool {
        time - lastTime > spacing * chartGapFactor + chartWindow / 2
    }

    /// Each step as it was run, leaving out steps skipped when the run finished early.
    /// Empty for a run without steps.
    var sections: [RunSection] {
        let timeline = intervalPlan?.timeline ?? []
        let workCount = timeline.filter { $0.kind == .work }.count
        var workNumber = 0
        return stepLog.compactMap { step in
            guard timeline.indices.contains(step.index) else { return nil }
            let planned = timeline[step.index]
            let isWork = planned.kind == .work && !planned.isWalk
            if isWork { workNumber += 1 }
            guard step.seconds >= 1 else { return nil }
            return RunSection(
                id: step.index,
                name: isWork && workCount > 1 ? "\(planned.name) \(workNumber)" : planned.name,
                isWork: isWork,
                startTime: step.startElapsed,
                endTime: step.endElapsed,
                meters: step.meters
            )
        }
    }

    /// Pace through the run, each point the pace over the half minute before it. Standing still
    /// and walking slower than 15 minutes a kilometer leave a gap, not a spike.
    var paceTimeline: [PacePoint] {
        Self.paceTimeline(activeRoute, buffers: chartPauseBuffers)
    }

    /// The same, from fixes already worked out with `activeRoute`.
    static func paceTimeline(_ fixes: [ActiveFix], buffers: ChartPauseBuffers) -> [PacePoint] {
        let track = fixes.filter { fix in
            let date = fix.sample.timestamp
            return buffers.segment(from: date, through: date) != nil
        }
        guard track.count > 1, let first = track.first, let last = track.last else { return [] }
        let window = Self.chartWindow
        let slowest: TimeInterval = 15 * 60
        let spacing = Self.chartSpacing(span: last.time - first.time)
        var points: [PacePoint] = []
        var back = 0
        var lastTime = -TimeInterval.infinity
        var segment = 0
        for (index, current) in track.enumerated() {
            if current.stretch != track[back].stretch {
                back = index
                lastTime = -.infinity
            }
            guard current.time - lastTime >= spacing else { continue }
            while back < index, current.time - track[back + 1].time >= window {
                back += 1
            }
            let from = track[back]
            let seconds = current.time - from.time
            let meters = current.meters - from.meters
            guard seconds >= window / 2, meters > 0 else { continue }
            let pace = seconds / (meters / 1_000)
            guard pace <= slowest else { continue }
            if !points.isEmpty, Self.startsNewChartSegment(at: current.time, after: lastTime, spacing: spacing) {
                segment += 1
            }
            points.append(PacePoint(activeTime: current.time, secondsPerKilometer: pace, segment: segment))
            lastTime = current.time
        }
        return points.chartSmoothed(value: \.secondsPerKilometer, segment: \.segment)
    }

    /// Steps a minute through the run, each point the steps over the half minute before it. Pauses
    /// count no steps, so they leave no dip.
    var cadenceTimeline: [CadencePoint] {
        cadenceSeries(buffers: chartPauseBuffers).chart
    }

    func cadenceSeries(buffers: ChartPauseBuffers) -> (chart: [CadencePoint], map: [CadencePoint]) {
        let counts = stepCounts
        let map = cadencePoints(from: counts, buffers: ChartPauseBuffers())
        let plotted = buffers.isEmpty ? map : cadencePoints(from: counts, buffers: buffers)
        return (plotted.chartSmoothed(value: \.stepsPerMinute, segment: \.segment), map)
    }

    /// The map uses the original cadence values. The chart also excludes counts touching a pause buffer.
    func cadencePoints(from counts: [StepCountSample], buffers: ChartPauseBuffers) -> [CadencePoint] {
        let stretches = counts
            .sorted { $0.start < $1.start }
            .compactMap { sample -> (start: TimeInterval, end: TimeInterval, count: Double, stretch: Int)? in
                guard let stretch = buffers.segment(from: sample.start, through: sample.end) else { return nil }
                return (activeTime(at: sample.start), activeTime(at: sample.end), sample.count, stretch)
            }
            .filter { $0.end > $0.start }
        guard stretches.count > 1, let firstStretch = stretches.first, let lastStretch = stretches.last else { return [] }
        let window = Self.chartWindow
        let spacing = Self.chartSpacing(span: lastStretch.end - firstStretch.start)
        var points: [CadencePoint] = []
        var lastTime = -TimeInterval.infinity
        var segment = 0
        for index in stretches.indices {
            if index > 0, stretches[index].stretch != stretches[index - 1].stretch {
                lastTime = -.infinity
            }
            guard stretches[index].end - lastTime >= spacing else { continue }
            let end = stretches[index].end
            var first = index
            var steps = stretches[index].count
            while first > 0, stretches[first - 1].stretch == stretches[index].stretch, stretches[first - 1].start >= end - window {
                first -= 1
                steps += stretches[first].count
            }
            let seconds = end - stretches[first].start
            guard seconds >= window / 2 else { continue }
            if !points.isEmpty, Self.startsNewChartSegment(at: end, after: lastTime, spacing: spacing) {
                segment += 1
            }
            points.append(CadencePoint(activeTime: end, stepsPerMinute: steps / seconds * 60, segment: segment))
            lastTime = end
        }
        return points
    }

    /// Steps a minute over the time spent running, or nil without steps or running time.
    static func meanCadence(steps: Double?, seconds: TimeInterval) -> Double? {
        steps.flatMap { seconds > 0 ? $0 / seconds * 60 : nil }
    }

    /// Climb and drop from the barometer, or from the fixes that carry a good GPS altitude, or nil when
    /// there's neither. Changes under the noise level are taken as wobble, so a flat run doesn't add up to a hill.
    var elevation: ElevationSummary? {
        Self.elevation(altitudeTrack)
    }

    /// The same, from a track already worked out.
    static func elevation(_ track: AltitudeTrack?) -> ElevationSummary? {
        guard let track else { return nil }
        let readings = track.points
        let (gain, loss) = climbAndDrop(track)
        let stride = max(1, readings.count / 300)
        let profile = Swift.stride(from: 0, to: readings.count, by: stride).map { index in
            ElevationPoint(activeTime: readings[index].time, meters: readings[index].altitude, segment: readings[index].stretch)
        }
        return ElevationSummary(gain: gain, loss: loss, profile: profile.chartSmoothed(value: \.meters, segment: \.segment), isRelative: track.isRelative)
    }

    /// Just the climb, for the coach, without the profile the charts draw. 0 when the run has no heights.
    var climbGain: Double {
        altitudeTrack.map { Self.climbAndDrop($0).gain } ?? 0
    }

    /// The climb and the drop along a track, leaving out changes under the noise level.
    static func climbAndDrop(_ track: AltitudeTrack) -> (gain: Double, loss: Double) {
        let readings = track.points
        guard let first = readings.first else { return (0, 0) }
        let threshold = climbNoise(for: track.source)
        var gain = 0.0
        var loss = 0.0
        var anchor = first.altitude
        for reading in readings.dropFirst() {
            let change = reading.altitude - anchor
            if change >= threshold {
                gain += change
                anchor = reading.altitude
            } else if change <= -threshold {
                loss -= change
                anchor = reading.altitude
            }
        }
        return (gain, loss)
    }

    /// The smallest change in height that counts as climbing or dropping: 2 m for GPS, whose altitude is
    /// noisy, and a meter for the barometer.
    static func climbNoise(for source: AltitudeSource) -> Double {
        switch source {
        case .barometer: 1
        case .gps: 2
        }
    }
}
