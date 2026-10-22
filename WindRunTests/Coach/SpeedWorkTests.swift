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

    /// A marathoner already at Green readiness (SW-1b): a marathon in the last 18 months, 4 runs and about
    /// 45 km a week, longest run 30 km.
    func marathonIntake(_ goal: GoalChoice? = nil) -> CoachIntake {
        var intake = CoachFixtures.regularIntake(goal ?? GoalChoice(flavor: .speedWork, distance: .marathon, targetSeconds: 4 * 3_600))
        intake.finished = .yesRecently
        intake.lastFourWeeks = RecentRunning(
            runsPerWeek: 4,
            weeklyLow: .distance(meters: 44_000),
            weeklyHigh: .distance(meters: 46_000),
            longest: .distance(meters: 30_000)
        )
        intake.runDays = [.tuesday, .thursday, .saturday, .sunday]
        return intake
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

    // MARK: The marathon

    func goalCheck(_ intake: CoachIntake) -> GoalCheck {
        let now = CoachFixtures.day(0)
        let assessment = RunnerAssessor.assess(intake, now: now, calendar: calendar)
        let paces = PaceCalculator.initialPaces(intake, now: now, calendar: calendar)
        return GoalChecker.check(intake.goal, intake: intake, assessment: assessment, paces: paces, level: .steady, now: now, calendar: calendar)
    }

    /// SW-1a: Speed Work offers every distance from the mile to the marathon.
    @Test func marathonIsOffered() {
        #expect(CoachGoal.speedWork.distances == [.mile, .fiveK, .tenK, .halfMarathon, .marathon])
    }

    /// SW-1b: the marathon's distance comes first, as Train for an Event's Green row: a 30 km long run on
    /// 40 km a week.
    @Test func marathonReadiness() {
        let goal = GoalChoice(flavor: .speedWork, distance: .marathon, targetSeconds: 4 * 3_600)
        let targets = GoalChecker.greenTargets(for: goal)
        #expect(targets.longRun == 30_000)
        #expect(targets.volume == 40_000)
        let ready = CoachFixtures.start(marathonIntake())
        #expect(WeekPlanner.goalLongRun(ready, pace: ready.paces.easyPace)?.meters == 30_000)
    }

    /// SW-4: a marathon goal is threshold-led like the half: threshold every load week with one slot, and with
    /// two the second alternates VO2max and threshold.
    @Test func marathonMix() {
        var state = CoachFixtures.start(marathonIntake())
        #expect(QualityPlanner.types(count: 1, state: state, weekIndex: 6, phase: .speedBlock) == [.threshold])
        state.quality.recentTypes = [.threshold]
        #expect(QualityPlanner.types(count: 1, state: state, weekIndex: 7, phase: .speedBlock) == [.threshold])
        #expect(QualityPlanner.types(count: 2, state: state, weekIndex: 6, phase: .speedBlock) == [.threshold, .vo2max])
        #expect(QualityPlanner.types(count: 2, state: state, weekIndex: 7, phase: .speedBlock) == [.threshold, .threshold])
    }

    /// A ready marathoner runs a full block: it opens with the 5 km test (PZ-3a), then threshold sessions one
    /// step a week, never above W4max or the long run already reached (SW-3a, HL-3), and ends with the retest.
    @Test func marathonBlock() throws {
        let state = CoachFixtures.start(marathonIntake())
        let plan = CoachFixtures.follow(state, days: 7 * 16).state
        let blockWeeks = plan.weeks.map(\.plan).filter { $0.blockWeek != nil }.sorted { $0.index < $1.index }
        let first = try #require(blockWeeks.first)
        #expect(first.blockWeek == 1)
        let test = try #require(first.sessions.first { $0.kind == .test })
        #expect(test.appTest == AppTest(goal: .distance(meters: 5_000), controlled: false))

        let loads = blockWeeks.filter { $0.kind != .stepBack && $0.blockWeek != 1 }
        #expect(!loads.isEmpty)
        for week in loads {
            #expect(week.qualitySessions.map(\.kind).allSatisfy { $0 == .threshold })
            #expect(!week.qualitySessions.isEmpty)
        }
        let steps = loads.prefix(2).compactMap { $0.qualitySessions.first?.dose?.step }
        #expect(steps == [0, 1])

        let usual = try #require(plan.weeks.map(\.plan).filter { $0.index < first.index && $0.kind != .stepBack && $0.kind != .calibration }.last)
        for week in blockWeeks {
            #expect(week.plannedVolume <= usual.plannedVolume * 1.0001)
            #expect((week.longRun?.meters ?? 0) <= (usual.longRun?.meters ?? 0) * 1.0001)
        }
        let last = try #require(blockWeeks.first { $0.blockWeek == 8 })
        #expect(last.kind == .stepBack)
        #expect(last.sessions.contains { $0.kind == .test })
    }

    /// SW-1b: a runner far from marathon distance gets Build Distance weeks first, and the message says so.
    @Test func marathonDistanceFirst() {
        var intake = marathonIntake(GoalChoice(flavor: .speedWork, distance: .marathon, strongFirstTime: true))
        intake.lastFourWeeks = RecentRunning(runsPerWeek: 4, weeklyLow: .distance(meters: 30_000), longest: .distance(meters: 18_000))
        let check = goalCheck(intake)
        #expect(check.verdict != .refused)
        #expect(check.message.hasPrefix("A strong first marathon needs long runs of about 30 km before speed work pays off."))
        let plan = CoachFixtures.follow(CoachFixtures.start(intake), days: 7 * 6).state
        #expect(plan.weeks.allSatisfy { $0.plan.qualitySessions.isEmpty })
    }

    /// HL-26 still holds in Speed Work: a first marathon needs a year of running and a half first, and the
    /// half is offered in Speed Work.
    @Test func firstMarathonInSpeedWork() {
        var intake = CoachFixtures.regularIntake(GoalChoice(flavor: .speedWork, distance: .marathon, targetSeconds: 4 * 3_600))
        intake.finished = .no
        intake.history = .threeToTwelveMonths
        intake.monthsRunning = 8
        let check = goalCheck(intake)
        #expect(check.refusal == .firstMarathon)
        #expect(check.savedGoal?.flavor == .speedWork)
        #expect(check.alternatives.map(\.goal) == [GoalChoice(flavor: .speedWork, distance: .halfMarathon)])
    }
}
