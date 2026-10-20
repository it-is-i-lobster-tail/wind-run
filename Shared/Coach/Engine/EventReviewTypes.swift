//
//  EventReviewTypes.swift
//  Wind Run
//

import Foundation

/// The event forecast and its checks, re-run each week (EF-1 to EF-9).
struct EventReviewState: Codable, Hashable {
    /// The forecast at the last weekly check.
    var forecast: RaceForecast?
    /// Slip triggers seen so far (EF-2), by plan week.
    var slipWeeks: [Int]
    /// The race was run (EV-9), with its run.
    var raceRunID: UUID?
    /// "Did you race?" was asked after race day passed with no run logged.
    var askedDidYouRace: Bool

    init() {
        slipWeeks = []
        askedDidYouRace = false
    }
}
