//
//  DistanceEstimator.swift
//  Wind Run
//

import CoreLocation
import Foundation

/// How far a run went, worked out from its GPS fixes one at a time.
///
/// Adding up the straight lines between raw fixes reads long when the fixes wobble: at running pace fixes a
/// second apart are only two or three meters apart, about the size of the error in each one, and every
/// sideways wobble adds length. So the fixes are first smoothed by a small Kalman filter that expects a
/// runner to keep a steady speed and heading from one second to the next, trusting each fix as much as its
/// own accuracy says, and the run's distance is the line through the smoothed positions. A fix that jumps
/// further than a runner could go is a spike: it's left out and never becomes a starting point. A fix whose
/// own speed says the runner is standing adds nothing, so waiting at a crossing doesn't creep up.
///
/// The fixes' own reported speed isn't multiplied by time any more ("speed-v1"): on iPhone 17 Pro with
/// iOS 27 it read 5 to 18% under the real pace on every run compared, while the GPS line matched a
/// Garmin watch to within 0.2%.
nonisolated struct DistanceEstimator {
    /// Names this way of measuring, kept with each run so an export can tell old and new runs apart.
    static let method = "smoothed-track-v1"
    /// Apple's workout distance, for a run that never got a GPS fix.
    static let appleMethod = "apple-workout"
    /// Apple's workout distance until GPS found its first fix, then this estimator from there.
    static let appleThenTrackMethod = "apple-then-smoothed-track-v1"
    /// The earlier way: each fix's reported speed times the seconds since the last. It read short, so runs
    /// measured this way are measured again (`DistanceRemeasure`).
    static let speedMethod = "speed-v1"
    /// Apple's distance until the first fix, then `speedMethod`.
    static let appleThenSpeedMethod = "apple-then-speed-v1"

    /// Faster than any distance runner, so a fix that implies more is a spike.
    static let maximumSpeed: CLLocationSpeed = 9
    /// A fix's own speed below this means the runner is standing, so the fix adds nothing.
    static let standingSpeed: CLLocationSpeed = 0.4
    /// After a longer gap between fixes the smoothing starts again from the new fix, and the gap counts as
    /// the straight line across it.
    static let longestSmoothedGap: TimeInterval = 10
    /// How quickly the filter lets a runner's speed and heading change, in m/s². Tuned on simulated runs:
    /// lower cuts more GPS noise but rounds off tight turns; at 1 it never read short of the true distance,
    /// while it took rough fixes (+16 to 19% by the raw line) down to about +5%.
    static let processNoise: Double = 1
    /// How unsure the runner's speed is when smoothing starts, in m/s.
    static let startingSpeedSpread: Double = 3

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

        /// Whether the speed can be used: known, and when its accuracy is known, no worse than 2 m/s.
        var hasUsableSpeed: Bool {
            speed >= 0 && speedAccuracy <= 2
        }

        /// Whether the fix's own speed says the runner is standing still.
        var isStanding: Bool {
            hasUsableSpeed && speed < DistanceEstimator.standingSpeed
        }
    }

    /// How a fix was counted.
    enum Counting: String {
        /// Along the smoothed line.
        case smoothed
        /// The straight line across a long gap, where smoothing started again.
        case track
        /// Nothing: paused, standing, a spike, or the first fix.
        case none
    }

    /// What one fix added.
    struct Step: Equatable {
        /// What this fix adds to the run's distance.
        var meters: Double
        /// The straight line from the fix before, the raw way of measuring, kept for comparison.
        var gap: Double
        /// True when the fix jumped further than a runner could go.
        var isSpike: Bool
        var counting: Counting
    }

    /// The smoothed position and velocity, in meters on a flat map around `origin`. Both directions share
    /// one covariance, since they're measured alike.
    private struct Filter {
        var x: Double
        var y: Double
        var vx: Double = 0
        var vy: Double = 0
        /// Covariance of position, position with speed, and speed.
        var pp: Double
        var pv: Double = 0
        var vv: Double
        var time: Date

        init(x: Double, y: Double, accuracy: Double, time: Date) {
            self.x = x
            self.y = y
            pp = DistanceEstimator.variance(accuracy)
            vv = DistanceEstimator.startingSpeedSpread * DistanceEstimator.startingSpeedSpread
            self.time = time
        }

        mutating func predict(to date: Date) {
            let dt = date.timeIntervalSince(time)
            guard dt > 0 else { return }
            let q = DistanceEstimator.processNoise * DistanceEstimator.processNoise
            x += vx * dt
            y += vy * dt
            pp += 2 * dt * pv + dt * dt * vv + q * dt * dt * dt * dt / 4
            pv += dt * vv + q * dt * dt * dt / 2
            vv += q * dt * dt
            time = date
        }

        mutating func update(x mx: Double, y my: Double, accuracy: Double) {
            let s = pp + DistanceEstimator.variance(accuracy)
            let kp = pp / s
            let kv = pv / s
            let dx = mx - x
            let dy = my - y
            x += kp * dx
            y += kp * dy
            vx += kv * dx
            vy += kv * dy
            vv -= kv * pv
            pv *= 1 - kp
            pp *= 1 - kp
        }
    }

    /// The fix before the next one.
    private(set) var previous: Fix?
    /// The newest fix that wasn't a spike: what the next fix is checked against.
    private(set) var anchor: Fix?
    private var filter: Filter?
    /// Where the flat map is centered: the first fix seen.
    private var origin: (latitude: Double, longitude: Double, metersPerDegreeLongitude: Double)?

    private let speedLimit: CLLocationSpeed

    /// Starts after `previous`, such as the last fix of a run being picked up again.
    init(previous: Fix? = nil, sport: WorkoutSport = .running) {
        // Allow fast descents while still rejecting implausible GPS jumps.
        self.speedLimit = sport == .cycling ? 35 : Self.maximumSpeed
        if let previous {
            start(at: previous)
        }
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
        guard counts, var filter else {
            start(at: fix)
            return Step(meters: 0, gap: gap, isSpike: false, counting: .none)
        }

        let anchor = self.anchor ?? previous
        let fromAnchor = fix.location.distance(from: anchor.location)
        let sinceAnchor = fix.time.timeIntervalSince(anchor.time)
        let isSpike = Self.isSpike(fix, meters: fromAnchor, seconds: sinceAnchor, speedLimit: speedLimit)
        self.previous = fix
        guard !isSpike else {
            return Step(meters: 0, gap: gap, isSpike: true, counting: .none)
        }
        self.anchor = fix

        let point = flat(fix)
        let before = (x: filter.x, y: filter.y)
        var step = Step(meters: 0, gap: gap, isSpike: false, counting: .smoothed)
        if fix.time.timeIntervalSince(filter.time) > Self.longestSmoothedGap {
            // Too long to smooth across: start again at this fix, and count the straight line to it.
            filter = Filter(x: point.x, y: point.y, accuracy: fix.horizontalAccuracy, time: fix.time)
            step.counting = .track
        } else {
            filter.predict(to: fix.time)
            filter.update(x: point.x, y: point.y, accuracy: fix.horizontalAccuracy)
        }
        let moved = ((filter.x - before.x) * (filter.x - before.x) + (filter.y - before.y) * (filter.y - before.y)).squareRoot()
        if fix.isStanding {
            step.counting = .none
        } else {
            step.meters = moved
        }
        self.filter = filter
        return step
    }

    private mutating func start(at fix: Fix) {
        previous = fix
        anchor = fix
        let point = flat(fix)
        filter = Filter(x: point.x, y: point.y, accuracy: fix.horizontalAccuracy, time: fix.time)
    }

    /// The fix on a flat map in meters, east and north of the first fix seen. Close enough over a run.
    private mutating func flat(_ fix: Fix) -> (x: Double, y: Double) {
        let origin = self.origin ?? (fix.latitude, fix.longitude, Self.metersPerDegree * cos(fix.latitude * .pi / 180))
        self.origin = origin
        return (
            (fix.longitude - origin.longitude) * origin.metersPerDegreeLongitude,
            (fix.latitude - origin.latitude) * Self.metersPerDegree
        )
    }

    private static let metersPerDegree = 6_371_008.8 * .pi / 180

    /// A fix's accuracy as a variance, never so small that one fix is trusted completely.
    fileprivate static func variance(_ accuracy: Double) -> Double {
        let meters = accuracy > 0 ? max(accuracy, 1) : 10
        return meters * meters
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
