import Foundation
import SwiftData

enum ProgressGroup: Hashable {
    case goal(RunGoal), plan(IntervalPlan), free, cycling, hiking

    init?(_ run: Run) {
        if let plan = run.intervalPlan { self = .plan(plan) }
        else if let goal = run.goal { self = .goal(goal) }
        else if run.kind == .free { self = Self.open(for: run.sport) }
        else { return nil }
    }

    static func open(for sport: WorkoutSport) -> Self {
        switch sport {
        case .cycling: .cycling
        case .hiking: .hiking
        case .running: .free
        }
    }

    var isOpen: Bool { self == .free || self == .cycling || self == .hiking }

    var sport: WorkoutSport {
        switch self {
        case .cycling: .cycling
        case .hiking: .hiking
        case .plan(let plan): plan.sport
        default: .running
        }
    }

    func title(_ unit: DistanceUnit) -> String {
        switch self {
        case .goal(.distance(let meters)): "\(RunFormat.plannedDistance(meters, unit: unit)) run"
        case .goal(.time(let seconds)): "\(RunFormat.duration(seconds)) timed run"
        case .plan(let plan): plan.name
        case .free: "Free runs"
        case .cycling: "Cycling"
        case .hiking: "Hikes"
        }
    }

    var type: WorkoutType {
        switch self {
        case .goal(.distance): .distance
        case .goal(.time): .time
        case .plan(let plan): WorkoutDraft(plan).main.type
        case .free, .cycling, .hiking: .free
        }
    }

    var bestLabel: String? {
        switch self {
        case .goal(.time): return "Farthest at the time goal"
        case .goal(.distance): return "Fastest to the distance goal"
        case .plan(let plan):
            let work = plan.timeline.filter { $0.kind == .work && !$0.isWalk }
            if !work.isEmpty, work.allSatisfy({ if case .distance = $0.goal { true } else { false } }) { return "Fastest completed work" }
            if !work.isEmpty, work.allSatisfy({ if case .time = $0.goal { true } else { false } }) { return "Farthest completed work" }
            return nil
        case .free, .cycling, .hiking: return nil
        }
    }

    /// Smaller ranks first. A run can carry on beyond its goal, so measure at the crossing.
    func rank(_ run: Run) -> Double? {
        switch self {
        case .free, .cycling, .hiking: return nil
        case .goal(let goal):
            // Walking the route is the slow part of ranking a whole group, so each run's rank is kept.
            return RunDerivedCache.shared.value("rank \(goal)", for: run) { Self.rank(run, reaching: goal) }
        case .plan(let plan):
            let timeline = plan.timeline
            let work = timeline.indices.filter { timeline[$0].kind == .work && !timeline[$0].isWalk }
            let log = run.stepLog
            guard !work.isEmpty, log.count == timeline.count,
                  zip(log.indices, log).allSatisfy({ $0.0 == $0.1.index }),
                  log.allSatisfy({ !$0.cut }) else { return nil }
            if work.allSatisfy({ if case .distance = timeline[$0].goal { true } else { false } }) {
                return work.reduce(0) { $0 + log[$1].seconds }
            }
            if work.allSatisfy({ if case .time = timeline[$0].goal { true } else { false } }) {
                return -work.reduce(0) { $0 + log[$1].meters }
            }
            return nil
        }
    }

    /// When a run reached its distance goal, or minus how far it got by its time goal. Nil when it didn't get there.
    private static func rank(_ run: Run, reaching goal: RunGoal) -> Double? {
        let fixes = run.activeRoute
        for (a, b) in zip(fixes, fixes.dropFirst()) where a.stretch == b.stretch {
            switch goal {
            case .distance(let m) where a.meters < m && b.meters + 0.001 >= m && b.meters > a.meters:
                return a.time + (b.time - a.time) * (m - a.meters) / (b.meters - a.meters)
            case .time(let t) where a.time < t && b.time >= t && b.time > a.time:
                return -(a.meters + (b.meters - a.meters) * (t - a.time) / (b.time - a.time))
            default: continue
            }
        }
        return nil
    }
}
