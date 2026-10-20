//
//  TravelTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// AD-15: no long run within a day of a long-haul flight, and easy runs only while the body clock catches up.
@MainActor
struct TravelTests {
    let calendar = CoachFixtures.calendar

    func week(_ index: Int, _ state: CoachState) throws -> PlannedWeek {
        try #require(state.weeks.first { $0.plan.index == index }?.plan)
    }

    func trip(on day: Int, zones: Int? = nil, eastward: Bool? = nil, longHaul: Bool) -> LifeEvent {
        var event = LifeEvent(kind: .travelling, start: CoachFixtures.day(day, hour: 0), length: .oneWeek)
        event.timeZones = zones
        event.eastward = eastward
        event.longHaulFlight = longHaul
        return event
    }

    /// A Saturday long-haul flight moves Sunday's long run to Thursday.
    @Test func longRunMovesAwayFromTheFlight() throws {
        let simulation = CoachFixtures.follow(CoachFixtures.start(CoachFixtures.regularIntake()), days: 7 * 3)
        let update = CoachEngine.addLifeEvent(trip(on: 26, longHaul: true), state: simulation.state, runs: simulation.runs, now: CoachFixtures.day(21, hour: 6), calendar: calendar)
        let plan = try week(3, update.state)
        let long = try #require(plan.sessions.first { $0.kind == .long })
        #expect(Weekday(of: plan.start, calendar: calendar).adding(long.dayOffset) == .thursday)
        #expect(plan.notes.contains { $0.text == "Long flight on Saturday, so your long run moves to Thursday." })
    }

    /// Four zones east on a Monday: Monday to Thursday are easy, so that week's Q becomes an easy run.
    @Test func easyDaysAfterCrossingTimeZones() throws {
        let raceDay = CoachFixtures.day(7 * 30 + 6, hour: 0)
        let goal = GoalChoice(flavor: .event, distance: .tenK, eventDate: raceDay)
        let simulation = CoachFixtures.follow(CoachFixtures.start(CoachFixtures.regularIntake(goal)), days: 7 * 5 + 1)
        let before = try week(5, simulation.state)
        #expect(!before.qualitySessions.isEmpty)
        let update = CoachEngine.addLifeEvent(trip(on: 35, zones: 4, eastward: true, longHaul: false), state: simulation.state, runs: simulation.runs, now: CoachFixtures.day(35, hour: 9), calendar: calendar)
        let plan = try week(5, update.state)
        #expect(plan.qualitySessions.isEmpty)
        #expect(plan.sessions.contains { $0.madeEasy == .travel })
        #expect(plan.notes.contains { $0.text == "Easy runs only until Thursday while your body clock catches up." })
    }
}
