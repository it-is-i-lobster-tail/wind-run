//
//  EventPlanTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// Event plans: weeks end on race day, the taper's shares (EV-6) and the race week (the dead week).
@MainActor
struct EventPlanTests {
    let calendar = CoachFixtures.calendar

    @Test func taperShares() {
        #expect(WeekPlanner.taperShares(distance: .tenK, peak: 30_000, week: 1, raceWeek: true).0 == 0.50)
        #expect(WeekPlanner.taperShares(distance: .halfMarathon, peak: 30_000, week: 1, raceWeek: false).0 == 0.70)
        #expect(WeekPlanner.taperShares(distance: .halfMarathon, peak: 30_000, week: 1, raceWeek: false).1 == 0.60)
        #expect(WeekPlanner.taperShares(distance: .halfMarathon, peak: 30_000, week: 2, raceWeek: true).0 == 0.45)
        #expect(WeekPlanner.taperShares(distance: .marathon, peak: 50_000, week: 1, raceWeek: false).0 == 0.75)
        #expect(WeekPlanner.taperShares(distance: .marathon, peak: 50_000, week: 2, raceWeek: false).0 == 0.55)
        #expect(WeekPlanner.taperShares(distance: .marathon, peak: 50_000, week: 3, raceWeek: true).0 == 0.35)
        #expect(WeekPlanner.taperShares(distance: .marathon, peak: 35_000, week: 1, raceWeek: false).0 == 0.65)
    }

    /// The plan's weeks are placed so the race falls on the last day of a week, and the dead week holds the race.
    @Test func raceFallsOnTheLastDayOfAWeek() throws {
        let raceDay = CoachFixtures.day(7 * 16 + 2, hour: 0)
        let goal = GoalChoice(flavor: .event, distance: .tenK, eventDate: raceDay)
        let state = CoachFixtures.start(CoachFixtures.regularIntake(goal))
        let event = try #require(state.event)
        let raceIndex = state.weekIndex(on: raceDay, calendar: calendar)
        let weekStart = state.weekStart(raceIndex, calendar: calendar)
        #expect(calendar.dateComponents([.day], from: weekStart, to: event.raceDate).day == 6)
        #expect(event.taperStart == weekStart)
        #expect(state.startDate <= calendar.startOfDay(for: CoachFixtures.day(0)))
    }

    /// The dead week: at most half the usual volume, no speed work, and the race on race day (EV-6).
    @Test func deadWeek() throws {
        let raceDay = CoachFixtures.day(7 * 5 + 6, hour: 0)
        let goal = GoalChoice(flavor: .event, distance: .tenK, eventDate: raceDay)
        let start = CoachFixtures.start(CoachFixtures.regularIntake(goal))
        let simulation = CoachFixtures.follow(start, days: 7 * 5 + 1)
        let raceIndex = simulation.state.weekIndex(on: raceDay, calendar: calendar)
        let dead = try #require(simulation.state.weeks.first { $0.plan.index == raceIndex }?.plan)
        #expect(dead.kind == .dead)
        #expect(dead.qualitySessions.allSatisfy { $0.kind == .race })
        let race = try #require(dead.sessions.first { $0.kind == .race })
        #expect(race.dayOffset == 6)
        // Peak: the mean of the 4 weeks before the taper; the race's own distance isn't counted.
        let peakWeeks = simulation.state.weeks.filter { $0.plan.index >= raceIndex - 4 && $0.plan.index < raceIndex }
        let peak = peakWeeks.reduce(0) { $0 + $1.plan.plannedVolume } / Double(max(1, peakWeeks.count))
        let easyVolume = dead.runs.filter { $0.kind != .race }.reduce(0) { $0 + $1.target.meters }
        #expect(easyVolume <= 0.5 * peak + 1)
        #expect(dead.longRun == nil)
        #expect(dead.sessions.allSatisfy { $0.strides == 0 })
    }
}
