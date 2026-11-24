//
//  IntervalPlan.swift
//  Wind Run
//

import Foundation
import SwiftData

/// A saved interval workout, such as "10 min warm up, 5 × (3 min hard, 2 min easy), 10 min cool down".
@Model
final class IntervalPlan {
    static let nameLimit = 40

    /// Older stores have no sport and describe running workouts.
    var workoutTypeValue: String?
    var sport: WorkoutSport { WorkoutSport(stored: workoutTypeValue) }

    var nameValue: String = ""
    var createdDateValue: Date = Date.now
    /// True for a workout the runner built on the Workout page; false once they deleted or edited it
    /// but a run still uses it; nil for the coach's session steps. Optional so older stores still load.
    var isCustomValue: Bool?
    /// The main part's target pace in seconds per kilometer, the faster end then the slower; both the same for
    /// one pace. Nil without one, and always for the coach's steps. Optional so older stores and iCloud records
    /// still load. These two fields are new on the IntervalPlan iCloud record: deploy the CloudKit schema to
    /// production before shipping a build with them.
    var targetPaceFastValue: Double?
    var targetPaceSlowValue: Double?
    /// The unit the workout's distances and pace are shown and typed in, "kilometers" or "miles". Nil for
    /// the coach's steps and workouts saved before it, which read in the unit their distances are round in.
    /// Also new on the iCloud record, so it goes out with the same CloudKit schema deploy.
    var distanceUnitValue: String?
    /// The id of the saved display (`DisplayLibrary`) runs of this workout show, or nil for the runner's
    /// default. Also new on the iCloud record, so it goes out with the same CloudKit schema deploy.
    var displayScreenIDValue: String?

    // To-many relationships are optional because iCloud sync requires it.
    @Relationship(deleteRule: .cascade, inverse: \IntervalBlock.planValue)
    var blocksValue: [IntervalBlock]? = []

    @Relationship(deleteRule: .nullify, inverse: \Run.intervalPlanValue)
    var runsValue: [Run]? = []

    /// Coach sessions that use this workout. iCloud sync needs every relationship to have an inverse.
    @Relationship(deleteRule: .nullify, inverse: \CoachWorkout.intervalPlanValue)
    var coachWorkoutsValue: [CoachWorkout]? = []

    init(name: String, createdDate: Date = .now, isCustom: Bool? = nil) {
        self.nameValue = name
        self.createdDateValue = createdDate
        self.isCustomValue = isCustom
    }
}

/// One step as the runner will meet it, with its place among the repeats.
struct PlannedIntervalStep: Hashable {
    let kind: IntervalStepKind
    let goal: IntervalGoal
    /// 1-based repeat number within its block.
    let repetition: Int
    let repeatCount: Int
    /// A walking step, such as a walk break.
    var isWalk = false

    /// The step's name mid-run: "Work", or "Walk" for a walking step.
    var name: String { IntervalStepChoice(kind: kind, isWalk: isWalk).name }

    /// The button that ends this step when it's open: "Run again" on a walk break, else "Next step". The same
    /// on the iPhone, the Watch and the Lock Screen.
    var openStepButtonTitle: String { isWalk ? "Run again" : "Next step" }
}

/// A step as a block holds it, before its repeats are written out.
protocol PlannableStep {
    var kind: IntervalStepKind { get }
    var goal: IntervalGoal { get }
    var isWalk: Bool { get }
}

extension IntervalStep: PlannableStep {}

extension PlannedIntervalStep {
    /// A block's steps in the order they're run, with its repeats written out. A count below 1 runs once.
    static func written<Step: PlannableStep>(_ steps: [Step], repeated repeatCount: Int) -> [PlannedIntervalStep] {
        let count = max(1, repeatCount)
        return (1...count).flatMap { repetition in
            steps.map {
                PlannedIntervalStep(kind: $0.kind, goal: $0.goal, repetition: repetition, repeatCount: count, isWalk: $0.isWalk)
            }
        }
    }
}

extension IntervalPlan {
    var name: String {
        get { nameValue }
        set { nameValue = newValue }
    }

    var blocks: [IntervalBlock] {
        (blocksValue ?? []).sorted { $0.order < $1.order }
    }

    var runs: [Run] { runsValue ?? [] }

    /// The unit the workout is shown and typed in, or nil when it wasn't saved with one.
    var distanceUnit: DistanceUnit? {
        get { distanceUnitValue.flatMap(DistanceUnit.init(rawValue:)) }
        set { distanceUnitValue = newValue?.rawValue }
    }

    /// The saved display runs of this workout show, or nil for the default.
    var displayScreenID: UUID? {
        get { displayScreenIDValue.flatMap(UUID.init(uuidString:)) }
        set { displayScreenIDValue = newValue?.uuidString }
    }

    /// The main part's target pace, seconds per kilometer, fastest first. Run against during the main part
    /// only: the work steps of intervals, never a warm-up, recovery or cooldown.
    var targetPace: ClosedRange<TimeInterval>? {
        get {
            guard let fast = targetPaceFastValue, let slow = targetPaceSlowValue, fast > 0, slow > 0 else { return nil }
            return min(fast, slow)...max(fast, slow)
        }
        set {
            targetPaceFastValue = newValue?.lowerBound
            targetPaceSlowValue = newValue?.upperBound
        }
    }

    /// A workout the runner built and still keeps on the Workout page.
    var isSavedWorkout: Bool { isCustomValue == true }

    /// Only the Workout page's workouts, for a query: not the coach's steps or the copies kept for runs.
    static var onIntervalsPage: Predicate<IntervalPlan> {
        let saved: Bool? = true
        return #Predicate { $0.isCustomValue == saved }
    }

    /// When the workout was last run, or made when it hasn't been. The Workout page lists the last one run
    /// first.
    var lastUsed: Date {
        runs.filter { $0.status == .complete }.map(\.startDate).max() ?? createdDateValue
    }

    /// Takes a saved workout off the Workout page. This device deletes it later with `deleteRemoved`, once
    /// no screen shows it, unless runs done with it need its steps.
    func remove(defaults: UserDefaults = .standard) {
        isCustomValue = false
        var removed = RemovedIntervalPlans(defaults: defaults)
        removed.add(persistentModelID)
    }

    /// Deletes the workouts this device took off the Workout page a day or more ago that no run uses.
    ///
    /// Only this device's own, and only after a day: a workout can reach a device through iCloud before the
    /// runs done with it, and deleting it then would take those runs' steps on every device.
    static func deleteRemoved(in context: ModelContext, now: Date = .now, defaults: UserDefaults = .standard) {
        var removed = RemovedIntervalPlans(defaults: defaults)
        guard !removed.isEmpty else { return }
        let all: [IntervalPlan]
        do {
            all = try context.fetch(FetchDescriptor<IntervalPlan>())
        } catch {
            Trace.error("Interval cleanup fetch", error)
            return
        }
        // Looked at here rather than in the fetch, so one taken off a moment ago and not saved yet counts.
        let plans = all.filter { $0.isCustomValue == false }
        // Forgets the ones already gone, such as deleted on another device.
        removed.keep(Set(plans.compactMap { RemovedIntervalPlans.key(for: $0.persistentModelID) }))
        let unused = plans.filter { plan in
            guard plan.runs.isEmpty, let date = removed.date(of: plan.persistentModelID) else { return false }
            return now.timeIntervalSince(date) >= RemovedIntervalPlans.delay
        }
        guard !unused.isEmpty else { return }
        let deleted = Set(unused.compactMap { RemovedIntervalPlans.key(for: $0.persistentModelID) })
        for plan in unused {
            context.delete(plan)
        }
        context.saveQuietly()
        removed.keep(removed.keys.subtracting(deleted))
        Trace.log(.data, "Removed intervals deleted", ["count": unused.count, "kept": plans.count - unused.count])
    }

    @discardableResult
    func addBlock(repeatCount: Int = 1) -> IntervalBlock {
        let block = IntervalBlock(repeatCount: repeatCount, order: (blocks.last?.order ?? -1) + 1)
        blocksValue = (blocksValue ?? []) + [block]
        return block
    }

    /// Every step in the order it's run, with repeats written out.
    var timeline: [PlannedIntervalStep] {
        blocks.flatMap { PlannedIntervalStep.written($0.steps, repeated: $0.repeatCount) }
    }

    /// Total time of the timed steps. Distance and open steps aren't counted.
    var timedDuration: TimeInterval {
        timeline.reduce(0) { total, step in
            if case .time(let seconds) = step.goal { total + seconds } else { total }
        }
    }

    /// The workout the brief describes: 10 min warm up, 5 × (3 min hard, 2 min easy), 10 min cool down.
    static func classicFiveByThree() -> IntervalPlan {
        let plan = IntervalPlan(name: "5 × 3 min")
        plan.addBlock().addStep(.warmup, goal: .time(10 * 60))
        let repeats = plan.addBlock(repeatCount: 5)
        repeats.addStep(.work, goal: .time(3 * 60))
        repeats.addStep(.recovery, goal: .time(2 * 60))
        plan.addBlock().addStep(.cooldown, goal: .time(10 * 60))
        return plan
    }
}

/// The saved workouts this device took off the Workout page, and when.
///
/// Kept on this device only, not in iCloud: a workout that arrives through iCloud already taken off, or a
/// run's own copy of one, can come before the runs that use it, so only the device that took it off ever
/// sweeps it, and only a day later.
nonisolated struct RemovedIntervalPlans {
    static let storageKey = "removedIntervalPlans"
    /// Long enough for runs done with the workout on another device to reach this one first.
    static let delay: TimeInterval = 24 * 60 * 60

    private let defaults: UserDefaults
    /// When each workout was taken off, by `key(for:)`.
    private var dates: [String: Date]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        dates = defaults.dictionary(forKey: Self.storageKey)?.compactMapValues { $0 as? Date } ?? [:]
    }

    /// A workout's identifier written out, so a stored one is matched as text and never read back as an
    /// identifier. Nil when it can't be written, such as for a workout never saved.
    static func key(for id: PersistentIdentifier) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(id)).map { String(decoding: $0, as: UTF8.self) }
    }

    var isEmpty: Bool { dates.isEmpty }

    /// Every workout this device took off, by `key(for:)`.
    var keys: Set<String> { Set(dates.keys) }

    mutating func add(_ id: PersistentIdentifier, at date: Date = .now) {
        guard let key = Self.key(for: id), dates[key] == nil else { return }
        dates[key] = date
        save()
    }

    /// When this device took the workout off the page, or nil when it didn't.
    func date(of id: PersistentIdentifier) -> Date? {
        Self.key(for: id).flatMap { dates[$0] }
    }

    /// Forgets every workout but these, by `key(for:)`.
    mutating func keep(_ keys: Set<String>) {
        let kept = dates.filter { keys.contains($0.key) }
        guard kept.count != dates.count else { return }
        dates = kept
        save()
    }

    private func save() {
        if dates.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else {
            defaults.set(dates, forKey: Self.storageKey)
        }
    }
}
