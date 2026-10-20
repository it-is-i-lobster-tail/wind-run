//
//  HardLimitTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// The hard limits hold whatever the runner does: HL-1 on every run, HL-2 on every week, and the race week's
/// half of peak with easy running only (EV-6), including when an injury shapes that week (EF-5).
@MainActor
struct HardLimitTests {
    let calendar = CoachFixtures.calendar

    /// A runner on `runs` runs a week at `low`-`high` km, longest `longest` km, easy pace `pace` s/km.
    func intake(_ goal: GoalChoice, runs: Int, low: Double, high: Double, longest: Double, pace: Double?, days: Set<Weekday>) -> CoachIntake {
        var intake = CoachFixtures.regularIntake(goal)
        intake.lastFourWeeks = RecentRunning(
            runsPerWeek: runs,
            weeklyLow: .distance(meters: low * 1_000),
            weeklyHigh: .distance(meters: high * 1_000),
            longest: .distance(meters: longest * 1_000)
        )
        intake.easyPace = pace
        intake.runDays = days
        return intake
    }

    /// The planning numbers a recorded week was planned with.
    func context(of record: WeekRecord, in state: CoachState, runs: [LoggedRun]) -> PlanningContext {
        var earlier = state
        record.planBaseline?.restore(into: &earlier)
        earlier.weeks = state.weeks.filter { $0.plan.index < record.plan.index }
        let before = runs.filter { $0.start < record.plan.start }
        return WeekPlanner.makeContext(week: record.plan.index, state: earlier, runs: before, now: record.plan.start, calendar: calendar)
    }

    /// Running planned in a week, the race not counted (EV-6).
    func volume(_ plan: PlannedWeek, unit: VolumeUnit) -> Double {
        plan.sessions.filter { $0.kind.isRun && $0.kind != .race }.reduce(0) { $0 + $1.target.amount(in: unit) }
    }

    func race(in weeks: Int) -> GoalChoice {
        GoalChoice(flavor: .event, distance: .tenK, eventDate: CoachFixtures.day(7 * weeks + 6, hour: 0))
    }

    /// An event date already gone never traps the plan start.
    @Test func pastRaceDate() {
        let goal = GoalChoice(flavor: .event, distance: .tenK, eventDate: CoachFixtures.day(-3, hour: 0))
        let state = CoachEngine.startPlan(intake: CoachFixtures.regularIntake(goal), goal: goal, level: .steady, runs: [], now: CoachFixtures.day(0), calendar: calendar).state
        #expect(state.goal.eventDate == goal.eventDate)
    }

    /// EV-6: with 4 runs a week at low volume, the 20-minute floors would push the race week over half of peak, so
    /// it drops runs instead, and keeps the race with no speed work.
    @Test func raceWeekKeepsHalfOfPeak() throws {
        let start = CoachFixtures.start(intake(race(in: 5), runs: 4, low: 12, high: 14, longest: 5, pace: 400, days: [.tuesday, .thursday, .saturday, .sunday]))
        let simulation = CoachFixtures.follow(start, days: 7 * 5 + 1)
        let record = try #require(simulation.state.weeks.first { $0.plan.index == 5 })
        let peak = WeekPlanner.peakVolume(context(of: record, in: simulation.state, runs: simulation.runs))
        #expect(record.plan.kind == .dead)
        #expect(volume(record.plan, unit: .distance) <= 0.5 * peak + 1)
        #expect(record.plan.sessions.contains { $0.kind == .race })
        #expect(record.plan.sessions.allSatisfy { !$0.isQuality || $0.kind == .race })
        #expect(record.plan.sessions.allSatisfy { $0.strides == 0 })
    }

    /// EF-5: a Mild report open in race week keeps the race, at half of peak at most, with easy running only.
    @Test func mildInjuryKeepsTheRaceWeek() throws {
        let start = CoachFixtures.start(CoachFixtures.regularIntake(race(in: 5)))
        var simulation = CoachFixtures.follow(start, days: 30)
        simulation.state = CoachEngine.reportInjury(level: .mild, area: .calfAchilles, origin: .planScreen, runID: nil, state: simulation.state, runs: simulation.runs, now: CoachFixtures.day(30, hour: 6), calendar: calendar).state
        simulation = CoachFixtures.follow(simulation.state, runs: simulation.runs, days: 6, from: 30)
        let record = try #require(simulation.state.weeks.first { $0.plan.index == 5 })
        let peak = WeekPlanner.peakVolume(context(of: record, in: simulation.state, runs: simulation.runs))
        #expect(record.plan.phase == .raceWeek)
        #expect(volume(record.plan, unit: .distance) <= 0.5 * peak + 1)
        #expect(record.plan.sessions.contains { $0.kind == .race })
        #expect(record.plan.sessions.allSatisfy { !$0.isQuality || $0.kind == .race })
    }

    /// HL-2: a 4-run runner who only does Tuesday and Sunday. W4max follows what was done, and the weeks drop runs
    /// rather than plan 4 runs of 20 minutes over the cap.
    @Test func weekCapHoldsWhenRunsAreSkipped() {
        let goal = GoalChoice(flavor: .buildDistance, distance: .tenK)
        let start = CoachFixtures.start(intake(goal, runs: 4, low: 12, high: 14, longest: 5, pace: 400, days: [.tuesday, .thursday, .saturday, .sunday]))
        let simulation = CoachFixtures.follow(start, days: 7 * 8, skip: { session, _ in session.dayOffset != 1 && session.dayOffset != 6 })
        for record in simulation.state.weeks {
            let context = context(of: record, in: simulation.state, runs: simulation.runs)
            #expect(volume(record.plan, unit: .distance) <= context.weekCap + 1, "week \(record.plan.index)")
        }
    }

    /// AD-10 and HL-2: after 5 weeks off, the first week back restarts at G3's share of the weeks before the gap,
    /// every later week stays inside HL-2, and no run is over 1.10 × P-L30 (HL-1).
    @Test func returnAfterAGap() {
        let start = CoachFixtures.start(CoachFixtures.regularIntake())
        var simulation = CoachFixtures.follow(start, days: 7 * 8)
        simulation = CoachFixtures.follow(simulation.state, runs: simulation.runs, days: 7 * 5, from: 7 * 8, rpe: nil, week: nil, skip: { _, _ in true })
        simulation = CoachFixtures.follow(simulation.state, runs: simulation.runs, days: 7 * 3, from: 7 * 13)
        let ramp = simulation.state.weeks.filter { $0.plan.kind == .ramp }
        #expect(!ramp.isEmpty)
        for record in simulation.state.weeks where record.plan.index >= 13 {
            let context = context(of: record, in: simulation.state, runs: simulation.runs)
            #expect(volume(record.plan, unit: .distance) <= context.weekCap + 1, "week \(record.plan.index)")
            let longest = context.longest.meters
            guard longest > 0 else { continue }
            for session in record.plan.sessions where session.kind.isRun {
                #expect(session.target.meters <= longest * CoachLimits.sessionGrowth + 1, "week \(record.plan.index) \(session.kind)")
            }
        }
    }

    /// HL-2 without an easy pace: the cap falls back to the slow pace and is never 0.
    @Test func capWithoutAnEasyPace() {
        let goal = GoalChoice(flavor: .buildDistance, distance: .halfMarathon)
        let start = CoachFixtures.start(intake(goal, runs: 3, low: 16, high: 18, longest: 10, pace: nil, days: [.tuesday, .thursday, .sunday]))
        #expect(start.paces.easyPace == nil)
        var simulation = CoachFixtures.follow(start, days: 7 * 6)
        simulation = CoachFixtures.follow(simulation.state, runs: simulation.runs, days: 7 * 5, from: 7 * 6, rpe: nil, week: nil, skip: { _, _ in true })
        simulation = CoachFixtures.follow(simulation.state, runs: simulation.runs, days: 7 * 2, from: 7 * 11)
        for record in simulation.state.weeks {
            let context = context(of: record, in: simulation.state, runs: simulation.runs)
            #expect(context.weekCap > 0)
            #expect(volume(record.plan, unit: .distance) <= context.weekCap + 1, "week \(record.plan.index)")
        }
    }

    /// HL-11 and TI-3: a Novice two months in (3 runs and 15-17 km a week, longest 8 km, 7:00/km) is credited
    /// 2 × 4.3 = 8.6 weeks and 8.6 × 15 = 129 km of regular running. Runs stay at 30 minutes until 12 weeks of
    /// regular running, and the early window ends at the first week end that brings the total to 200 km.
    @Test func earlyWindowEndsFromLoggedRunning() {
        var novice = intake(GoalChoice(flavor: .buildDistance, distance: .tenK), runs: 3, low: 15, high: 17, longest: 8, pace: 420, days: [.tuesday, .thursday, .sunday])
        novice.history = .underThreeMonths
        novice.monthsRunning = 2
        let start = CoachFixtures.start(novice)
        #expect(start.assessment.tier == .novice)
        #expect(start.assessment.overlays.earlyWindow)
        #expect(abs(start.assessment.overlays.creditedWeeks - 8.6) < 1e-9)
        #expect(abs(start.assessment.overlays.creditedMeters - 129_000) < 1e-6)

        // Weeks 0-3 end at 11.6 weeks, so every run in them stays at 30 minutes, under the 50 the seed's 7.2 km allows.
        var simulation = CoachFixtures.follow(start, days: 28)
        for record in simulation.state.weeks {
            for session in record.plan.sessions where session.kind.isRun {
                #expect(session.target.seconds <= 30 * 60 + 1, "week \(record.plan.index)")
            }
        }
        // Week 3's end makes 12.6 weeks: the cap lifts, and the window stays open under 200 km.
        let lifted = CoachEngine.refresh(state: simulation.state, runs: simulation.runs, now: CoachFixtures.day(28, hour: 6), calendar: calendar)
        #expect(lifted.notes.contains { $0.text.hasPrefix("Your runs can now grow past 30 minutes") })
        #expect(lifted.state.assessment.overlays.earlyWindow)
        simulation.state = lifted.state

        var ended: Int?
        for week in 4 ..< 10 where ended == nil {
            simulation = CoachFixtures.follow(simulation.state, runs: simulation.runs, days: 7, from: 7 * week)
            let update = CoachEngine.refresh(state: simulation.state, runs: simulation.runs, now: CoachFixtures.day(7 * week + 7, hour: 6), calendar: calendar)
            let end = simulation.state.weekStart(week + 1, calendar: calendar)
            let total = 129_000 + simulation.runs.filter { $0.start < end }.reduce(0) { $0 + $1.meters }
            #expect(update.state.assessment.overlays.earlyWindow == (total < 200_000), "week \(week)")
            if !update.state.assessment.overlays.earlyWindow {
                #expect(update.notes.contains { $0.text.hasPrefix("I've lifted the limits I keep for new runners") })
                ended = week
            }
            simulation.state = update.state
        }
        #expect(ended != nil)
        #expect(simulation.state.weeks.contains { $0.plan.sessions.contains { $0.kind.isRun && $0.target.seconds > 30 * 60 + 1 } })
    }

    /// HL-2 and HL-16: new run days chosen mid-week give the days left only what the week has left, so the week
    /// never gains a run's worth over its plan.
    @Test func midWeekScheduleChange() throws {
        for index in 2 ... 6 {
            let start = CoachFixtures.start(CoachFixtures.regularIntake())
            let simulation = CoachFixtures.follow(start, days: 7 * index + 2)
            let now = CoachFixtures.day(7 * index + 2, hour: 6)
            let state = CoachEngine.changeSchedule(runDays: [.wednesday, .friday, .sunday], weekdayMaxSeconds: nil, weekendMaxSeconds: nil, longRunDay: .sunday, state: simulation.state, runs: simulation.runs, now: now, calendar: calendar).state
            let record = try #require(state.weeks.first { $0.plan.index == index })
            #expect(volume(record.plan, unit: .distance) <= record.plan.plannedVolume + 1, "week \(index)")
            #expect(volume(record.plan, unit: .distance) <= context(of: record, in: state, runs: simulation.runs).weekCap + 1, "week \(index)")
        }
    }
}
