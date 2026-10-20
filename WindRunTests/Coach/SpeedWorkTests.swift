//
//  SpeedWorkTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// Speed Work's block calendar, its retests and the volume cycle between blocks (SW-3a, SW-3b, SW-6, SW-7a, PZ-3a).
@MainActor
struct SpeedWorkTests {
    let calendar = CoachFixtures.calendar

    func week(_ index: Int, _ state: CoachState) throws -> PlannedWeek {
        try #require(state.weeks.first { $0.plan.index == index }?.plan)
    }

    func fiveKIntake() -> CoachIntake {
        CoachFixtures.regularIntake(GoalChoice(flavor: .speedWork, distance: .fiveK, targetSeconds: 25 * 60))
    }

    /// A Regular runner ready for a 5K block: calibration, one Steady cycle back to their usual week, then an
    /// 8-week block that opens with a test (no anchor yet), alternates threshold and VO2max weeks one step at a
    /// time, steps back in weeks 4 and 8, and ends with the retest (SW-1b, SW-3a, PZ-2a). Volume holds at W4max
    /// and the long run never grows inside the block (HL-3). At HL-14's ceiling the next block follows (SW-6).
    @Test func eightWeekBlock() throws {
        let state = CoachFixtures.start(fiveKIntake())
        let simulation = CoachFixtures.follow(state, days: 7 * 14)
        let plan = simulation.state

        #expect(try week(0, plan).kind == .calibration)
        #expect(try week(1, plan).kind == .calibration)
        #expect(try week(2, plan).phase == .base)
        #expect(try week(2, plan).qualitySessions.isEmpty)
        #expect(try week(4, plan).kind == .stepBack)
        #expect(try week(4, plan).blockWeek == nil)

        let first = try week(5, plan)
        #expect(first.phase == .speedBlock)
        #expect(first.blockWeek == 1)
        let test = try #require(first.sessions.first { $0.kind == .test })
        #expect(test.appTest == AppTest(goal: .time(seconds: 720), controlled: false))
        #expect(test.isKey)
        #expect(first.qualitySessions.filter { $0.kind != .test }.isEmpty)
        // The test doesn't cut the week: volume holds at W4max, the usual week before the block.
        #expect(first.plannedVolume == (try week(3, plan).plannedVolume))

        let second = try week(6, plan)
        #expect(second.blockWeek == 2)
        #expect(second.qualitySessions.map(\.kind) == [.threshold])
        #expect(second.qualitySessions.first?.dose?.step == 0)

        let third = try week(7, plan)
        #expect(third.qualitySessions.map(\.kind) == [.intervals])

        let stepBack = try week(8, plan)
        #expect(stepBack.blockWeek == 4)
        #expect(stepBack.kind == .stepBack)
        #expect(stepBack.qualitySessions.isEmpty)
        #expect(stepBack.plannedVolume < third.plannedVolume)

        let fifth = try week(9, plan)
        #expect(fifth.blockWeek == 5)
        #expect(fifth.qualitySessions.map(\.kind) == [.threshold])
        #expect(fifth.qualitySessions.first?.dose?.step == 1)

        let last = try week(12, plan)
        #expect(last.blockWeek == 8)
        #expect(last.kind == .stepBack)
        #expect(last.sessions.contains { $0.kind == .test })
        #expect(last.qualitySessions.allSatisfy { $0.kind == .test })

        // Inside the block, volume never passes W4max and the long run never grows.
        let usual = try week(3, plan)
        for index in 5 ... 12 {
            let block = try week(index, plan)
            #expect(block.plannedVolume <= usual.plannedVolume * 1.0001)
            #expect((block.longRun?.meters ?? 0) <= (usual.longRun?.meters ?? 0) * 1.0001)
        }

        // This runner's volume is at HL-14's ceiling, so the next block starts straight after the retest week
        // (SW-6), without a second test.
        let next = try week(13, plan)
        #expect(plan.quality.blocksDone == 1)
        #expect(next.blockWeek == 1)
        #expect(!next.sessions.contains { $0.kind == .test })
    }

    /// HL-3: a missed week before the first block means the 3 weeks before it aren't steady, so another cycle
    /// runs first.
    @Test func unsteadyWeeksDelayTheFirstBlock() throws {
        let state = CoachFixtures.start(fiveKIntake())
        let simulation = CoachFixtures.follow(state, days: 7 * 7, skip: { session, day in session.kind == .long && (21 ..< 28).contains(day) })
        let plan = simulation.state
        #expect(try week(5, plan).blockWeek == nil)
    }

    /// SW-6: the volume cycle runs below HL-14's ceiling, and is required at ≤15 km a week with a 10K goal.
    @Test func volumeCycleRule() {
        var state = CoachFixtures.start(fiveKIntake())
        let ceiling = WeekPlanner.volumeCeiling(state, pace: state.paces.easyPace)
        #expect(SpeedWorkPlanner.needsVolumeCycle(state, volume: ceiling * 0.9, pace: state.paces.easyPace))
        #expect(!SpeedWorkPlanner.needsVolumeCycle(state, volume: ceiling, pace: state.paces.easyPace))
        state.goal = GoalChoice(flavor: .speedWork, distance: .tenK)
        #expect(SpeedWorkPlanner.needsVolumeCycle(state, volume: 15_000, pace: state.paces.easyPace))
    }

    /// SW-3b: a busy week keeps the block calendar running.
    @Test func busyWeekKeepsTheCalendar() throws {
        var simulation = CoachFixtures.follow(CoachFixtures.start(fiveKIntake()), days: 7 * 7)
        let busy = LifeEvent(kind: .busy, start: CoachFixtures.day(49, hour: 0), length: .oneWeek)
        simulation.state = CoachEngine.addLifeEvent(busy, state: simulation.state, runs: simulation.runs, now: CoachFixtures.day(48, hour: 21), calendar: calendar).state
        let state = CoachFixtures.follow(simulation.state, runs: simulation.runs, days: 7 * 2, from: 49).state
        let busyWeek = try week(7, state)
        #expect(busyWeek.kind == .busy)
        #expect(busyWeek.blockWeek == 3)
        #expect(try week(8, state).blockWeek == 4)
    }
}
