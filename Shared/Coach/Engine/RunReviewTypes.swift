//
//  RunReviewTypes.swift
//  Wind Run
//

import Foundation

/// A run longer than 1.10 × P-L30 (AD-8): it counts at the cap and holds back the next steps.
struct SpikeRecord: Codable, Hashable {
    var runID: UUID
    var date: Date
    /// The run's load and the P-L30 in force when it was run.
    var load: Load
    var longest: Load
    /// Over 1.30 × P-L30: next week HOLD.
    var large: Bool
}

/// What run reviews keep between runs (AD-8, FB-1 to FB-4, PZ-8).
struct RunReviewState: Codable, Hashable {
    /// Runs already reviewed, so a second call for the same run (after its check-in) updates instead of adding.
    var reviewedRunIDs: [UUID]
    var spikes: [SpikeRecord]
    /// Extra runs by plan week, for AD-8's habit offer.
    var extraRunWeeks: [Int]
    /// A hard extra run before the Q gate: no hard or long run until this date (AD-8).
    var hardDayUntil: Date?
    /// The "Fun run!" message shows once.
    var funRunShown: Bool

    init() {
        reviewedRunIDs = []
        spikes = []
        extraRunWeeks = []
        funRunShown = false
    }
}
