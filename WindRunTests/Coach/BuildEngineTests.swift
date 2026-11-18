//
//  BuildEngineTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// The coach's paths the plan tests don't walk: missed and deleted runs, the restart after two low weeks, the
/// clearance answers, a change of level, Mild getting better, a stopped plan and the end of a plan.
@MainActor
struct BuildEngineTests {
    static var calendar: Calendar { BuildPlannerTests.calendar }

    static func day(_ offset: Int) -> Date { BuildPlannerTests.day(offset) }

    /// The 50K plan started on Monday 2 November, so week 1 is a full week: Tuesday, Wednesday, Thursday, Saturday
    /// and Sunday.
    static func monday() -> BuildPlanState {
        BuildEngine.start(BuildPlannerTests.fiftyK(), runs: [], now: day(5), calendar: calendar)
    }

    /// Every session of the week run at `share` of its target, at 7 in the morning.
    static func runs(doing state: BuildPlanState, week number: Int, share: Double = 1) -> [CoachRun] {
        state.week(number)?.sessions.map { session in
            CoachRun(start: session.date.addingTimeInterval(7 * 3_600), meters: session.target.meters * share, climb: session.target.climb * share, plannedSessionID: session.id)
        } ?? []
    }

    static func start(of number: Int, in state: BuildPlanState) -> Date {
        state.planCalendar.start(of: number, calendar: calendar)
    }

    @Test func weekOneIsAFullWeek() throws {
        let state = Self.monday()
        let week = try #require(state.week(1))
        #expect(week.start == Self.day(5))
        #expect(week.sessions.map(\.date) == [Self.day(6), Self.day(7), Self.day(8), Self.day(10), Self.day(11)])
        #expect(week.sessions.allSatisfy { $0.target.meters > 0 })
    }

    /// A planned run whose day goes by without a run is missed; today's isn't yet.
    @Test func aPastUnrunSessionIsMissed() throws {
        var state = Self.monday()
        state = BuildEngine.refresh(state, runs: [], now: Self.day(8), calendar: Self.calendar)
        let week = try #require(state.week(1))
        #expect(week.sessions.map(\.status) == [.missed, .missed, .planned, .planned, .planned])
        // What the missed runs had goes to the runs left, never past half the week for the long run.
        let left = week.sessions.filter(\.status.isPlanned)
        #expect(left.map(\.kind) == [.easy, .long, .easy])
        #expect(left.allSatisfy { $0.target.meters <= week.target.meters * BuildLimits.longRunMaxShare + 0.01 })
    }

    /// A run deleted after it matched: its session is planned again, then missed once its day is past.
    @Test func aDeletedRunMakesItsSessionPlannedAgain() throws {
        var state = Self.monday()
        let tuesday = try #require(state.week(1)?.sessions.first)
        let run = CoachRun(start: tuesday.date.addingTimeInterval(7 * 3_600), meters: tuesday.target.meters, plannedSessionID: tuesday.id)
        state = BuildEngine.refresh(state, runs: [run], now: tuesday.date.addingTimeInterval(10 * 3_600), calendar: Self.calendar)
        #expect(state.week(1)?.sessions.first?.status == .done(runID: run.id))
        state = BuildEngine.refresh(state, runs: [], now: tuesday.date.addingTimeInterval(11 * 3_600), calendar: Self.calendar)
        #expect(state.week(1)?.sessions.first?.status == .planned)
        state = BuildEngine.refresh(state, runs: [], now: Self.day(7), calendar: Self.calendar)
        #expect(state.week(1)?.sessions.first?.status == .missed)
    }

    /// A run on a planned day with no session id counts for that day's session.
    @Test func aRunOnAPlannedDayCountsForIt() throws {
        var state = Self.monday()
        let wednesday = try #require(state.week(1)?.sessions.first { $0.date == Self.day(7) })
        #expect(state.week(1)?.plannedSessionIndex(on: Self.day(7).addingTimeInterval(9 * 3_600), calendar: Self.calendar) == 1)
        let run = CoachRun(start: Self.day(7).addingTimeInterval(9 * 3_600), meters: 3_000)
        state = BuildEngine.refresh(state, runs: [run], now: Self.day(7).addingTimeInterval(12 * 3_600), calendar: Self.calendar)
        let week = try #require(state.week(1))
        #expect(week.sessions.first { $0.id == wednesday.id }?.status == .done(runID: run.id))
        // A done session is no longer the day's planned one.
        #expect(week.plannedSessionIndex(on: Self.day(7), calendar: Self.calendar) == nil)
        #expect(week.done == WeekVolume(meters: 3_000))
    }

    /// Two building weeks in a row under half done: the plan starts again from what was run lately, never under the
    /// floor and never over the base it had.
    @Test func twoLowWeeksRestartFromRecentRuns() throws {
        var state = Self.monday()
        var allRuns = Self.runs(doing: state, week: 1, share: 0.3)
        state = BuildEngine.refresh(state, runs: allRuns, now: Self.start(of: 2, in: state), calendar: Self.calendar)
        #expect(state.lowWeeks == 1)
        #expect(state.week(2)?.kind == .holding)
        allRuns += Self.runs(doing: state, week: 2, share: 0.3)
        let oldBase = state.base
        state = BuildEngine.refresh(state, runs: allRuns, now: Self.start(of: 3, in: state), calendar: Self.calendar)
        #expect(state.lowWeeks == 0)
        #expect(!state.holdNext)

        let done1 = try #require(state.week(1)).done
        let done2 = try #require(state.week(2)).done
        let average = WeekVolume(meters: (done1.meters + done2.meters) / 2, climb: (done1.climb + done2.climb) / 2)
        let floor = BuildPlanner.startingFloor(peakClimb: state.settings.goal.peakWeekClimbMeters)
        let week3 = try #require(state.week(3))
        // Week 3 is planned from the restarted base, as a building week rather than a repeat.
        #expect(week3.kind == .building)
        #expect(!week3.holdBefore)
        #expect(abs(week3.baseBefore.meters - min(oldBase.meters, max(average.meters, floor.meters))) < 0.01)
        #expect(abs(week3.baseBefore.climb - min(oldBase.climb, max(average.climb, floor.climb))) < 0.01)
        #expect(week3.baseBefore.meters < oldBase.meters)
    }

    /// Moderate, not cleared or not sure: the plan stays paused.
    @Test func notClearedStaysPaused() throws {
        for answer in [ClearanceAnswer.no, .notSure] {
            var state = Self.monday()
            state = BuildEngine.reportInjury(level: .intense, area: nil, runID: nil, state: state, runs: [], now: Self.day(5), calendar: Self.calendar)
            let report = try #require(state.openInjuries.first)
            state = BuildEngine.answerClearance(answer, reportID: report.id, state: state, runs: [], now: Self.day(5), calendar: Self.calendar)
            #expect(state.isPaused, "\(answer)")
            #expect(state.injuries.first?.clearance == answer)
            #expect(state.injuries.first?.recovery == nil)
            #expect(state.week(1)?.kind == .paused)
            state = BuildEngine.refresh(state, runs: [], now: Self.start(of: 2, in: state), calendar: Self.calendar)
            #expect(state.week(2)?.kind == .paused)
        }
    }

    /// A report moved to another level starts over: its recovery weeks are gone and the plan pauses again.
    @Test func changingLevelClearsRecovery() throws {
        var state = Self.monday()
        state = BuildEngine.reportInjury(level: .severe, area: nil, runID: nil, state: state, runs: [], now: Self.day(5), calendar: Self.calendar)
        let report = try #require(state.openInjuries.first)
        state = BuildEngine.ready(reportID: report.id, state: state, runs: [], now: Self.day(5), calendar: Self.calendar)
        #expect(state.week(1)?.kind == .recovery)
        #expect(state.injuries.first?.recovery == .severe)
        state = BuildEngine.changeInjuryLevel(.intense, reportID: report.id, state: state, runs: [], now: Self.day(5), calendar: Self.calendar)
        let changed = try #require(state.injuries.first)
        #expect(changed.level == .intense)
        #expect(changed.recovery == nil)
        #expect(changed.recoveryStartWeek == nil)
        #expect(changed.clearance == nil)
        #expect(state.isPaused)
        #expect(state.week(1)?.kind == .paused)
    }

    /// Mild, then better: the next week builds again instead of holding.
    @Test func betterEndsTheHold() throws {
        var state = Self.monday()
        state = BuildEngine.reportInjury(level: .mild, area: .shin, runID: nil, state: state, runs: [], now: Self.day(5), calendar: Self.calendar)
        #expect(state.holdsNextBuildingWeek)
        let report = try #require(state.openInjuries.first)
        state = BuildEngine.injuryBetter(reportID: report.id, state: state, now: Self.day(6))
        #expect(state.openInjuries.isEmpty)
        #expect(!state.holdsNextBuildingWeek)
        let allRuns = Self.runs(doing: state, week: 1)
        state = BuildEngine.refresh(state, runs: allRuns, now: Self.start(of: 2, in: state), calendar: Self.calendar)
        #expect(state.week(2)?.kind == .building)
        #expect((state.week(2)?.target.meters ?? 0) > (state.week(1)?.target.meters ?? .infinity))
    }

    @Test func eitherAShortWeekOrAMildInjuryHoldsTheNextWeek() {
        var state = Self.monday()
        #expect(!state.holdsNextBuildingWeek)
        state.holdNext = true
        #expect(state.holdsNextBuildingWeek)
        state.holdNext = false
        state.injuries.append(BuildInjury(id: UUID(), reportedAt: Self.day(5), level: .mild, area: nil, runID: nil, baseAtReport: state.base))
        #expect(state.holdsNextBuildingWeek)
        state.injuries[0].closedAt = Self.day(6)
        #expect(!state.holdsNextBuildingWeek)
    }

    @Test func aStoppedPlanDoesntChange() {
        let stopped = BuildEngine.stop(Self.monday(), now: Self.day(6))
        #expect(stopped.status == .stopped(on: Self.day(6)))
        let later = Self.start(of: 3, in: stopped)
        #expect(BuildEngine.refresh(stopped, runs: Self.runs(doing: stopped, week: 1), now: later, calendar: Self.calendar) == stopped)
    }

    /// Past the goal date every open week closes, even one the plan never refreshed through, and the plan is done.
    @Test func refreshPastTheGoalDateClosesEveryOpenWeek() {
        let settings = BuildSettings(currentWeeklyMeters: 30_000, goal: BuildGoal(event: .halfMarathon, date: Self.day(11)), runDays: [.tuesday, .thursday, .saturday])
        var state = BuildEngine.start(settings, runs: [], now: BuildPlannerTests.now, calendar: Self.calendar)
        #expect(state.planCalendar.count == 2)
        #expect(state.weeks.map(\.number) == [1])
        state = BuildEngine.refresh(state, runs: [], now: Self.day(12), calendar: Self.calendar)
        #expect(state.status == .complete(on: Self.day(12)))
        #expect(!state.weeks.isEmpty)
        #expect(state.weeks.allSatisfy { $0.closed })
        // Nothing was run, so every run with something planned is missed.
        #expect(state.weeks.flatMap(\.sessions).filter { $0.target.meters > 0 }.allSatisfy { $0.status == .missed })
    }
}
