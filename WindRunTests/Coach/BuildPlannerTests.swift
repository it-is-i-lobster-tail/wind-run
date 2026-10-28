//
//  BuildPlannerTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// Build Distance's weeks: never more than 10% on the last building week, easy weeks 25% under it, the goal week
/// easy, and the timeline's 5% and 10% estimates (Brendon, 2026-10-28).
@MainActor
struct BuildPlannerTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Wednesday 28 October 2026, 09:00 UTC.
    static let now = Date(timeIntervalSince1970: 1_793_178_000)
    static let mile = 1_609.344
    static let foot = 0.3048

    static func day(_ offset: Int, from date: Date = BuildPlannerTests.now) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) ?? date
    }

    /// The 50K example: 25 mi a week now with 3,800 ft of climb, 50K with 3,800 ft on Sunday 28 March 2027.
    static func fiftyK(easyWeeks: EasyWeekSchedule = .every(4)) -> BuildSettings {
        BuildSettings(
            currentWeeklyMeters: 25 * mile,
            currentWeeklyClimbMeters: 3_800 * foot,
            goal: BuildGoal(event: .fiftyK, climbMeters: 3_800 * foot, date: day(151)),
            runDays: [.tuesday, .wednesday, .thursday, .saturday, .sunday],
            easyWeeks: easyWeeks
        )
    }

    /// Checks every week against the last building week before it.
    func expectWithinLimits(_ weeks: [TimelineWeek], start: WeekVolume) {
        var base = start
        for week in weeks {
            switch week.kind {
            case .easy, .goal:
                #expect(abs(week.volume.meters - base.meters * 0.75) < 0.01, "week \(week.number)")
            default:
                #expect(week.volume.meters <= base.meters * 1.1 + 0.01, "week \(week.number) grew over 10%")
                #expect(week.volume.climb <= base.climb * 1.1 + 0.01, "week \(week.number) climb grew over 10%")
                #expect(week.volume.meters >= base.meters - 0.01, "week \(week.number) went down")
                base = week.volume
            }
        }
    }

    // MARK: Calendar

    @Test func weeksEndOnTheGoalDate() {
        let plan = PlanCalendar.make(goalDate: Self.day(151), now: Self.now, calendar: Self.calendar)
        #expect(plan.count == 22)
        #expect(plan.end(of: 22, calendar: Self.calendar) == Self.day(151))
        #expect(plan.start(of: 1, calendar: Self.calendar) == Self.day(-2))
        #expect(plan.number(on: Self.now, calendar: Self.calendar) == 1)
        #expect(plan.number(on: Self.day(151), calendar: Self.calendar) == 22)
        #expect(plan.number(on: Self.day(152), calendar: Self.calendar) == 23)
    }

    /// Fewer than 3 days left in the first week: the plan starts the week after.
    @Test func shortFirstWeekStartsNextWeek() {
        // Goal on a Thursday: today's week would end tomorrow.
        let plan = PlanCalendar.make(goalDate: Self.day(141), now: Self.now, calendar: Self.calendar)
        #expect(plan.count == 20)
        #expect(plan.start(of: 1, calendar: Self.calendar) == Self.day(2))
        #expect(plan.number(on: Self.now, calendar: Self.calendar) == 0)
    }

    // MARK: Timeline

    @Test func fiftyKExampleStaysInsideTheLimits() throws {
        let settings = Self.fiftyK()
        let timeline = BuildPlanner.timeline(settings, now: Self.now, calendar: Self.calendar)
        #expect(timeline.weeks.count == 22)
        expectWithinLimits(timeline.weeks, start: BuildPlanner.startingBase(settings))
        #expect(timeline.weeks.last?.kind == .goal)
        #expect(timeline.weeks.filter { $0.kind == .easy }.map(\.number) == [4, 8, 12, 16, 20])
        #expect(timeline.reachesPeak)
        #expect(timeline.reachesClimb)
        #expect(!timeline.isAmbitious)
        // 46.6 mi from 25 needs under 5% a week over 16 building weeks, so the plan adds 5% and holds the peak.
        #expect(abs(timeline.firstRate - 0.05) < 0.0001)
        let fastest = try #require(timeline.fastestPeakWeek)
        let slowest = try #require(timeline.slowestPeakWeek)
        #expect(fastest == 9)
        #expect(slowest == 17)
        #expect(timeline.planPeakWeek == 17)
    }

    @Test func tooLittleTimeIsAmbitiousButStillPlanned() {
        let settings = BuildSettings(
            currentWeeklyMeters: 10 * Self.mile,
            goal: BuildGoal(event: .marathon, date: Self.day(67)),
            runDays: [.tuesday, .thursday, .saturday]
        )
        let timeline = BuildPlanner.timeline(settings, now: Self.now, calendar: Self.calendar)
        #expect(timeline.weeks.count == 10)
        #expect(timeline.isAmbitious)
        #expect(abs(timeline.firstRate - 0.10) < 0.0001)
        expectWithinLimits(timeline.weeks, start: BuildPlanner.startingBase(settings))
        #expect((timeline.fastestPeakWeek ?? 0) > timeline.weeks.count)
    }

    @Test func rateNeededSitsBetweenFiveAndTenPercent() {
        #expect(BuildPlanner.rate(from: 10, to: 20, weeks: 100) == 0.05)
        #expect(BuildPlanner.rate(from: 10, to: 20, weeks: 2) == 0.10)
        #expect(abs(BuildPlanner.rate(from: 10, to: 20, weeks: 10) - (pow(2, 0.1) - 1)) < 0.0001)
        #expect(BuildPlanner.rate(from: 20, to: 20, weeks: 10) == 0)
    }

    @Test func noRunningStartsAtFiveKilometres() {
        var settings = Self.fiftyK()
        settings.currentWeeklyMeters = 0
        settings.currentWeeklyClimbMeters = 0
        let base = BuildPlanner.startingBase(settings)
        #expect(base.meters == 5_000)
        #expect(abs(base.climb - settings.goal.peakWeekClimbMeters * 0.1) < 0.01)
    }

    @Test func peakIsOneAndAHalfTimesTheEvent() {
        #expect(BuildGoal(event: .fiveK, date: Self.now).peakWeekMeters == BuildLimits.minimumPeakMeters)
        #expect(BuildGoal(event: .marathon, date: Self.now).peakWeekMeters == 42_195 * 1.5)
        #expect(BuildGoal(event: .fiftyK, climbMeters: 1_000, date: Self.now).peakWeekClimbMeters == 1_500)
    }

    @Test func chosenEasyWeeksReplaceTheSchedule() {
        let settings = Self.fiftyK(easyWeeks: .chosen([5, 11]))
        let timeline = BuildPlanner.timeline(settings, now: Self.now, calendar: Self.calendar)
        #expect(timeline.weeks.filter { $0.kind == .easy }.map(\.number) == [5, 11])
        expectWithinLimits(timeline.weeks, start: BuildPlanner.startingBase(settings))
        #expect(EasyWeekSchedule.every(4).toggling(6, through: 12) == .chosen([4, 6, 8]))
    }

    // MARK: Splitting a week

    @Test func longRunIsTwiceTheOthersUpToHalf() {
        #expect(BuildPlanner.longShare(runs: 1) == 1)
        #expect(BuildPlanner.longShare(runs: 2) == 0.5)
        #expect(BuildPlanner.longShare(runs: 3) == 0.5)
        #expect(BuildPlanner.longShare(runs: 4) == 0.4)
        let days = (0 ..< 4).map { Self.day($0 + 6) } // Tuesday to Friday
        let split = BuildPlanner.split(WeekVolume(meters: 40_000), over: days, longRun: true, calendar: Self.calendar)
        #expect(split.map(\.kind) == [.easy, .easy, .easy, .long])
        #expect(split.map { $0.volume.meters.rounded() } == [8_000, 8_000, 8_000, 16_000])
    }

    @Test func longRunGoesOnSaturday() {
        let days = [Self.day(6), Self.day(10), Self.day(11)] // Tuesday, Saturday, Sunday
        #expect(BuildPlanner.longRunIndex(days, calendar: Self.calendar) == 1)
    }

    // MARK: The plan

    func runs(doing state: BuildPlanState, week number: Int, share: Double = 1) -> [CoachRun] {
        state.week(number)?.sessions.map { session in
            CoachRun(start: session.date.addingTimeInterval(7 * 3_600), meters: session.target.meters * share, climb: session.target.climb * share, plannedSessionID: session.id)
        } ?? []
    }

    /// A runner who does every run: the plan's weeks follow the timeline setup showed.
    @Test func planFollowsTheTimeline() {
        let settings = Self.fiftyK()
        let timeline = BuildPlanner.timeline(settings, now: Self.now, calendar: Self.calendar)
        var state = BuildEngine.start(settings, runs: [], now: Self.now, calendar: Self.calendar)
        var allRuns: [CoachRun] = []
        for number in 1 ... 22 {
            allRuns += runs(doing: state, week: number)
            let next = state.planCalendar.start(of: number + 1, calendar: Self.calendar).addingTimeInterval(3_600)
            state = BuildEngine.refresh(state, runs: allRuns, now: next, calendar: Self.calendar)
            if number < 22 {
                let planned = state.week(number + 1)?.target.meters ?? 0
                let expected = timeline.weeks[number].volume.meters
                #expect(abs(planned - expected) < 1, "week \(number + 1)")
            }
        }
        #expect(state.status == .complete(on: state.planCalendar.start(of: 23, calendar: Self.calendar).addingTimeInterval(3_600)))
        let event = state.week(22)?.sessions.last
        #expect(event?.kind == .event)
        #expect(event?.date == Self.day(151))
    }

    /// Under 90% of a building week: the next building week repeats it.
    @Test func shortWeekRepeats() {
        let settings = Self.fiftyK()
        var state = BuildEngine.start(settings, runs: [], now: Self.day(5), calendar: Self.calendar)
        // Week 1 is the first full week here (the plan starts on a Monday).
        var allRuns = runs(doing: state, week: 1, share: 0.8)
        state = BuildEngine.refresh(state, runs: allRuns, now: state.planCalendar.start(of: 2, calendar: Self.calendar), calendar: Self.calendar)
        let week1 = state.week(1)?.target.meters ?? 0
        #expect(state.week(2)?.kind == .holding)
        #expect(abs((state.week(2)?.target.meters ?? 0) - week1) < 0.01)
        allRuns += runs(doing: state, week: 2)
        state = BuildEngine.refresh(state, runs: allRuns, now: state.planCalendar.start(of: 3, calendar: Self.calendar), calendar: Self.calendar)
        #expect(state.week(3)?.kind == .building)
        #expect((state.week(3)?.target.meters ?? 0) > week1)
    }

    /// Runs left in the week take what's left of it, and a done run stays when run days change.
    @Test func changingRunDaysKeepsFinishedRuns() throws {
        let settings = Self.fiftyK()
        let monday = Self.day(5)
        var state = BuildEngine.start(settings, runs: [], now: monday, calendar: Self.calendar)
        let tuesday = try #require(state.week(1)?.sessions.first)
        let run = CoachRun(start: tuesday.date.addingTimeInterval(7 * 3_600), meters: tuesday.target.meters, plannedSessionID: tuesday.id)
        state = BuildEngine.refresh(state, runs: [run], now: Self.day(7), calendar: Self.calendar)
        state = BuildEngine.changeRunDays([.thursday, .saturday], state: state, runs: [run], now: Self.day(7), calendar: Self.calendar)
        let week = try #require(state.week(1))
        #expect(week.sessions.first?.status == .done(runID: run.id))
        let left = week.sessions.filter(\.status.isPlanned)
        #expect(left.map { Weekday(of: $0.date, calendar: Self.calendar) } == [.thursday, .saturday])
        #expect(left.last?.kind == .long)
        #expect(left.allSatisfy { $0.target.meters <= week.target.meters * 0.5 + 0.01 })
    }

    @Test func severeInjuryPausesThenReturnsAtHalf() throws {
        let settings = Self.fiftyK()
        let monday = Self.day(5)
        var state = BuildEngine.start(settings, runs: [], now: monday, calendar: Self.calendar)
        let base = state.base
        state = BuildEngine.reportInjury(level: .severe, area: .knee, runID: nil, state: state, runs: [], now: monday, calendar: Self.calendar)
        #expect(state.isPaused)
        #expect(state.week(1)?.kind == .paused)
        #expect(state.week(1)?.sessions.isEmpty == true)
        state = BuildEngine.refresh(state, runs: [], now: state.planCalendar.start(of: 2, calendar: Self.calendar), calendar: Self.calendar)
        let report = try #require(state.openInjuries.first)
        state = BuildEngine.ready(reportID: report.id, state: state, runs: [], now: state.planCalendar.start(of: 2, calendar: Self.calendar), calendar: Self.calendar)
        #expect(state.week(2)?.kind == .recovery)
        #expect(abs((state.week(2)?.target.meters ?? 0) - base.meters * 0.5) < 0.01)
        state = BuildEngine.refresh(state, runs: [], now: state.planCalendar.start(of: 4, calendar: Self.calendar), calendar: Self.calendar)
        #expect(state.week(3)?.kind == .recovery)
        // Week 4 is an easy week on the schedule; week 5 builds from the recovery weeks, not the old base.
        state = BuildEngine.refresh(state, runs: [], now: state.planCalendar.start(of: 5, calendar: Self.calendar), calendar: Self.calendar)
        #expect(state.openInjuries.isEmpty)
        #expect((state.week(5)?.target.meters ?? 0) <= base.meters * 0.5 * 1.1 + 0.01)
    }

    @Test func mildInjuryHoldsTheMileage() {
        let settings = Self.fiftyK()
        let monday = Self.day(5)
        var state = BuildEngine.start(settings, runs: [], now: monday, calendar: Self.calendar)
        state = BuildEngine.reportInjury(level: .mild, area: .shin, runID: nil, state: state, runs: [], now: monday, calendar: Self.calendar)
        let allRuns = runs(doing: state, week: 1)
        state = BuildEngine.refresh(state, runs: allRuns, now: state.planCalendar.start(of: 2, calendar: Self.calendar), calendar: Self.calendar)
        #expect(state.week(2)?.kind == .holding)
        #expect(abs((state.week(2)?.target.meters ?? 0) - (state.week(1)?.target.meters ?? 0)) < 0.01)
    }
}
