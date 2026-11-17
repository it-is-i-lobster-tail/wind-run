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
    let secondsPerKilometer: Double
    /// Which unbroken stretch of the line it's on. A stop or a walk too slow to chart starts the next one.
    var segment = 0
}

/// Steps a minute at one moment of the run, against time spent running.
struct CadencePoint: Hashable {
    let activeTime: TimeInterval
    let stepsPerMinute: Double
    /// Which unbroken stretch of the line it's on. A stretch with no steps counted starts the next one.
    var segment = 0
}


/// Height above sea level at one moment of the run, against time spent running.
struct ElevationPoint: Hashable {
    let activeTime: TimeInterval
    let meters: Double
}

/// How much the run climbed and dropped, and the profile to chart.
struct ElevationSummary: Equatable {
    let gain: Double
    let loss: Double
    let profile: [ElevationPoint]
}

extension Run {
    /// A chart point this much further on than the spacing between points means some were left out
    /// there, so the line breaks.
    static let chartGapFactor = 1.5

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
        Self.paceTimeline(activeRoute)
    }

    /// The same, from fixes already worked out with `activeRoute`.
    static func paceTimeline(_ track: [ActiveFix]) -> [PacePoint] {
        guard track.count > 1 else { return [] }
        let window: TimeInterval = 30
        let slowest: TimeInterval = 15 * 60
        // About one point every 10 seconds, so a long run doesn't draw thousands of points.
        let spacing = max(10, (track.last!.time - track.first!.time) / 400)
        var points: [PacePoint] = []
        var back = 0
        var lastTime = -TimeInterval.infinity
        var segment = 0
        for current in track where current.time - lastTime >= spacing {
            while back < track.count - 1, current.time - track[back + 1].time >= window {
                back += 1
            }
            let from = track[back]
            let seconds = current.time - from.time
            let meters = current.meters - from.meters
            guard seconds >= window / 2, meters > 0 else { continue }
            let pace = seconds / (meters / 1_000)
            guard pace <= slowest else { continue }
            if !points.isEmpty, current.time - lastTime > spacing * Self.chartGapFactor + window / 2 {
                segment += 1
            }
            points.append(PacePoint(activeTime: current.time, secondsPerKilometer: pace, segment: segment))
            lastTime = current.time
        }
        return points
    }

    /// Steps a minute through the run, each point the steps over the half minute before it. Pauses
    /// count no steps, so they leave no dip.
    var cadenceTimeline: [CadencePoint] {
        let stretches = stepCounts
            .sorted { $0.start < $1.start }
            .map { (start: activeTime(at: $0.start), end: activeTime(at: $0.end), count: $0.count) }
            .filter { $0.end > $0.start }
        guard stretches.count > 1 else { return [] }
        let window: TimeInterval = 30
        // About one point every 10 seconds, so a long run doesn't draw thousands of points.
        let spacing = max(10, (stretches.last!.end - stretches.first!.start) / 400)
        var points: [CadencePoint] = []
        var lastTime = -TimeInterval.infinity
        var segment = 0
        for index in stretches.indices where stretches[index].end - lastTime >= spacing {
            let end = stretches[index].end
            var first = index
            var steps = stretches[index].count
            while first > 0, stretches[first - 1].start >= end - window {
                first -= 1
                steps += stretches[first].count
            }
            let seconds = end - stretches[first].start
            guard seconds >= window / 2 else { continue }
            if !points.isEmpty, end - lastTime > spacing * Self.chartGapFactor + window / 2 {
                segment += 1
            }
            points.append(CadencePoint(activeTime: end, stepsPerMinute: steps / seconds * 60, segment: segment))
            lastTime = end
        }
        return points
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
            ElevationPoint(activeTime: readings[index].time, meters: readings[index].altitude)
        }
        return ElevationSummary(gain: gain, loss: loss, profile: profile)
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
