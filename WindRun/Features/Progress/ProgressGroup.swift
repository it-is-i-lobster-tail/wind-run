import Foundation
import SwiftData

enum ProgressGroup: Hashable {
    case goal(RunGoal), plan(IntervalPlan), free

    init?(_ run: Run) {
        if let plan = run.intervalPlan { self = .plan(plan) }
        else if let goal = run.goal { self = .goal(goal) }
        else if run.kind == .free { self = .free }
        else { return nil }
    }

    func title(_ unit: DistanceUnit) -> String {
        switch self {
        case .goal(.distance(let meters)): "\(RunFormat.plannedDistance(meters, unit: unit)) run"
        case .goal(.time(let seconds)): "\(RunFormat.duration(seconds)) timed run"
        case .plan(let plan): plan.name
        case .free: "Free runs"
        }
    }

    var type: WorkoutType {
        switch self {
        case .goal(.distance): .distance
        case .goal(.time): .time
        case .plan(let plan): WorkoutDraft(plan).main.type
        case .free: .free
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
        case .free: return nil
        }
    }

    /// Smaller ranks first. A run can carry on beyond its goal, so measure at the crossing.
    func rank(_ run: Run) -> Double? {
        switch self {
        case .free: return nil
        case .goal(let goal):
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
}
