import MapKit
import SwiftUI

enum RouteActivity: String, Codable, CaseIterable {
    case run = "Run"
    case ride = "Ride"

    var symbol: String { self == .run ? "figure.run" : "bicycle" }
}

struct RoutePoint: Codable, Equatable {
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var location: CLLocation { .init(latitude: latitude, longitude: longitude) }
    static let poolStart = Self(latitude: 38.88900, longitude: -77.04972)
}

struct WorkoutWaypoint: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var point: RoutePoint
    // The effort on the way TO this waypoint.
    var effort: IntervalStepKind
}

struct WaypointWorkout: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var activity = RouteActivity.run
    var points: [WorkoutWaypoint]
    var returnsToStart = true
    var returnEffort = IntervalStepKind.cooldown

    static let pool = WaypointWorkout(name: "Reflecting Pool intervals", points: [
        .init(name: "South walk", point: .init(latitude: 38.88890, longitude: -77.04813), effort: .warmup),
        .init(name: "East terrace", point: .init(latitude: 38.88890, longitude: -77.04235), effort: .work),
        .init(name: "North walk", point: .init(latitude: 38.88991, longitude: -77.04235), effort: .recovery),
        .init(name: "Lincoln steps", point: .init(latitude: 38.88991, longitude: -77.04853), effort: .work)
    ])

    static let outAndBack = WaypointWorkout(name: "Pool out and back", points: [
        .init(name: "East terrace", point: pool.points[1].point, effort: .work)
    ], returnEffort: .recovery)

    // The preview needs a stand-in start. A GPS session always sets its own on the first good fix.
    var previewStart: RoutePoint {
        guard let first = points.first?.point,
              first.location.distance(from: RoutePoint.poolStart.location) > 1_000 else { return .poolStart }
        return RoutePoint(latitude: first.latitude, longitude: first.longitude > 0 ? first.longitude - 0.002 : first.longitude + 0.002)
    }

    var legCount: Int { points.isEmpty ? 0 : points.count + (returnsToStart ? 1 : 0) }
}

/// The preview player and Core Location feed the same ordered arrival check.
struct WaypointProgress {
    let workout: WaypointWorkout
    private(set) var start: RoutePoint?
    private(set) var position: RoutePoint?
    private(set) var leg = 0
    private var motionAnchor: RoutePoint?
    private var anchorAccuracy: Double = 0
    private var lastFix: Date?
    private(set) var direction: WaypointDirection?

    /// Half-width of a finish line across the actual direction of travel.
    static let passingWidth: Double = 80

    init(workout: WaypointWorkout, start: RoutePoint? = nil, completedLegs: Int = 0) {
        self.workout = workout
        self.start = start
        self.leg = min(completedLegs, workout.legCount)
    }

    var finished: Bool { start != nil && leg == workout.legCount }
    var target: RoutePoint? {
        guard start != nil, !finished else { return nil }
        return leg < workout.points.count ? workout.points[leg].point : start
    }

    var destination: String {
        leg < workout.points.count ? workout.points[leg].name : "Starting point"
    }

    var effort: IntervalStepKind {
        leg < workout.points.count ? workout.points[leg].effort : workout.returnEffort
    }

    mutating func breakTrack() { motionAnchor = nil; direction = nil }

    mutating func receive(_ point: RoutePoint, accuracy: Double = 0, at date: Date? = nil) {
        guard !finished else { return }
        if let date, let lastFix, date <= lastFix { return }

        // Never infer a crossing over a GPS outage or an implausible jump.
        if let date, let lastFix, let position {
            let seconds = date.timeIntervalSince(lastFix)
            let maxSpeed = workout.activity == .ride ? 35.0 : 15.0
            if seconds > 30 || position.location.distance(from: point.location) > seconds * maxSpeed + 60 {
                motionAnchor = nil
                direction = nil
            }
        }
        lastFix = date
        let previous = position
        position = point
        if start == nil { start = point }

        guard let anchor = motionAnchor, let target else {
            motionAnchor = point
            anchorAccuracy = accuracy
            return
        }
        let motion = WaypointDirection(from: anchor, to: point)
        // Use a baseline longer than the reported uncertainty before trusting a heading.
        let passed: Bool
        if motion.length >= max(12, anchorAccuracy + accuracy) {
            direction = motion
            motionAnchor = point
            anchorAccuracy = accuracy
            passed = motion.crosses(target, from: anchor, to: point, halfWidth: Self.passingWidth)
        } else if let direction, let previous {
            // Approaching the line at walking speed, a short final stride can still cross it.
            passed = direction.crosses(target, from: previous, to: point, halfWidth: Self.passingWidth)
        } else {
            return
        }
        if passed {
            leg += 1
            direction = nil
            motionAnchor = point
            anchorAccuracy = accuracy
        }
    }
}

/// Local map distances in meters, with x east and y south. The runner's track defines the
/// normal to the finish line, so a bend or an approach from a side street works too.
struct WaypointDirection {
    let x: Double
    let y: Double
    let length: Double

    init(from start: RoutePoint, to end: RoutePoint) {
        let a = MKMapPoint(start.coordinate)
        let b = MKMapPoint(end.coordinate)
        let world = MKMapRect.world.width
        var dx = b.x - a.x
        if abs(dx) > world / 2 { dx += dx < 0 ? world : -world }
        let scale = MKMetersPerMapPointAtLatitude(start.latitude)
        x = dx * scale
        y = (b.y - a.y) * scale
        length = hypot(x, y)
    }

    func crosses(_ waypoint: RoutePoint, from start: RoutePoint, to end: RoutePoint, halfWidth: Double) -> Bool {
        guard length > 0 else { return false }
        let target = Self(from: start, to: waypoint)
        let step = Self(from: start, to: end)
        let nx = x / length, ny = y / length
        let toLine = target.x * nx + target.y * ny
        let forward = step.x * nx + step.y * ny
        guard forward > 0, toLine >= -0.001, toLine <= forward + 0.001 else { return false }
        let fraction = min(1, max(0, toLine / forward))
        let miss = (step.x * fraction - target.x) * ny - (step.y * fraction - target.y) * nx
        return abs(miss) <= halfWidth
    }

    func offset(_ point: RoutePoint, forward: Double = 0, sideways: Double) -> RoutePoint {
        guard length > 0 else { return point }
        let origin = MKMapPoint(point.coordinate)
        let scale = length * MKMetersPerMapPointAtLatitude(point.latitude)
        let result = MKMapPoint(x: origin.x + (x * forward - y * sideways) / scale,
                                y: origin.y + (y * forward + x * sideways) / scale).coordinate
        return .init(latitude: result.latitude, longitude: result.longitude)
    }
}

extension IntervalStepKind {
    var routeTint: Color {
        switch self {
        case .warmup: .orange
        case .work: .accentColor
        case .recovery: .indigo
        case .cooldown: .blue
        }
    }
}
