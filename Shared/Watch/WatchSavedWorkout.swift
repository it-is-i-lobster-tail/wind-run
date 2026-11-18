//
//  WatchSavedWorkout.swift
//  Wind Run
//

import Foundation
import SwiftData

/// One of the runner's own workouts from the iPhone's Workout page as the watch gets it, so it starts from the wrist in one tap.
/// Workouts are built and changed on the iPhone; the watch keeps the last list it was sent.
struct WatchSavedWorkout: Codable, Hashable, Identifiable {
    var name: String
    var createdDate: Date
    var blocks: [WatchCoachSession.Block]
    /// The main part's target pace, seconds per kilometer. Optional, so the watch still reads a workout from an
    /// iPhone app that doesn't send one.
    var targetPaceFast: Double? = nil
    var targetPaceSlow: Double? = nil
    /// The workout's own unit, "kilometers" or "miles", or nil from an iPhone app that doesn't send one.
    var distanceUnit: String? = nil
    /// The id of the saved display its runs show, or nil for the default, or from an iPhone app that doesn't
    /// send one.
    var displayScreenID: String? = nil

    var id: String { "\(createdDate.timeIntervalSinceReferenceDate)-\(name)" }

    /// Every step in the order it's run, with repeats written out.
    var timeline: [PlannedIntervalStep] {
        blocks.timeline
    }
}

extension WatchSavedWorkout {
    /// The iPhone's saved workout, for sending.
    init(_ plan: IntervalPlan) {
        self.init(
            name: plan.name,
            createdDate: plan.createdDateValue,
            blocks: plan.blocks.map { WatchCoachSession.Block($0) },
            targetPaceFast: plan.targetPace?.lowerBound,
            targetPaceSlow: plan.targetPace?.upperBound,
            distanceUnit: plan.distanceUnitValue,
            displayScreenID: plan.displayScreenIDValue
        )
    }

    /// The watch's own copy of the workout to run, inserted into `context`. The run keeps it, so its steps
    /// read the same later. It isn't a saved workout on the watch: the list stays the iPhone's.
    func makePlan(in context: ModelContext) -> IntervalPlan {
        let plan = IntervalPlan(name: name, isCustom: false)
        plan.targetPaceFastValue = targetPaceFast
        plan.targetPaceSlowValue = targetPaceSlow
        plan.distanceUnitValue = distanceUnit
        plan.displayScreenIDValue = displayScreenID
        plan.addBlocks(blocks)
        context.insert(plan)
        return plan
    }

    /// "45 min", or "22 min + warm up and cool down until Next", with distances in the workout's own unit, or
    /// in `defaultUnit` when it has none.
    func summary(defaultUnit: DistanceUnit) -> String {
        let own = distanceUnit.flatMap(DistanceUnit.init(rawValue:)) ?? defaultUnit
        return WorkoutDistance.length(timeline, in: own)
    }

    // MARK: Sending

    static func encode(_ workouts: [WatchSavedWorkout]) -> Data? {
        try? JSONEncoder().encode(workouts)
    }

    static func decode(_ data: Data?) -> [WatchSavedWorkout] {
        guard let data else { return [] }
        // One workout the watch can't read, such as from a newer iPhone app, drops only itself.
        return LossyList<WatchSavedWorkout>.decode(data, what: "saved workouts")
    }
}
