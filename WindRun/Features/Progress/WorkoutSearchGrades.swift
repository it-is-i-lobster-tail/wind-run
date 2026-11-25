import Foundation

enum WorkoutSearchTerrain: String, Codable {
    case hills, uphill, downhill

    var label: String {
        switch self {
        case .hills: "Hills · 6% or steeper for 100 m"
        case .uphill: "Uphill · 6% or steeper for 100 m"
        case .downhill: "Downhill · 6% or steeper for 100 m"
        }
    }
}

/// Keep route decoding out of ordinary searches. Records sharing this projection reuse its result.
final class WorkoutSearchGrades {
    private let run: Run
    private lazy var directions = Self.directions(in: run)

    init(_ run: Run) { self.run = run }

    func matches(_ terrain: WorkoutSearchTerrain) -> Bool {
        terrain == .hills ? !directions.isEmpty : directions.contains(terrain)
    }

    private static func directions(in run: Run) -> Set<WorkoutSearchTerrain> {
        let fixes = run.activeRoute
        guard let track = run.altitudeTrack(for: fixes) else { return [] }
        var result = Set<WorkoutSearchTerrain>()
        var start = 0
        // Don't treat a pause, a missing elevation reading, or a gap in the route as a slope.
        for end in 1...track.points.count {
            if end < track.points.count {
                let a = track.points[end - 1], b = track.points[end]
                if a.stretch == b.stretch, b.index == a.index + 1,
                   b.time - a.time <= 30, b.meters - a.meters <= 50 { continue }
            }
            let points = track.points[start..<end]
            start = end
            guard let first = points.first, let last = points.last, last.meters - first.meters >= 100 else { continue }
            let segment = Array(fixes[first.index...last.index])
            let heights = Run.smoothedHeights(AltitudeTrack(source: track.source, points: Array(points)), fixes: segment)
            let grades = Run.grades(along: segment, heights: heights)
            var previous: WorkoutSearchTerrain?
            var since = 0.0
            for (fix, grade) in zip(segment, grades) {
                // Six percent is the steep end of the route map's grade scale.
                let direction: WorkoutSearchTerrain?
                if let grade, grade >= 0.06 { direction = .uphill }
                else if let grade, grade <= -0.06 { direction = .downhill }
                else { direction = nil }
                if direction != previous { since = fix.meters; previous = direction }
                if let direction, fix.meters - since >= 100 { result.insert(direction) }
            }
            if result.count == 2 { break }
        }
        return result
    }
}
