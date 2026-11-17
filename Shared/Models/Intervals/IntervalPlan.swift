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

    var nameValue: String = ""
    var createdDateValue: Date = Date.now
    /// True for a workout the runner built on the Intervals page; false once they deleted or edited it
    /// but a run still uses it; nil for the coach's session steps. Optional so older stores still load.
    var isCustomValue: Bool?

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

    /// A workout the runner built and still keeps on the Intervals page.
    var isSavedWorkout: Bool { isCustomValue == true }

    /// Only the Intervals page's workouts, for a query: not the coach's steps or the copies kept for runs.
    static var onIntervalsPage: Predicate<IntervalPlan> {
        let saved: Bool? = true
        return #Predicate { $0.isCustomValue == saved }
    }

    /// When the workout was last run, or made when it hasn't been. The Intervals page lists the last one run
    /// first.
    var lastUsed: Date {
        runs.filter { $0.status == .complete }.map(\.startDate).max() ?? createdDateValue
    }

    /// Takes a saved workout off the Intervals page. This device deletes it later with `deleteRemoved`, once
    /// no screen shows it, unless runs done with it need its steps.
    func remove(defaults: UserDefaults = .standard) {
        isCustomValue = false
        var removed = RemovedIntervalPlans(defaults: defaults)
        removed.add(persistentModelID)
    }

    /// Deletes the workouts this device took off the Intervals page a day or more ago that no run uses.
    ///
    /// Only this device's own, and only after a day: a workout can reach a device through iCloud before the
    /// runs done with it, and deleting it then would take those runs' steps on every device.
    static func deleteRemoved(in context: ModelContext, now: Date = .now, defaults: UserDefaults = .standard) {
        var removed = RemovedIntervalPlans(defaults: defaults)
        guard !removed.isEmpty else { return }
        let hidden: Bool? = false
        let plans: [IntervalPlan]
        do {
            plans = try context.fetch(FetchDescriptor<IntervalPlan>(predicate: #Predicate { $0.isCustomValue == hidden }))
        } catch {
            Trace.error("Interval cleanup fetch", error)
            return
        }
        // Forgets the ones already gone, such as deleted on another device.
        let ids = Set(plans.map(\.persistentModelID))
        removed.keep { ids.contains($0) }
        let unused = plans.filter { plan in
            guard plan.runs.isEmpty, let date = removed.date(of: plan.persistentModelID) else { return false }
            return now.timeIntervalSince(date) >= RemovedIntervalPlans.delay
        }
        guard !unused.isEmpty else { return }
        let deleted = Set(unused.map(\.persistentModelID))
        for plan in unused {
            context.delete(plan)
        }
        context.saveQuietly()
        removed.keep { !deleted.contains($0) }
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
        blocks.flatMap { block in
            (1...max(1, block.repeatCount)).flatMap { repetition in
                block.steps.map {
                    PlannedIntervalStep(
                        kind: $0.kind,
                        goal: $0.goal,
                        repetition: repetition,
                        repeatCount: block.repeatCount,
                        isWalk: $0.isWalk
                    )
                }
            }
        }
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

/// The saved workouts this device took off the Intervals page, and when.
///
/// Kept on this device only, not in iCloud: a workout that arrives through iCloud already taken off, or a
/// run's own copy of one, can come before the runs that use it, so only the device that took it off ever
/// sweeps it, and only a day later.
nonisolated struct RemovedIntervalPlans {
    static let storageKey = "removedIntervalPlans"
    /// Long enough for runs done with the workout on another device to reach this one first.
    static let delay: TimeInterval = 24 * 60 * 60

    private struct Entry: Codable {
        let id: PersistentIdentifier
        let date: Date
    }

    private let defaults: UserDefaults
    private var entries: [Entry]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    var isEmpty: Bool { entries.isEmpty }

    mutating func add(_ id: PersistentIdentifier, at date: Date = .now) {
        guard !entries.contains(where: { $0.id == id }) else { return }
        entries.append(Entry(id: id, date: date))
        save()
    }

    /// When this device took the workout off the page, or nil when it didn't.
    func date(of id: PersistentIdentifier) -> Date? {
        entries.first { $0.id == id }?.date
    }

    /// Keeps only the workouts `keep` says yes to.
    mutating func keep(where keep: (PersistentIdentifier) -> Bool) {
        let kept = entries.filter { keep($0.id) }
        guard kept.count != entries.count else { return }
        entries = kept
        save()
    }

    private func save() {
        if entries.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else {
            defaults.set(try? JSONEncoder().encode(entries), forKey: Self.storageKey)
        }
    }
}
