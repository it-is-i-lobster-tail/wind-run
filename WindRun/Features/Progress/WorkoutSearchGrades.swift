import Foundation

/// The steep stretches along a route. This decodes the whole route, so `WorkoutSearchIndex` works it out
/// once per workout and keeps the answer.
nonisolated enum WorkoutSearchGrades {
    @MainActor static func directions(in run: Run) -> Set<WorkoutSearchTerrain> {
        directions(fixes: run.activeRoute, barometer: run.barometricAltitude)
    }

    /// The same, from fixes and barometer readings already read out of the store, away from the screen.
    static func directions(fixes: [ActiveFix], barometer: [AltitudeSample]) -> Set<WorkoutSearchTerrain> {
        guard let track = Run.altitudeTrack(for: fixes, barometer: barometer) else { return [] }
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
