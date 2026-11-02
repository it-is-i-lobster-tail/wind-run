//
//  HealthWorkout.swift
//  Wind Run
//

import CoreLocation
import Foundation

/// What a finished run looks like to Apple Health: when it ran, when it paused,
/// how far it went in short stretches, and the route.
///
/// Plain values with no HealthKit types, so the conversion can be tested on its own.
struct HealthWorkout {
    /// Distance covered over a short stretch of running.
    struct DistanceSegment: Equatable {
        let start: Date
        let end: Date
        let meters: Double
    }

    /// Distance goes to Health in stretches of about this long, so Health can work out splits.
    static let segmentLength: TimeInterval = 10

    let start: Date
    let end: Date
    let pauses: [DateInterval]
    let distance: [DistanceSegment]
    let route: [CLLocation]

    /// Nil unless the run is complete.
    init?(_ run: Run) {
        guard run.status == .complete, let end = run.endDate else { return nil }
        let start = run.startDate
        let pauses = run.pauses.map { pause in
            DateInterval(start: pause.startDate, end: max(pause.startDate, pause.endDate ?? end))
        }
        // A first fix can be cached from before the start; Health wants everything inside the workout.
        let route = run.route.filter { $0.timestamp >= start && $0.timestamp <= end }

        self.start = start
        self.end = end
        self.pauses = pauses
        self.route = route.map(\.location)
        self.distance = Self.segments(
            route: route.map { ($0.timestamp, $0.location) },
            pauses: pauses,
            totalMeters: run.distanceMeters
        )
    }

    /// Splits the route into short stretches of running, leaving out anything recorded while paused.
    /// The stretches are scaled to add up to `totalMeters`, so Health shows the same distance as the app.
    static func segments(
        route: [(timestamp: Date, location: CLLocation)],
        pauses: [DateInterval],
        totalMeters: Double
    ) -> [DistanceSegment] {
        var segments: [DistanceSegment] = []
        var current: (start: Date, end: Date, meters: Double)?

        func close() {
            if let current, current.meters > 0 {
                segments.append(DistanceSegment(start: current.start, end: current.end, meters: current.meters))
            }
            current = nil
        }

        for (previous, next) in zip(route, route.dropFirst()) {
            // Matches `Run.record`: a fix that arrives while paused adds no distance.
            let isPaused = pauses.contains { $0.start <= next.timestamp && next.timestamp < $0.end }
            guard !isPaused else {
                close()
                continue
            }
            let meters = next.location.distance(from: previous.location)
            if var stretch = current {
                stretch.end = next.timestamp
                stretch.meters += meters
                current = stretch
            } else {
                // The first fix after a resume was taken while paused; start the stretch at the resume instead.
                let resume = pauses.first { $0.start <= previous.timestamp && previous.timestamp < $0.end }?.end
                current = (resume ?? previous.timestamp, next.timestamp, meters)
            }
            if let stretch = current, stretch.end.timeIntervalSince(stretch.start) >= segmentLength {
                close()
            }
        }
        close()

        let measured = segments.reduce(0) { $0 + $1.meters }
        guard measured > 0, totalMeters > 0 else { return [] }
        let scale = totalMeters / measured
        return segments.map { DistanceSegment(start: $0.start, end: $0.end, meters: $0.meters * scale) }
    }
}
