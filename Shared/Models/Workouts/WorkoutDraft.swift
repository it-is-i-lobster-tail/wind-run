//
//  WorkoutDraft.swift
//  Wind Run
//

import Foundation
import SwiftData

/// The main part of a workout, what the runner came out to do: run for a time, run a distance, run until
/// they tap on, or intervals.
enum WorkoutMain: Hashable {
    case time(TimeInterval)
    case distance(meters: Double)
    /// Runs until the runner taps Next, or until they finish the run when nothing comes after it.
    case free
    case intervals(Intervals)

    /// Work then recover, done some number of times.
    struct Intervals: Hashable {
        var work: IntervalGoal
        var recovery: IntervalGoal
        var repeats: Int
    }

    var type: WorkoutType {
        switch self {
        case .time: .time
        case .distance: .distance
        case .free: .free
        case .intervals: .intervals
        }
    }

    /// The main part a new workout starts with: 4 × (5 min work, 2 min recover).
    static let starter = WorkoutMain.intervals(Intervals(work: .time(5 * 60), recovery: .time(2 * 60), repeats: 4))
}

/// A workout being built or changed: an optional warm-up, the main part, and an optional cooldown. It's plain
/// values, so nothing is stored until the runner taps Save, and a workout a run already used is never
/// changed under that run.
///
/// It's saved as an `IntervalPlan`, the coach's step system, so it runs, shows and sounds the same as the
/// coach's sessions mid-run and goes to the watch the same way: the warm-up and cooldown are a step each, and
/// the main part is one step, or work and recover repeated.
struct WorkoutDraft: Equatable {
    static let timeRange: ClosedRange<TimeInterval> = 5...(5 * 3_600)
    static let distanceRange: ClosedRange<Double> = 50...100_000

    /// What a warm-up or cooldown starts as when it's added: 10 minutes.
    static let defaultEnd = IntervalGoal.time(10 * 60)

    var name: String
    /// Nil without a warm-up.
    var warmup: IntervalGoal?
    var main: WorkoutMain
    /// Nil without a cooldown.
    var cooldown: IntervalGoal?
    /// The pace to hold in the main part, seconds per kilometer, fastest first; one pace is both ends the same.
    /// For intervals it's the work's pace. Nil without one.
    var targetPace: ClosedRange<TimeInterval>?

    init(name: String, warmup: IntervalGoal? = nil, main: WorkoutMain, cooldown: IntervalGoal? = nil, targetPace: ClosedRange<TimeInterval>? = nil) {
        self.name = name
        self.warmup = warmup
        self.main = main
        self.cooldown = cooldown
        self.targetPace = targetPace
    }

    /// A new workout: 10 min warm-up, 4 × (5 min work, 2 min recover), 10 min cooldown, to change from.
    static func starter() -> WorkoutDraft {
        WorkoutDraft(name: "", warmup: defaultEnd, main: .starter, cooldown: defaultEnd)
    }

    /// The draft of a saved workout. One that doesn't have this shape, such as one from an older version,
    /// is read as closely as it can be: a warm-up step first, a cooldown step last, and the first repeats,
    /// or else the first step, as the main part.
    init(_ plan: IntervalPlan) {
        name = plan.name
        var blocks = plan.blocks.filter { !$0.steps.isEmpty }
        if blocks.count > 1, let step = Self.onlyStep(of: blocks.first, kind: .warmup) {
            warmup = step.goal
            blocks.removeFirst()
        }
        if blocks.count > 1, let step = Self.onlyStep(of: blocks.last, kind: .cooldown) {
            cooldown = step.goal
            blocks.removeLast()
        }
        main = Self.main(of: blocks)
        targetPace = plan.targetPace
    }

    /// Whether a saved workout is exactly a warm-up, a main part and a cooldown, as this version builds them.
    static func fits(_ plan: IntervalPlan) -> Bool {
        let draft = WorkoutDraft(plan)
        let blocks = plan.blocks.filter { !$0.steps.isEmpty }
        let stored = blocks.map { block in
            StoredBlock(repeats: block.repeatCount, steps: block.steps.map { StoredStep(kind: $0.kind, goal: $0.goal, isWalk: $0.isWalk) })
        }
        return stored == draft.storedBlocks
    }

    private static func onlyStep(of block: IntervalBlock?, kind: IntervalStepKind) -> IntervalStep? {
        guard let block, block.repeatCount == 1, block.steps.count == 1, let step = block.steps.first, step.kind == kind else { return nil }
        return step
    }

    private static func main(of blocks: [IntervalBlock]) -> WorkoutMain {
        if let repeats = blocks.first(where: { $0.repeatCount > 1 || $0.steps.count > 1 }), let work = repeats.steps.first {
            let recovery = repeats.steps.dropFirst().first?.goal ?? .time(2 * 60)
            return .intervals(.init(work: work.goal, recovery: recovery, repeats: repeats.repeatCount))
        }
        switch blocks.first?.steps.first?.goal {
        case .time(let seconds): return .time(seconds)
        case .distance(let meters): return .distance(meters: meters)
        case .open: return .free
        case nil: return .starter
        }
    }

    // MARK: Steps

    struct StoredStep: Equatable {
        var kind: IntervalStepKind
        var goal: IntervalGoal
        var isWalk = false
    }

    struct StoredBlock: Equatable {
        var repeats: Int
        var steps: [StoredStep]
    }

    /// The blocks the workout is saved as: the warm-up, the main part, then the cooldown.
    var storedBlocks: [StoredBlock] {
        var blocks: [StoredBlock] = []
        if let warmup {
            blocks.append(StoredBlock(repeats: 1, steps: [StoredStep(kind: .warmup, goal: warmup)]))
        }
        switch main {
        case .time(let seconds):
            blocks.append(StoredBlock(repeats: 1, steps: [StoredStep(kind: .work, goal: .time(seconds))]))
        case .distance(let meters):
            blocks.append(StoredBlock(repeats: 1, steps: [StoredStep(kind: .work, goal: .distance(meters: meters))]))
        case .free:
            blocks.append(StoredBlock(repeats: 1, steps: [StoredStep(kind: .work, goal: .open)]))
        case .intervals(let intervals):
            blocks.append(StoredBlock(repeats: IntervalBlock.clampedRepeats(intervals.repeats), steps: [
                StoredStep(kind: .work, goal: intervals.work),
                StoredStep(kind: .recovery, goal: intervals.recovery),
            ]))
        }
        if let cooldown {
            blocks.append(StoredBlock(repeats: 1, steps: [StoredStep(kind: .cooldown, goal: cooldown)]))
        }
        return blocks
    }

    /// Every step in the order it's run, with repeats written out.
    var timeline: [PlannedIntervalStep] {
        storedBlocks.flatMap { block in
            (1...max(1, block.repeats)).flatMap { repetition in
                block.steps.map {
                    PlannedIntervalStep(kind: $0.kind, goal: $0.goal, repetition: repetition, repeatCount: block.repeats, isWalk: $0.isWalk)
                }
            }
        }
    }

    // MARK: Names

    /// The name to save: the runner's, or one made from the main part when they left it blank.
    func trimmedName(unit: DistanceUnit) -> String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((typed.isEmpty ? suggestedName(unit: unit) : typed).prefix(IntervalPlan.nameLimit))
    }

    /// A name from the main part: "4 × 5 min", "8 × 400 m", "45 min run", "5 km run" or "Free run".
    func suggestedName(unit: DistanceUnit) -> String {
        switch main {
        case .time(let seconds):
            return "\(WorkoutDistance.text(of: .time(seconds), unit: unit)) run"
        case .distance(let meters):
            return "\(WorkoutDistance.text(meters, preferred: unit)) run"
        case .free:
            return "Free run"
        case .intervals(let intervals):
            if case .open = intervals.work { return "\(intervals.repeats) repeats" }
            return "\(intervals.repeats) × \(WorkoutDistance.text(of: intervals.work, unit: unit))"
        }
    }

    // MARK: Saving

    /// Saves the draft as one of the runner's workouts and returns it. Changing a workout that no run has used
    /// yet changes it in place; one a run used is kept for that run and a new one takes its place. A blank name
    /// is made in `unit`.
    @discardableResult
    func save(
        replacing original: IntervalPlan?,
        unit: DistanceUnit = .kilometers,
        in context: ModelContext,
        defaults: UserDefaults = .standard
    ) -> IntervalPlan {
        let plan: IntervalPlan
        let name = trimmedName(unit: unit)
        // Which way the save went, for the trace: no names.
        let path: String
        if let original, original.runs.isEmpty {
            path = "inPlace"
            plan = original
            // Unlinked before they're deleted, so nothing reaches a deleted block through the plan.
            let old = original.blocks
            plan.blocksValue = []
            for block in old {
                context.delete(block)
            }
        } else {
            path = original == nil ? "new" : "copied"
            // Kept for the runs done with it until they're gone.
            original?.remove(defaults: defaults)
            // The copy takes the original's place in the list, which puts the last one run first: it starts
            // from the original's last run rather than sinking to when the original was made.
            plan = IntervalPlan(name: name, createdDate: original?.lastUsed ?? .now, isCustom: true)
            context.insert(plan)
        }
        plan.name = name
        plan.isCustomValue = true
        plan.targetPace = targetPace
        for block in storedBlocks {
            let stored = plan.addBlock(repeatCount: block.repeats)
            for step in block.steps {
                stored.addStep(step.kind, goal: Self.clamped(step.goal), isWalk: step.isWalk)
            }
        }
        context.saveQuietly()
        Trace.log(.data, "Workout saved", [
            "path": path,
            "main": main.type.rawValue,
            "warmup": warmup != nil,
            "cooldown": cooldown != nil,
            "targetPace": targetPace.map { $0.lowerBound == $0.upperBound ? "single" : "range" } ?? "none",
            "steps": timeline.count,
            "keptRuns": original?.runs.count ?? 0,
        ])
        return plan
    }

    /// Keeps a step's time or distance inside what a run can sensibly hold.
    static func clamped(_ goal: IntervalGoal) -> IntervalGoal {
        switch goal {
        case .time(let seconds): .time(min(max(seconds, timeRange.lowerBound), timeRange.upperBound))
        case .distance(let meters): .distance(meters: min(max(meters, distanceRange.lowerBound), distanceRange.upperBound))
        case .open: .open
        }
    }
}

/// How the workout pages write a part's distance or time.
enum WorkoutDistance {
    /// The unit a distance was most likely picked in: the runner's own, unless it's a round number only in
    /// the other one, such as 5 mi (8,046.72 m) for a runner who uses kilometers. A workout keeps meters, so
    /// this is how a distance typed in miles still reads in miles.
    static func unit(for meters: Double, preferred: DistanceUnit) -> DistanceUnit {
        func isRound(in unit: DistanceUnit) -> Bool {
            let hundredths = meters / unit.meters * 100
            return abs(hundredths - hundredths.rounded()) < 0.01
        }
        if isRound(in: preferred) { return preferred }
        let other: DistanceUnit = preferred == .kilometers ? .miles : .kilometers
        return isRound(in: other) ? other : preferred
    }

    /// The amount in `unit`, as typed: "5", "0.25", "21.1".
    static func amount(_ meters: Double, in unit: DistanceUnit) -> String {
        (meters / unit.meters).formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    /// "5 km", "400 m", "3.1 mi", "0.25 mi": in the unit it was picked in, without trailing zeros.
    static func text(_ meters: Double, preferred: DistanceUnit) -> String {
        let unit = unit(for: meters, preferred: preferred)
        if unit == .kilometers, meters < 1_000 {
            return "\(Int(meters.rounded())) m"
        }
        return "\(amount(meters, in: unit)) \(unit.symbol)"
    }

    /// "10 min", "4:30", "5 km", or "Until Next" for a part that ends on a tap.
    static func text(of goal: IntervalGoal, unit: DistanceUnit) -> String {
        switch goal {
        case .time(let seconds): RunFormat.goal(.time(seconds), unit: unit)
        case .distance(let meters): text(meters, preferred: unit)
        case .open: "Until Next"
        }
    }
}
