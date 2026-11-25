import MapKit
import SwiftUI

enum RouteActivity: String, Codable, CaseIterable {
    case run = "Run"
    case ride = "Ride"

    var symbol: String { self == .run ? "figure.run" : "bicycle" }
}

nonisolated struct RoutePoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var location: CLLocation { .init(latitude: latitude, longitude: longitude) }
    static let poolStart = Self(latitude: 38.88900, longitude: -77.04972)
}

struct WorkoutWaypoint: Identifiable, Codable, Hashable {
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

/// A crossing can lie between GPS samples, or be confirmed one or two samples later.
struct WaypointFix {
    let point: RoutePoint
    let accuracy: Double
    let date: Date?
    let meters: Double

    func connects(to next: Self, activity: RouteActivity) -> Bool {
        guard let date, let end = next.date else { return true }
        let seconds = end.timeIntervalSince(date)
        let allowed = seconds * (activity == .ride ? 35 : 15) + accuracy + next.accuracy
        return seconds > 0 && seconds <= 30 && point.location.distance(from: next.point.location) <= allowed
    }

    func interpolated(to end: Self, fraction: Double) -> Self {
        let motion = WaypointDirection(from: point, to: end.point)
        let position = motion.offset(point, forward: motion.length * fraction, sideways: 0)
        let time = date.flatMap { start in end.date.map { start.addingTimeInterval($0.timeIntervalSince(start) * fraction) } }
        return Self(point: position, accuracy: max(accuracy, end.accuracy), date: time,
                    meters: meters + (end.meters - meters) * fraction)
    }
}

extension WaypointFix {
    init(_ location: CLLocation, meters: Double) {
        self.init(point: .init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
                  accuracy: location.horizontalAccuracy, date: location.timestamp, meters: meters)
    }
}

/// The preview player and Core Location feed the same ordered arrival check.
struct WaypointProgress {
    let workout: WaypointWorkout
    private(set) var start: RoutePoint?
    private(set) var position: RoutePoint?
    private(set) var leg = 0
    private var lastFix: WaypointFix?
    private var separatedFix: WaypointFix?
    private var pending: [WaypointFix] = []
    private var heading: WaypointDirection?
    private var track: [WaypointFix] = []
    private var evaluatedTrackIndex = 0
    private var gateProjection: (leg: Int, distance: Double, direction: WaypointDirection)?
    private var turnaround: Turnaround?
    private var initialFixes: [WaypointFix] = []
    private var estimatedStart: RoutePoint?
    private var startAccuracy: Double = 0
    private var estimatesInitialFix = true

    private struct Turnaround {
        let approach: WaypointDirection
        let tip: WaypointFix
        var returning: [WaypointFix] = []
    }

    /// Half-width of a finish line across the actual direction of travel.
    static let passingWidth: Double = 20

    init(workout: WaypointWorkout, start: RoutePoint? = nil, completedLegs: Int = 0) {
        self.workout = workout
        self.start = start
        estimatesInitialFix = start == nil
        self.leg = min(completedLegs, workout.legCount)
    }

    var finished: Bool { leg == workout.legCount }
    var target: RoutePoint? {
        guard start != nil, !finished else { return nil }
        return leg < workout.points.count ? workout.points[leg].point : (estimatedStart ?? start)
    }

    var destination: String {
        leg < workout.points.count ? workout.points[leg].name : "Starting point"
    }

    var effort: IntervalStepKind {
        leg < workout.points.count ? workout.points[leg].effort : workout.returnEffort
    }

    mutating func skipWaypoint() {
        guard !finished else { return }
        leg += 1
        breakTrack()
    }

    mutating func breakTrack() {
        separatedFix = nil
        pending.removeAll()
        heading = nil
        turnaround = nil
        track.removeAll()
        if estimatesInitialFix, start != nil {
            estimatesInitialFix = false
            initialFixes.removeAll()
        }
        evaluatedTrackIndex = 0
        gateProjection = nil
    }

    @discardableResult
    mutating func receive(_ point: RoutePoint, accuracy: Double = 0, at date: Date? = nil,
                          meters: Double = 0) -> [WaypointFix] {
        guard !finished else { return [] }
        let fix = WaypointFix(point: point, accuracy: accuracy, date: date, meters: meters)
        let previous = lastFix
        if let date, let prior = previous?.date, date <= prior { return [] }
        // After a track break, the previous fix still guards timestamp order.
        if let previous, !pending.isEmpty, !previous.connects(to: fix, activity: workout.activity) {
            let seconds = date.flatMap { end in previous.date.map { end.timeIntervalSince($0) } }
            if let seconds, seconds <= 30,
               separatedFix?.connects(to: fix, activity: workout.activity) != true {
                separatedFix = fix
                return []
            }
            breakTrack()
        }
        separatedFix = nil
        lastFix = fix
        position = point
        if start == nil {
            start = point
            startAccuracy = accuracy
        }
        if estimatesInitialFix, date != nil {
            recordInitialMotion(fix)
        }
        if date != nil {
            track.append(fix)
            if track.count > 48 {
                track.removeFirst()
                evaluatedTrackIndex = max(0, evaluatedTrackIndex - 1)
            }
        }
        guard let anchor = pending.first, let previous else {
            pending = [fix]
            return []
        }
        let priorLeg = leg
        let stride = WaypointDirection(from: previous.point, to: point)
        let baseline = WaypointDirection(from: anchor.point, to: point)
        if stride.length == 0 {
            pending[pending.count - 1] = fix
            guard date != nil, track.count > 3 else { return [] }
            let events = timedCrossings()
            if !events.isEmpty { turnaround = nil }
            return events
        }
        pending.append(fix)

        var events: [WaypointFix] = []
        // Trust a short stride only when it continues established motion. Otherwise
        // keep the actual path until displacement is larger than GPS uncertainty.
        let established = pending.count == 2 ? heading : nil
        let continues = established?.aligned(with: stride) == true
        // A direct crossing is strong evidence even on a turn. For a lateral
        // crossing on a new bearing, wait for another moving fix to confirm it.
        let turning = established != nil && !continues
        let direct = target.flatMap {
            stride.crossingFraction($0, from: previous.point, to: point, halfWidth: 1)
        } != nil
        let resolved = baseline.length >= max(12, anchor.accuracy + accuracy) && (!turning || direct)
        if date != nil, track.count > 3 {
            events = timedCrossings()
            if baseline.length >= 12 {
                heading = baseline
                pending = [fix]
            } else if pending.count > 32 {
                pending.removeFirst()
            }
        } else if continues || resolved {
            let reliable = continues ? (established ?? baseline) : baseline
            for (a, b) in zip(pending, pending.dropFirst()) {
                let local = WaypointDirection(from: a.point, to: b.point)
                if local.progresses(along: reliable) {
                    events += crossings(from: a, to: b, along: reliable)
                }
            }
            heading = reliable
            pending = [fix]
        } else if pending.count > 32 {
            pending.removeFirst()
        }

        if workout.returnsToStart, leg == workout.points.count, priorLeg == leg,
           let start = estimatedStart ?? start, let heading,
           let arrival = inboundHomeArrival(from: previous, to: fix, start: start, heading: heading) {
            leg += 1
            events.append(arrival)
        }
        if leg != priorLeg {
            turnaround = nil
            if track.count <= 3 {
                evaluatedTrackIndex = max(0, track.count - 1)
                gateProjection = nil
            }
        }
        else if workout.returnsToStart, leg == workout.points.count - 1,
                let reversal = confirmedTurnaround(from: previous, to: fix) {
            leg += 1
            events.append(reversal.tip)
            var from = reversal.tip
            for back in reversal.returning {
                let direction = WaypointDirection(from: from.point, to: back.point)
                events += crossings(from: from, to: back, along: direction)
                from = back
            }
            pending = [fix]
            evaluatedTrackIndex = max(0, track.count - 1)
            gateProjection = nil
            heading = WaypointDirection(from: reversal.tip.point, to: fix.point)
        }
        return events
    }

    private mutating func timedCrossings() -> [WaypointFix] {
        guard let current = track.last else { return [] }
        var events: [WaypointFix] = []
        while evaluatedTrackIndex + 1 < track.count, let target {
            let a = track[evaluatedTrackIndex]
            let b = track[evaluatedTrackIndex + 1]
            let stride = WaypointDirection(from: a.point, to: b.point)
            guard stride.length > 0 else {
                evaluatedTrackIndex += 1
                continue
            }
            let targetDistance = WaypointDirection(from: a.point, to: target).length
            // A distant endpoint can still connect across a gate after a sparse update.
            guard targetDistance <= 105 + stride.length else {
                evaluatedTrackIndex += 1
                gateProjection = nil
                continue
            }
            let futureTravel = b.point.location.distance(from: current.point.location)
            let futureCount = track.count - evaluatedTrackIndex - 2
            let longStride = stride.length >= max(28, 2 * (a.accuracy + b.accuracy))
            guard futureTravel >= 18 || futureCount >= 6 || (current.date?.timeIntervalSince(b.date ?? .distantPast) ?? 0) >= 8 || longStride else { break }

            let stopped = b.point == current.point && futureCount >= 2
            if let fit = (longStride || stopped) ? (stride, b.point) : localMotion(around: evaluatedTrackIndex) {
                let (direction, fittedPoint) = fit
                let correction = WaypointDirection(from: b.point, to: fittedPoint)
                var lastFraction = 0.0
                while let target = self.target {
                    let toA = WaypointDirection(from: target, to: a.point)
                    let toB = WaypointDirection(from: target, to: b.point)
                    let sameGate = gateProjection.flatMap { $0.leg == leg ? $0 : nil }
                    let before = sameGate.flatMap { $0.direction.aligned(with: direction) ? $0.distance : nil } ?? direction.projection(toA)
                    let after = direction.projection(toB) + direction.projection(correction)
                    gateProjection = (leg, after, direction)
                    guard before < 0, after >= 0 else { break }
                    let fraction = -before / (after - before)
                    guard fraction > lastFraction else { break }
                    let lateral = direction.x * (toA.y + (toB.y - toA.y) * fraction)
                                - direction.y * (toA.x + (toB.x - toA.x) * fraction)
                    guard abs(lateral) <= Self.passingWidth * direction.length else { break }
                    events.append(a.interpolated(to: b, fraction: fraction))
                    leg += 1
                    lastFraction = fraction
                }
            } else {
                gateProjection = nil
            }
            evaluatedTrackIndex += 1
            if finished { break }
        }
        return events
    }

    private func localMotion(around index: Int) -> (WaypointDirection, RoutePoint)? {
        let a = track[index]
        let b = track[index + 1]
        guard let midpoint = a.interpolated(to: b, fraction: 0.5).date else { return nil }
        var first = index
        var last = index + 1
        while first > 0,
              a.point.location.distance(from: track[first].point.location) < 28,
              midpoint.timeIntervalSince(track[first].date ?? midpoint) < 14 {
            first -= 1
        }
        while last + 1 < track.count,
              b.point.location.distance(from: track[last].point.location) < 37,
              (track[last].date ?? midpoint).timeIntervalSince(midpoint) < 8 {
            last += 1
        }
        let origin = a.point
        let endToAnchor = WaypointDirection(from: a.point, to: b.point)
        let endToEnd = WaypointDirection(from: track[first].point, to: track[last].point)
        guard endToEnd.length >= max(9, a.accuracy * 0.8) else { return nil }
        var weight = 0.0
        var time = 0.0
        var timeSquared = 0.0
        var x = 0.0
        var y = 0.0
        var timeX = 0.0
        var timeY = 0.0

        for sample in track[first...last] {
            guard let date = sample.date else { continue }
            let t = date.timeIntervalSince(midpoint)
            let offset = WaypointDirection(from: origin, to: sample.point)
            let w = 1 / max(2, sample.accuracy)
            weight += w
            time += w * t
            timeSquared += w * t * t
            x += w * offset.x
            y += w * offset.y
            timeX += w * t * offset.x
            timeY += w * t * offset.y
        }
        let span = timeSquared - time * time / weight
        guard weight > 0, span > 0, let date = b.date else { return nil }
        let velocity = WaypointDirection(x: (timeX - time * x / weight) / span,
                                         y: (timeY - time * y / weight) / span)
        let relativeTime = date.timeIntervalSince(midpoint) - time / weight
        let correction = WaypointDirection(x: (x / weight + velocity.x * relativeTime) - endToAnchor.x,
                                           y: (y / weight + velocity.y * relativeTime) - endToAnchor.y)
        var direction = velocity
        var earlier = first
        while earlier > 0,
              a.point.location.distance(from: track[earlier].point.location) < 58,
              midpoint.timeIntervalSince(track[earlier].date ?? midpoint) < 24 {
            earlier -= 1
        }
        if earlier < first, last > first + 3 {
            let from = track[earlier].interpolated(to: track[earlier + 1], fraction: 0.5)
            let to = track[last - 1].interpolated(to: track[last], fraction: 0.5)
            let broad = WaypointDirection(from: from.point, to: to.point)
            let agreement = velocity.projection(broad) / max(1, broad.length)
            if agreement >= 0.97 {
                let ratio = 0.4 * velocity.length / broad.length
                direction = WaypointDirection(x: 0.6 * velocity.x + ratio * broad.x,
                                              y: 0.6 * velocity.y + ratio * broad.y)
            }
        }
        return (direction, correction.offset(b.point, forward: correction.length * 0.85, sideways: 0))
    }

    /// Estimate the start from a short initial run of samples while retaining the
    /// first fix as the recorded start. The intercept remains at the first fix's time.
    private mutating func recordInitialMotion(_ fix: WaypointFix) {
        initialFixes.append(fix)
        guard let first = initialFixes.first, let date = first.date,
              let elapsed = fix.date?.timeIntervalSince(date), elapsed >= 6 || initialFixes.count >= 32 else { return }
        estimatesInitialFix = false
        defer { initialFixes.removeAll() }
        guard initialFixes.count >= 4 else { return }
        let displacement = WaypointDirection(from: first.point, to: fix.point)
        guard displacement.length >= 8 else { return }
        var w = 0.0, t = 0.0, tt = 0.0, x = 0.0, y = 0.0, tx = 0.0, ty = 0.0
        for sample in initialFixes {
            guard let time = sample.date?.timeIntervalSince(date) else { continue }
            let weight = 1 / max(2, sample.accuracy)
            let offset = WaypointDirection(from: first.point, to: sample.point)
            w += weight
            t += weight * time
            tt += weight * time * time
            x += weight * offset.x
            y += weight * offset.y
            tx += weight * time * offset.x
            ty += weight * time * offset.y
        }
        let determinant = w * tt - t * t
        guard determinant > 0 else { return }
        let intercept = WaypointDirection(x: (tt * x - t * tx) / determinant,
                                           y: (tt * y - t * ty) / determinant)
        estimatedStart = intercept.offset(first.point, forward: min(first.accuracy, intercept.length), sideways: 0)
    }

    private func inboundHomeArrival(from a: WaypointFix, to b: WaypointFix,
                                    start: RoutePoint, heading: WaypointDirection) -> WaypointFix? {
        let inbound = WaypointDirection(from: a.point, to: start)
        let gap = WaypointDirection(from: b.point, to: start).length
        guard let date = b.date else {
            return heading.aligned(with: inbound) && gap < inbound.length && gap <= min(8, b.accuracy) ? b : nil
        }
        let radius = min(11, max(6, 0.7 * hypot(startAccuracy, b.accuracy)))
        let captureRadius = max(radius, min(18, hypot(startAccuracy, b.accuracy) + 2))
        guard gap <= captureRadius, gap < inbound.length,
              let anchor = track.reversed().first(where: { sample in
                  guard let time = sample.date, date.timeIntervalSince(time) <= 18 else { return false }
                  return WaypointDirection(from: sample.point, to: b.point).length >= 16
              }) else { return nil }
        let motion = WaypointDirection(from: anchor.point, to: b.point)
        let towardStart = WaypointDirection(from: anchor.point, to: start)
        let remaining = motion.projection(WaypointDirection(from: b.point, to: start))
        guard motion.aligned(with: towardStart), gap <= radius || remaining <= 6 else { return nil }
        return b
    }

    private mutating func crossings(from a: WaypointFix, to b: WaypointFix,
                                    along direction: WaypointDirection) -> [WaypointFix] {
        var events: [WaypointFix] = []
        var lastFraction = 0.0
        while let target, let fraction = direction.crossingFraction(target, from: a.point, to: b.point,
                                                                     halfWidth: Self.passingWidth),
              fraction > lastFraction {
            events.append(a.interpolated(to: b, fraction: fraction))
            leg += 1
            lastFraction = fraction
        }
        return events
    }

    private mutating func confirmedTurnaround(from a: WaypointFix, to b: WaypointFix) -> Turnaround? {
        guard let target, let start, max(a.accuracy, b.accuracy) <= 10 else {
            turnaround = nil
            return nil
        }
        let gap = b.point.location.distance(from: target.location)
        let priorGap = a.point.location.distance(from: target.location)
        let movement = WaypointDirection(from: a.point, to: b.point)
        guard movement.length > 0 else { return nil }
        // A fast turnaround can carry a short stride just beyond the pin before a
        // reliable outbound heading exists. Remember the tip of that approach.
        if gap <= 15, let previous = turnaround, previous.returning.isEmpty,
           movement.aligned(with: previous.approach) {
            turnaround = Turnaround(approach: previous.approach, tip: b)
            return nil
        }
        if turnaround == nil, gap <= 15, gap < priorGap {
            turnaround = Turnaround(approach: movement, tip: b)
            return nil
        }
        guard var attempt = turnaround else { return nil }
        let home = WaypointDirection(from: attempt.tip.point, to: start)
        guard movement.aligned(with: home),
              movement.x * attempt.approach.x + movement.y * attempt.approach.y < 0 else {
            turnaround = nil
            return nil
        }
        attempt.returning.append(b)
        let separation = b.point.location.distance(from: attempt.tip.point.location)
        if attempt.returning.count >= 2, separation >= max(3, b.accuracy + attempt.tip.accuracy) {
            turnaround = nil
            return attempt
        }
        turnaround = attempt.returning.count < 32 ? attempt : nil
        return nil
    }

}

/// Local map distances in meters, with x east and y south. The runner's track defines the
/// normal to the finish line, so a bend or an approach from a side street works too.
struct WaypointDirection {
    let x: Double
    let y: Double
    let length: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
        length = hypot(x, y)
    }

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

    func projection(_ delta: Self) -> Double {
        guard length > 0 else { return 0 }
        return (x * delta.x + y * delta.y) / length
    }

    func progresses(along other: Self) -> Bool {
        length > 0 && other.length > 0 && x * other.x + y * other.y >= 0.35 * length * other.length
    }

    func aligned(with other: Self) -> Bool {
        length > 0 && other.length > 0 && x * other.x + y * other.y >= 0.82 * length * other.length
    }

    func crossingFraction(_ waypoint: RoutePoint, from start: RoutePoint, to end: RoutePoint, halfWidth: Double) -> Double? {
        guard length > 0 else { return nil }
        let target = Self(from: start, to: waypoint)
        let step = Self(from: start, to: end)
        let nx = x / length, ny = y / length
        let toLine = target.x * nx + target.y * ny
        let forward = step.x * nx + step.y * ny
        guard forward > 0, toLine > 0, toLine <= forward + 0.001 else { return nil }
        let fraction = min(1, max(0, toLine / forward))
        let miss = (step.x * fraction - target.x) * ny - (step.y * fraction - target.y) * nx
        return abs(miss) <= halfWidth ? fraction : nil
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
