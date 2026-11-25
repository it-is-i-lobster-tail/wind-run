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

    /// The single step's goal for a time, distance or free run, or nil for intervals.
    var singleGoal: IntervalGoal? {
        switch self {
        case .time(let seconds): .time(seconds)
        case .distance(let meters): .distance(meters: meters)
        case .free: .open
        case .intervals: nil
        }
    }

    /// The main part a new workout starts with: 4 × (5 min work, 2 min recover).
    static let starter = WorkoutMain.intervals(.starter)
}

extension WorkoutMain.Intervals {
    /// The work a new set of intervals starts with: 5 minutes.
    static let starterWorkSeconds: TimeInterval = 5 * 60
    /// The recovery a new set of intervals starts with, and what one read without a recovery gets: 2 minutes.
    static let starterRecoverySeconds: TimeInterval = 2 * 60
    /// 4 × (5 min work, 2 min recover).
    static let starter = Self(work: .time(starterWorkSeconds), recovery: .time(starterRecoverySeconds), repeats: 4)
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

    /// What a warm-up or cooldown starts as when it's added: 5 minutes.
    static let defaultEnd = IntervalGoal.time(5 * 60)
    /// The name a workout gets when the runner leaves it blank, which the name box shows as its hint.
    static let defaultName = "My New Run"

    var sport: WorkoutSport = .running
    var suggestedName: String { sport == .cycling ? "My New Ride" : Self.defaultName }

    var name: String
    var manualIcon: String?
    /// Nil without a warm-up.
    var warmup: IntervalGoal?
    var main: WorkoutMain
    /// Nil without a cooldown.
    var cooldown: IntervalGoal?
    /// The pace to hold in the main part, seconds per kilometer, fastest first; one pace is both ends the same.
    /// For intervals it's the work's pace. Nil without one.
    var targetPace: ClosedRange<TimeInterval>?
    /// The one unit the workout's distances and pace are shown and typed in. Distances are kept in meters and
    /// the pace in seconds per kilometer, exactly, so switching it only changes how they read: 1 mi switched
    /// to km and back is still 1 mi.
    var unit: DistanceUnit
    /// The saved display the workout's runs show, or nil for the runner's default.
    var displayScreenID: UUID?

    init(
        name: String,
        warmup: IntervalGoal? = nil,
        main: WorkoutMain,
        cooldown: IntervalGoal? = nil,
        targetPace: ClosedRange<TimeInterval>? = nil,
        unit: DistanceUnit = .kilometers,
        displayScreenID: UUID? = nil
    ) {
        self.name = name
        self.warmup = warmup
        self.main = main
        self.cooldown = cooldown
        self.targetPace = targetPace
        self.unit = unit
        self.displayScreenID = displayScreenID
    }

    /// A new workout: 5 min warm-up, a 20 min run, 5 min cooldown, to change from, in the runner's unit.
    static func starter(unit: DistanceUnit = .kilometers) -> WorkoutDraft {
        WorkoutDraft(name: "", warmup: defaultEnd, main: .time(20 * 60), cooldown: defaultEnd, unit: unit)
    }

    /// The draft of a saved workout. One that doesn't have this shape, such as one from an older version,
    /// is read as closely as it can be: a warm-up step first, a cooldown step last, and the first repeats,
    /// or else the first step, as the main part.
    init(_ plan: IntervalPlan, preferred: DistanceUnit = .kilometers) {
        sport = plan.sport
        manualIcon = plan.iconIsManualValue == true ? plan.iconValue : nil
        name = plan.name
        unit = preferred
        var blocks = Self.nonEmptyBlocks(of: plan)
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
        // One saved before workouts kept a unit reads in the one its distances are round in.
        unit = plan.distanceUnit ?? Self.guessedUnit(distances, preferred: preferred)
        displayScreenID = plan.displayScreenID
    }

    /// Every distance in the workout, in meters.
    var distances: [Double] {
        var goals = [warmup, cooldown].compactMap { $0 }
        switch main {
        case .distance(let meters): goals.append(.distance(meters: meters))
        case .intervals(let intervals): goals += [intervals.work, intervals.recovery]
        case .time, .free: break
        }
        return goals.compactMap { if case .distance(let meters) = $0 { meters } else { nil } }
    }

    /// The unit every distance is round in, or else the runner's own.
    static func guessedUnit(_ distances: [Double], preferred: DistanceUnit) -> DistanceUnit {
        let other = WorkoutDistance.other(than: preferred)
        guard !distances.isEmpty else { return preferred }
        return distances.allSatisfy({ WorkoutDistance.unit(for: $0, preferred: other) == other }) ? other : preferred
    }

    /// Whether a saved workout is exactly a warm-up, a main part and a cooldown, as this version builds them.
    static func fits(_ plan: IntervalPlan) -> Bool {
        let draft = WorkoutDraft(plan)
        let stored = nonEmptyBlocks(of: plan).map { block in
            StoredBlock(repeats: block.repeatCount, steps: block.steps.map { StoredStep(kind: $0.kind, goal: $0.goal, isWalk: $0.isWalk) })
        }
        return stored == draft.storedBlocks
    }

    /// The plan's blocks that have steps, as both reading a plan and `fits` see it.
    private static func nonEmptyBlocks(of plan: IntervalPlan) -> [IntervalBlock] {
        plan.blocks.filter { !$0.steps.isEmpty }
    }

    private static func onlyStep(of block: IntervalBlock?, kind: IntervalStepKind) -> IntervalStep? {
        guard let block, block.repeatCount == 1, block.steps.count == 1, let step = block.steps.first, step.kind == kind else { return nil }
        return step
    }

    private static func main(of blocks: [IntervalBlock]) -> WorkoutMain {
        if let repeats = blocks.first(where: { $0.repeatCount > 1 || $0.steps.count > 1 }), let work = repeats.steps.first {
            let recovery = repeats.steps.dropFirst().first?.goal ?? .time(WorkoutMain.Intervals.starterRecoverySeconds)
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

    struct StoredStep: Equatable, PlannableStep {
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
        storedBlocks.flatMap { PlannedIntervalStep.written($0.steps, repeated: $0.repeats) }
    }

    // MARK: Names

    /// The name to save: the runner's, or "My New Run" when they left it blank.
    var trimmedName: String {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return String((typed.isEmpty ? suggestedName : typed).prefix(IntervalPlan.nameLimit))
    }

    /// A generated placeholder carries no information about the workout.
    var iconQuery: String { trimmedName == suggestedName ? "" : trimmedName }

    // MARK: Saving

    /// Saves the draft as one of the runner's workouts and returns it. Changing a workout that no run has used
    /// yet changes it in place; one a run used is kept for that run and a new one takes its place. A blank name
    /// saves as "My New Run".
    @discardableResult
    func save(
        replacing original: IntervalPlan?,
        in context: ModelContext,
        defaults: UserDefaults = .standard,
        automaticIcon: String = WorkoutIcon.fallback
    ) -> IntervalPlan {
        let plan: IntervalPlan
        let name = trimmedName
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
        plan.workoutTypeValue = sport.rawValue
        plan.iconValue = manualIcon ?? automaticIcon
        plan.iconIsManualValue = manualIcon != nil
        plan.name = name
        plan.isCustomValue = true
        plan.targetPace = sport == .running ? targetPace : nil
        plan.distanceUnit = unit
        plan.displayScreenID = displayScreenID
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
            "display": displayScreenID == nil ? "default" : "own",
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
        let other = Self.other(than: preferred)
        return isRound(in: other) ? other : preferred
    }

    /// Miles for kilometers, and kilometers for miles.
    static func other(than unit: DistanceUnit) -> DistanceUnit {
        unit == .kilometers ? .miles : .kilometers
    }

    /// The amount in `unit` to one decimal, halves rounded up, without a trailing zero: "5", "5.5", "0.4",
    /// a quarter mile "0.3". Never "0": a distance too short for that reads "0.1". Only how it reads; the
    /// meters behind it stay exact.
    static func amount(_ meters: Double, in unit: DistanceUnit) -> String {
        let value = meters / unit.meters
        // A hair over, so a quarter mile that's 0.2499… in floating point still rounds up.
        var tenths = (value * 10 + 1e-9).rounded(.toNearestOrAwayFromZero)
        if tenths == 0, value > 0 { tenths = 1 }
        return (tenths / 10).formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }

    /// "5 km", "8.9 km", "0.4 km", "5.5 mi", "0.25 mi": always in kilometers or miles, the workout's unit,
    /// never meters, so it reads the same way whichever unit the workout is in.
    static func text(_ meters: Double, in unit: DistanceUnit) -> String {
        "\(amount(meters, in: unit)) \(unit.symbol)"
    }

    /// How long a workout is, as `RunFormat.intervalLength` writes it, with its distances in `unit` as `text`
    /// writes them: never meters.
    static func length(_ timeline: [PlannedIntervalStep], in unit: DistanceUnit) -> String {
        RunFormat.intervalLength(timeline, unit: unit) { text($0, in: unit) }
    }

    /// A workout's target pace: "9:30–11:30 min/mi", or "9:30 min/mi" for one pace, from seconds per kilometer.
    /// Rounded to the nearest second, as the target pace boxes show it, so the page and its "Target:" line agree.
    static func paceText(_ range: ClosedRange<TimeInterval>, unit: DistanceUnit) -> String {
        let fast = pacePerUnit(range.lowerBound, unit: unit)
        let slow = pacePerUnit(range.upperBound, unit: unit)
        return (fast == slow ? fast : "\(fast)–\(slow)") + " min/\(unit.symbol)"
    }

    /// "8:45" for a pace per `unit`, from seconds per kilometer, rounded to the nearest second. The target pace
    /// boxes and `paceText` both write a pace this way, so they agree.
    static func pacePerUnit(_ secondsPerKilometer: TimeInterval, unit: DistanceUnit) -> String {
        minutesSeconds(unit.perUnit(secondsPerKilometer))
    }

    /// "5:00" for 300 seconds, rounded to the nearest second.
    static func minutesSeconds(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }

    /// How a part that ends on a tap reads in the builder and on a saved workout's page.
    static let untilNextDetail = "Until you tap Next"

    /// "10 min", "1 km", or "Until you tap Next": how a part ends, as the builder and a saved workout's page
    /// write it.
    static func endDetail(_ goal: IntervalGoal, unit: DistanceUnit) -> String {
        if case .open = goal { return untilNextDetail }
        return text(of: goal, unit: unit)
    }

    /// "10 min", "4:30", "5 km", or "Until Next" for a part that ends on a tap.
    static func text(of goal: IntervalGoal, unit: DistanceUnit) -> String {
        switch goal {
        case .time(let seconds): RunFormat.goal(.time(seconds), unit: unit)
        case .distance(let meters): text(meters, in: unit)
        case .open: "Until Next"
        }
    }
}
