//
//  DistanceEstimator.swift
//  Wind Run
//

import CoreLocation
import Foundation

/// How far a run went, worked out from its GPS fixes one at a time.
///
/// Adding up the straight lines between fixes reads long: at running pace fixes a second apart are
/// only two or three meters apart, about the size of the error in each one, and every sideways wobble
/// adds length. So each fix's own speed, which the GPS measures from the satellite signal and which
/// carries none of that position wobble, is multiplied by the seconds since the last fix. A fix with no
/// usable speed falls back to the straight line from the last good fix. A fix that jumps further than a
/// runner could go is a spike: it adds nothing by the straight line and never becomes a starting point.
///
/// The research behind this, and the trade-offs against smoothing the track, are in the project's
/// "GPS distance accuracy: smoothing options" write-up.
nonisolated struct DistanceEstimator {
    /// Names this way of measuring, kept with each run so an export can tell old and new runs apart.
    static let method = "speed-v1"
    /// Apple's workout distance, for a run that never got a GPS fix.
    static let appleMethod = "apple-workout"
    /// Apple's workout distance until GPS found its first fix, then this estimator from there.
    static let appleThenSpeedMethod = "apple-then-speed-v1"

    /// Faster than any distance runner, so a fix that implies more is a spike.
    static let maximumSpeed: CLLocationSpeed = 9
    /// A speed less sure than this is passed over for the straight line.
    static let maximumSpeedAccuracy: CLLocationSpeed = 2
    /// Slower than this is GPS noise while standing, so it adds nothing.
    static let standingSpeed: CLLocationSpeed = 0.4
    /// Over a longer gap between fixes the speed at its end may not hold, so the straight line counts.
    static let longestSpeedGap: TimeInterval = 10

    /// What the estimator needs from a fix.
    struct Fix: Equatable {
        var time: Date
        var latitude: Double
        var longitude: Double
        var horizontalAccuracy: Double
        /// Meters per second, negative when unknown.
        var speed: Double
        /// Meters per second, negative when unknown.
        var speedAccuracy: Double

        var location: CLLocation {
            CLLocation(latitude: latitude, longitude: longitude)
        }

        /// Whether the speed can be used: known, and when its accuracy is known, sure enough.
        /// Runs recorded before speed accuracy was kept have none, and their speed is used as it is.
        var hasUsableSpeed: Bool {
            speed >= 0 && speedAccuracy <= DistanceEstimator.maximumSpeedAccuracy
        }
    }

    /// How a fix was counted.
    enum Counting: String {
        /// Its speed times the seconds since the last fix.
        case speed
        /// The straight line from the last good fix.
        case track
        /// Nothing: paused, a spike with no speed, or the first fix.
        case none
    }

    /// What one fix added.
    struct Step: Equatable {
        /// What this fix adds to the run's distance.
        var meters: Double
        /// The straight line from the fix before, the old way of measuring, kept for comparison.
        var gap: Double
        /// True when the fix jumped further than a runner could go.
        var isSpike: Bool
        var counting: Counting
    }

    /// The fix before the next one.
    private(set) var previous: Fix?
    /// The newest fix that wasn't a spike: where the straight line starts.
    private(set) var anchor: Fix?
    /// The time up to which the run has been counted since `anchor`, when speed counted fixes after it.
    private var countedUntil: Date?

    private let speedLimit: CLLocationSpeed

    /// Starts after `previous`, such as the last fix of a run being picked up again.
    init(previous: Fix? = nil, sport: WorkoutSport = .running) {
        // Allow fast descents while still rejecting implausible GPS jumps.
        self.speedLimit = sport == .cycling ? 35 : Self.maximumSpeed
        self.previous = previous
        self.anchor = previous
    }

    /// Takes the next fix. While `counts` is false (the run is paused) the fix adds nothing, but the
    /// next stretch starts from it, so ground covered while paused never counts.
    mutating func add(_ fix: Fix, counts: Bool = true) -> Step {
        guard let previous, fix.time > previous.time else {
            if self.previous == nil {
                start(at: fix)
            }
            return Step(meters: 0, gap: 0, isSpike: false, counting: .none)
        }
        let gap = fix.location.distance(from: previous.location)
        guard counts else {
            start(at: fix)
            return Step(meters: 0, gap: gap, isSpike: false, counting: .none)
        }

        let anchor = self.anchor ?? previous
        let fromAnchor = fix.location.distance(from: anchor.location)
        let sinceAnchor = fix.time.timeIntervalSince(anchor.time)
        let isSpike = Self.isSpike(fix, meters: fromAnchor, seconds: sinceAnchor, speedLimit: speedLimit)
        let seconds = fix.time.timeIntervalSince(previous.time)

        var step = Step(meters: 0, gap: gap, isSpike: isSpike, counting: .none)
        if seconds <= Self.longestSpeedGap, fix.hasUsableSpeed, fix.speed <= speedLimit {
            step.meters = fix.speed >= Self.standingSpeed ? fix.speed * seconds : 0
            step.counting = .speed
            countedUntil = fix.time
        } else if !isSpike {
            // Only the part of the line speed hasn't already counted.
            let uncounted = fix.time.timeIntervalSince(max(anchor.time, countedUntil ?? anchor.time))
            let share = sinceAnchor > 0 ? min(1, max(0, uncounted / sinceAnchor)) : 1
            step.meters = fromAnchor * share
            step.counting = .track
        }

        self.previous = fix
        if !isSpike {
            self.anchor = fix
            countedUntil = nil
        }
        return step
    }

    private mutating func start(at fix: Fix) {
        previous = fix
        anchor = fix
        countedUntil = nil
    }

    /// A fix is a spike when getting to it from the last good fix would take more than a runner's top
    /// speed, or when it's much further than its own measured speed allows and further than its accuracy.
    static func isSpike(_ fix: Fix, meters: Double, seconds: TimeInterval, speedLimit: Double = maximumSpeed) -> Bool {
        guard seconds > 0 else { return false }
        let implied = meters / seconds
        if implied > speedLimit { return true }
        if fix.speed >= 0, implied > max(2.5 * fix.speed, fix.speed + 3), meters > max(fix.horizontalAccuracy, 5) {
            return true
        }
        return false
    }
}

extension DistanceEstimator.Fix {
    /// Not tied to the main actor, so a run (a SwiftData model, which isn't either) can measure its own fixes.
    nonisolated init(_ sample: RouteSample) {
        self.init(
            time: sample.timestampValue,
            latitude: sample.latitudeValue,
            longitude: sample.longitudeValue,
            horizontalAccuracy: sample.horizontalAccuracyValue,
            speed: sample.speedValue,
            speedAccuracy: sample.speedAccuracyValue
        )
    }

    /// The same, from a fix already read out of the store.
    nonisolated init(_ reading: RouteReading) {
        self.init(
            time: reading.timestamp,
            latitude: reading.latitudeValue,
            longitude: reading.longitudeValue,
            horizontalAccuracy: reading.horizontalAccuracyValue,
            speed: reading.speedValue,
            speedAccuracy: reading.speedAccuracyValue
        )
    }
}

/// A whole route measured again, fix by fix.
nonisolated struct MeasuredRoute {
    /// One entry per fix, in order.
    var steps: [DistanceEstimator.Step]
    /// The distance by `DistanceEstimator`.
    var meters: Double
    /// The straight lines between fixes while running, as runs were measured before.
    var trackMeters: Double

    /// Measures fixes in time order, counting only those `isActive` says were taken while running.
    init(_ fixes: [DistanceEstimator.Fix], isActive: (Date) -> Bool) {
        self.init(fixes, active: fixes.map { isActive($0.time) })
    }

    /// The same, with whether each fix was taken while running already worked out, one flag per fix. A fix
    /// with no flag isn't counted.
    init(_ fixes: [DistanceEstimator.Fix], active flags: [Bool], sport: WorkoutSport = .running) {
        var estimator = DistanceEstimator(sport: sport)
        var steps: [DistanceEstimator.Step] = []
        steps.reserveCapacity(fixes.count)
        var meters = 0.0
        var trackMeters = 0.0
        for (index, fix) in fixes.enumerated() {
            let active = index < flags.count && flags[index]
            let step = estimator.add(fix, counts: active)
            steps.append(step)
            meters += step.meters
            if active { trackMeters += step.gap }
        }
        self.steps = steps
        self.meters = meters
        self.trackMeters = trackMeters
    }
}
