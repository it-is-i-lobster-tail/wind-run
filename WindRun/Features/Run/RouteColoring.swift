//
//  RouteColoring.swift
//  Wind Run
//

import CoreLocation
import Foundation

/// What the run map colors the route by. Swiping on the map moves through them in this order.
enum RouteColoring: Int, CaseIterable, Identifiable {
    case pace
    case cadence
    case grade

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .pace: "Pace"
        case .cadence: "Cadence"
        case .grade: "Grade"
        }
    }

    /// The words at each end of the key: the lowest level first.
    var ends: (low: String, high: String) {
        switch self {
        case .pace, .cadence: ("Slower", "Faster")
        case .grade: ("Decline", "Incline")
        }
    }

    /// How many shades the route is drawn in. Odd, so a grade scale has a middle shade for flat ground.
    static let levels = 9
}

/// A stretch of the route drawn in one shade, from 0 (slowest, or steepest down) to `RouteColoring.levels - 1`.
struct ColoredRouteSegment: Identifiable {
    let id: Int
    let level: Int
    let coordinates: [CLLocationCoordinate2D]
}

/// The route cut into stretches of one shade for one way of coloring it.
struct ColoredRoute: Identifiable {
    let coloring: RouteColoring
    let segments: [ColoredRouteSegment]
    /// Every point of the route in order, for the dark edge drawn under the shades. Joined once here
    /// rather than each time the map redraws.
    let edge: [CLLocationCoordinate2D]

    init(coloring: RouteColoring, segments: [ColoredRouteSegment]) {
        self.coloring = coloring
        self.segments = segments
        edge = segments.flatMap(\.coordinates)
    }

    var id: RouteColoring { coloring }
}

extension Run {
    /// The route colored each way the run has data for, in swiping order: pace whenever the route has fixes
    /// taken while running, cadence when steps were counted, grade when the run has heights.
    var coloredRoutes: [ColoredRoute] {
        let fixes = activeRoute
        return Self.coloredRoutes(fixes: fixes, track: altitudeTrack(for: fixes), cadence: cadenceTimeline)
    }

    /// The same, from the fixes, heights and cadence already worked out, as the run summary has them.
    static func coloredRoutes(fixes: [ActiveFix], track: AltitudeTrack?, cadence: [CadencePoint]) -> [ColoredRoute] {
        guard fixes.count > 1 else { return [] }
        return RouteColoring.allCases.compactMap { coloring in
            let values: [Double?]
            switch coloring {
            case .pace: values = Self.speeds(along: fixes)
            case .cadence: values = Self.cadences(at: fixes, timeline: cadence)
            case .grade: values = Self.grades(along: fixes, heights: Self.smoothedHeights(track, fixes: fixes))
            }
            guard let shades = Self.levels(for: values, coloring: coloring) else { return nil }
            // Fewer, longer lines: a long run would otherwise be thousands of map overlays.
            let segments = Self.segments(fixes: fixes, levels: Self.merged(shades, fixes: fixes)).map { segment in
                ColoredRouteSegment(id: segment.id, level: segment.level, coordinates: Self.simplified(segment.coordinates))
            }
            return ColoredRoute(coloring: coloring, segments: segments)
        }
    }

    /// The shades with any stretch shorter than `shortest` meters drawn in the shade before it (or after it,
    /// at the start), so a noisy reading doesn't flick the line to another shade for a few meters.
    static func merged(_ levels: [Int], fixes: [ActiveFix], shortest: Double = 20) -> [Int] {
        guard levels.count == fixes.count, levels.count > 2 else { return levels }
        var merged = levels
        var start = 0
        while start < merged.count {
            var end = start
            while end + 1 < merged.count, merged[end + 1] == merged[start] {
                end += 1
            }
            let isWholeRoute = start == 0 && end == merged.count - 1
            if !isWholeRoute, fixes[end].meters - fixes[start].meters < shortest {
                let shade = start > 0 ? merged[start - 1] : merged[end + 1]
                for index in start...end {
                    merged[index] = shade
                }
            }
            start = end + 1
        }
        return merged
    }

    /// The points of a line with those that sit within `tolerance` meters of the line through their
    /// neighbors left out (Douglas–Peucker). The ends are always kept, so stretches still meet.
    static func simplified(_ coordinates: [CLLocationCoordinate2D], tolerance: Double = 2) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 2 else { return coordinates }
        // Meters on a flat plane around the first point, which is close enough over a run's few kilometers.
        let origin = coordinates[0]
        let metersPerDegree = 111_320.0
        let east = cos(origin.latitude * .pi / 180) * metersPerDegree
        let points = coordinates.map { (x: ($0.longitude - origin.longitude) * east, y: ($0.latitude - origin.latitude) * metersPerDegree) }

        func distance(_ point: Int, from first: Int, to last: Int) -> Double {
            let a = points[first]
            let b = points[last]
            let p = points[point]
            let dx = b.x - a.x
            let dy = b.y - a.y
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 0 else { return ((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)).squareRoot() }
            return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / length
        }

        var keep = Array(repeating: false, count: coordinates.count)
        keep[0] = true
        keep[coordinates.count - 1] = true
        // A stack rather than recursion, so a marathon's thousands of points can't run it too deep.
        var stack = [(0, coordinates.count - 1)]
        while let (first, last) = stack.popLast() {
            guard last - first > 1 else { continue }
            var farthest = first
            var farthestDistance = 0.0
            for index in (first + 1)..<last {
                let d = distance(index, from: first, to: last)
                if d > farthestDistance {
                    farthest = index
                    farthestDistance = d
                }
            }
            if farthestDistance > tolerance {
                keep[farthest] = true
                stack.append((first, farthest))
                stack.append((farthest, last))
            }
        }
        return coordinates.indices.filter { keep[$0] }.map { coordinates[$0] }
    }

    /// Meters a second at each fix, over the 30 seconds around it on the same stretch between pauses. Nil where
    /// the stretch is too short to say.
    static func speeds(along fixes: [ActiveFix], window: TimeInterval = 30) -> [Double?] {
        var back = 0
        var ahead = 0
        return fixes.indices.map { index in
            let fix = fixes[index]
            while fixes[back].stretch != fix.stretch || fix.time - fixes[back].time > window / 2 {
                back += 1
            }
            ahead = max(ahead, index)
            while ahead + 1 < fixes.count, fixes[ahead + 1].stretch == fix.stretch, fixes[ahead + 1].time - fix.time <= window / 2 {
                ahead += 1
            }
            let seconds = fixes[ahead].time - fixes[back].time
            guard seconds >= window / 3 else { return nil }
            return (fixes[ahead].meters - fixes[back].meters) / seconds
        }
    }

    /// Steps a minute at each fix, between the cadence points either side of it. Nil where no point is within a
    /// minute, as when steps weren't counted.
    static func cadences(at fixes: [ActiveFix], timeline: [CadencePoint]) -> [Double?] {
        guard !timeline.isEmpty else { return Array(repeating: nil, count: fixes.count) }
        let reach: TimeInterval = 60
        var after = 0
        return fixes.map { fix in
            while after < timeline.count, timeline[after].activeTime < fix.time {
                after += 1
            }
            let before = after - 1
            let a = timeline.indices.contains(before) ? timeline[before] : nil
            let b = timeline.indices.contains(after) ? timeline[after] : nil
            if let a, let b, b.activeTime - a.activeTime <= 2 * reach {
                let fraction = (fix.time - a.activeTime) / max(b.activeTime - a.activeTime, 0.001)
                return a.stepsPerMinute + (b.stepsPerMinute - a.stepsPerMinute) * fraction
            }
            // Across a longer gap, only a point within a minute speaks for the fix.
            if let a, fix.time - a.activeTime <= reach { return a.stepsPerMinute }
            if let b, b.activeTime - fix.time <= reach { return b.stepsPerMinute }
            return nil
        }
    }

    /// Rise over run at each fix, from the smoothed heights `reach` meters either side of it on the same stretch.
    /// Nil where the stretch is too short to say or has no heights.
    static func grades(along fixes: [ActiveFix], heights: [Double?], reach: Double = 25) -> [Double?] {
        var back = 0
        var ahead = 0
        return fixes.indices.map { index in
            let fix = fixes[index]
            while back < index, fixes[back].stretch != fix.stretch || fix.meters - fixes[back + 1].meters >= reach {
                back += 1
            }
            ahead = max(ahead, index)
            while ahead + 1 < fixes.count, fixes[ahead + 1].stretch == fix.stretch, fixes[ahead].meters - fix.meters < reach {
                ahead += 1
            }
            let meters = fixes[ahead].meters - fixes[back].meters
            guard meters >= reach, let high = heights[ahead], let low = heights[back] else { return nil }
            return (high - low) / meters
        }
    }

    /// Each fix's shade, or nil when no fix has a value. Gaps take the value before them, or after at the start.
    /// Pace and cadence spread across this run's own range, leaving out the odd 5% at each end, so an easy run
    /// shows its own ups and downs; a tiny range stays in the middle shades. Grade uses a fixed scale, flat in
    /// the middle and 6% or steeper at the ends, so a flat run reads flat.
    static func levels(for values: [Double?], coloring: RouteColoring) -> [Int]? {
        let known = values.compactMap { $0 }.sorted()
        guard !known.isEmpty, let first = values.lazy.compactMap({ $0 }).first else { return nil }
        var filled: [Double] = []
        var last = first
        for value in values {
            if let value { last = value }
            filled.append(last)
        }

        let top = Double(RouteColoring.levels - 1)
        let low: Double
        let high: Double
        switch coloring {
        case .grade:
            low = -0.06
            high = 0.06
        case .pace, .cadence:
            let p5 = known[Int(Double(known.count - 1) * 0.05)]
            let p95 = known[Int(Double(known.count - 1) * 0.95)]
            // A spread smaller than this is only wobble: half a meter a second, or 10 steps a minute.
            let smallest = coloring == .pace ? 0.5 : 10
            let middle = (p5 + p95) / 2
            let spread = max(p95 - p5, smallest)
            low = middle - spread / 2
            high = middle + spread / 2
        }
        return filled.map { value in
            Int((min(max((value - low) / (high - low), 0), 1) * top).rounded())
        }
    }

    /// The fixes cut where the shade changes. Each stretch starts where the last one ended, so the line has no gaps.
    static func segments(fixes: [ActiveFix], levels: [Int]) -> [ColoredRouteSegment] {
        guard fixes.count > 1, levels.count == fixes.count else { return [] }
        var segments: [ColoredRouteSegment] = []
        var current = [fixes[0].sample.coordinate]
        var currentLevel = levels[0]
        for index in fixes.indices.dropFirst() {
            current.append(fixes[index].sample.coordinate)
            if levels[index] != currentLevel {
                segments.append(ColoredRouteSegment(id: segments.count, level: currentLevel, coordinates: current))
                current = [fixes[index].sample.coordinate]
                currentLevel = levels[index]
            }
        }
        if current.count > 1 {
            segments.append(ColoredRouteSegment(id: segments.count, level: currentLevel, coordinates: current))
        }
        return segments
    }
}
