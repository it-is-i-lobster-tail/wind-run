//
//  CoachSheet.swift
//  Wind Run
//

import Foundation

/// The coach screens that open over the plan.
enum CoachSheet: Identifiable, Hashable {
    case runCheckIn(runID: UUID)
    case weeklyCheckIn(weekIndex: Int)
    case morningCheck(runID: UUID)
    case reportInjury(origin: InjuryOrigin, runID: UUID?, level: InjuryLevel? = nil)
    case recoveryPlan(reportID: UUID)
    case returnPlan(reportID: UUID)
    case lifeHappens(LifeEventKind?)
    case settings
    case raceRecordedElsewhere
    case raceMoved
    /// The goal screen for what comes next, starting from this flavor and, when kept, this distance.
    case newGoal(CoachGoal, distance: RaceDistance?)
    /// The whole setup again, as a new plan for this goal, such as after a long injury pause.
    case setUpAgain(CoachGoal)

    var id: Self { self }
}
