//
//  RunSummary.swift
//  Wind Run
//

import CoreLocation
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

/// A stretch of the route to draw in one style: the hard steps in the accent color, the rest muted.
struct RouteSegment: Identifiable {
    let id: Int
    let isWork: Bool
    let coordinates: [CLLocationCoordinate2D]
}

extension Run {
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
        let track = activeRoute
        guard track.count > 1 else { return [] }
        let window: TimeInterval = 30
        let slowest: TimeInterval = 15 * 60
        // About one point every 10 seconds, so a long run doesn't draw thousands of points.
        let spacing = max(10, (track.last!.time - track.first!.time) / 400)
        var points: [PacePoint] = []
        var back = 0
        var lastTime = -TimeInterval.infinity
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
            points.append(PacePoint(activeTime: current.time, secondsPerKilometer: pace))
            lastTime = current.time
        }
        return points
    }

    /// Climb and drop from the barometer, or from the fixes that carry a good GPS altitude, or nil when
    /// there's neither. Changes under the noise level are taken as wobble, so a flat run doesn't add up to a hill.
    var elevation: ElevationSummary? {
        guard let track = altitudeTrack else { return nil }
        let readings = track.points
        let threshold = Self.climbNoise(for: track.source)
        var gain = 0.0
        var loss = 0.0
        var anchor = readings[0].altitude
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
        let stride = max(1, readings.count / 300)
        let profile = Swift.stride(from: 0, to: readings.count, by: stride).map { index in
            ElevationPoint(activeTime: readings[index].time, meters: readings[index].altitude)
        }
        return ElevationSummary(gain: gain, loss: loss, profile: profile)
    }

    /// The smallest change in height that counts as climbing or dropping: 2 m for GPS, whose altitude is
    /// noisy, and a meter for the barometer.
    static func climbNoise(for source: AltitudeSource) -> Double {
        switch source {
        case .barometer: 1
        case .gps: 2
        }
    }

    /// The route cut where the run changes between hard and easy steps, or one stretch for a run
    /// without steps. Each stretch starts where the last one ended, so the line has no gaps.
    func routeSegments(sections: [RunSection]) -> [RouteSegment] {
        let route = self.route
        guard route.count > 1 else { return [] }
        let coordinates = route.map(\.coordinate)
        guard !sections.isEmpty else { return [RouteSegment(id: 0, isWork: false, coordinates: coordinates)] }

        func isWork(at sample: RouteSample) -> Bool {
            let time = activeTime(at: sample.timestamp)
            // Fixes taken in a pause share the running time of its start, so they go with the step it paused.
            return sections.first { time >= $0.startTime && time <= $0.endTime }?.isWork ?? false
        }
        var segments: [RouteSegment] = []
        var current = [coordinates[0]]
        var currentIsWork = isWork(at: route[0])
        for index in route.indices.dropFirst() {
            let work = isWork(at: route[index])
            current.append(coordinates[index])
            if work != currentIsWork {
                segments.append(RouteSegment(id: segments.count, isWork: currentIsWork, coordinates: current))
                current = [coordinates[index]]
                currentIsWork = work
            }
        }
        if current.count > 1 {
            segments.append(RouteSegment(id: segments.count, isWork: currentIsWork, coordinates: current))
        }
        return segments
    }
}
