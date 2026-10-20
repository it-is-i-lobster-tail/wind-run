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
    case reportInjury(origin: InjuryOrigin, runID: UUID?)
    case recoveryPlan(reportID: UUID)
    case returnPlan(reportID: UUID)
    case lifeHappens(LifeEventKind?)
    case settings

    var id: Self { self }
}
