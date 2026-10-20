//
//  SavedGoalTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// RC-1's saved goals and HL-9's habit mode during a plan: under 2 run days a week the plan switches to 1 run plus
/// walks with the goal saved, and a saved goal is checked again once its cause clears (a second run day, Ready after
/// a Severe pause, its earliest date).
@MainActor
struct SavedGoalTests {
    let calendar = CoachFixtures.calendar

    /// A 10K race in `weeks` weeks for the Regular fixture runner, who finished one recently (no first-race gate).
    func tenKIntake(weeks: Int, finishedRecently: Bool = true) -> CoachIntake {
        var intake = CoachFixtures.regularIntake(GoalChoice(flavor: .event, distance: .tenK, eventDate: CoachFixtures.day(7 * weeks, hour: 9)))
        if finishedRecently { intake.finished = .yesRecently }
        return intake
    }

    /// The Regular fixture runner keeping their distance ("Keep this distance"), with a goal saved for later.
    func keepingDistance(saved: GoalChoice?, earliest offset: Int? = nil) -> CoachState {
        var intake = CoachFixtures.regularIntake()
        intake.finished = .yesRecently
        var state = EventReviewer.maintain(CoachFixtures.start(intake)).state
        state.savedGoal = saved
        state.savedGoalEarliest = offset.map { CoachFixtures.day($0, hour: 0, from: state.startDate) }
        return state
    }

    /// A 10K race `weeks` weeks after the plan's first day.
    func tenK(inWeeks weeks: Int, from state: CoachState) -> GoalChoice {
        GoalChoice(flavor: .event, distance: .tenK, eventDate: CoachFixtures.day(7 * weeks, hour: 9, from: state.startDate))
    }

    /// 06:00 on day `offset` of the plan.
    func at(_ offset: Int, _ state: CoachState) -> Date {
        CoachFixtures.day(offset, hour: 6, from: state.startDate)
    }

    func week(at date: Date, in state: CoachState) throws -> PlannedWeek {
        let index = state.weekIndex(on: date, calendar: calendar)
        return try #require(state.weeks.first { $0.plan.index == index }).plan
    }

    func schedule(_ days: Set<Weekday>, state: CoachState, runs: [LoggedRun], now: Date) -> CoachUpdate {
        CoachEngine.changeSchedule(
            runDays: days,
            weekdayMaxSeconds: nil,
            weekendMaxSeconds: nil,
            longRunDay: days.contains(.sunday) ? .sunday : nil,
            state: state,
            runs: runs,
            now: now,
            calendar: calendar
        )
    }

    // MARK: Habit mode (HL-9)

    @Test func oneRunDaySavesTheEventAndASecondBringsItBack() throws {
        let intake = tenKIntake(weeks: 20)
        let goal = intake.goal
        let started = CoachFixtures.start(intake)
        #expect(started.event != nil)
        let simulation = CoachFixtures.follow(started, days: 9)

        let habit = schedule([.sunday], state: simulation.state, runs: simulation.runs, now: at(9, started))
        #expect(habit.state.status.isActive)
        #expect(habit.state.assessment.habitMode)
        #expect(habit.state.goal.flavor == .buildDistance)
        #expect(habit.state.savedGoal == goal)
        #expect(habit.state.event == nil)
        #expect(habit.notes.contains { $0.text == "Because you told me you can run one day a week now, I've switched to a habit plan. Your 10K goal is saved." })

        let habitWeeks = CoachFixtures.follow(habit.state, runs: simulation.runs, days: 12, from: 9)
        let planned = try week(at: at(16, started), in: habitWeeks.state)
        #expect(planned.kind == .habit)
        #expect(planned.sessions.filter { $0.kind.isRun }.count == 1)
        #expect(planned.sessions.allSatisfy { !$0.isQuality })
        // Habit mode waits for a second run day: the weekly check leaves the goal saved.
        #expect(habitWeeks.state.savedGoal == goal)

        let back = schedule([.tuesday, .thursday, .sunday], state: habitWeeks.state, runs: habitWeeks.runs, now: at(23, started))
        #expect(!back.state.assessment.habitMode)
        #expect(back.state.goal == goal)
        #expect(back.state.savedGoal == nil)
        #expect(back.state.event?.raceDate == calendar.startOfDay(for: goal.eventDate ?? .distantPast))
        #expect(back.state.cycle.runsPerWeek == 2)
        #expect(back.notes.contains { $0.text == "Two runs fit your week now, so your full plan is back. Your 10K goal is back on." })

        let after = CoachFixtures.follow(back.state, runs: habitWeeks.runs, days: 14, from: 23)
        let next = try week(at: at(30, started), in: after.state)
        #expect(next.sessions.filter { $0.kind.isRun }.count == 2)
    }

    @Test func aSavedGoalThatDoesNotFitYetStaysSaved() throws {
        let intake = tenKIntake(weeks: 12, finishedRecently: false)
        let goal = intake.goal
        let started = CoachFixtures.start(intake)
        let simulation = CoachFixtures.follow(started, days: 3)
        let habit = schedule([.sunday], state: simulation.state, runs: simulation.runs, now: at(3, started))
        #expect(habit.state.savedGoal == goal)

        // Weeks of one run a week later, a first 10K no longer fits before race day.
        let later = CoachFixtures.follow(habit.state, runs: simulation.runs, days: 56, from: 3)
        let back = schedule([.tuesday, .thursday, .sunday], state: later.state, runs: later.runs, now: at(59, started))
        #expect(!back.state.assessment.habitMode)
        #expect(back.state.goal.flavor == .buildDistance)
        #expect(back.state.savedGoal == goal)
        #expect(back.notes.contains { $0.text == "Two runs fit your week now, so your full plan is back. I checked your 10K goal again, and it doesn't fit yet, so it stays saved. I'll check it again each week." })
    }

    @Test func aRaceDateThatPassedInHabitModeIsLetGo() throws {
        let intake = tenKIntake(weeks: 5)
        let started = CoachFixtures.start(intake)
        let simulation = CoachFixtures.follow(started, days: 3)
        let habit = schedule([.sunday], state: simulation.state, runs: simulation.runs, now: at(3, started))
        let later = CoachFixtures.follow(habit.state, runs: simulation.runs, days: 42, from: 3)

        let back = schedule([.tuesday, .thursday, .sunday], state: later.state, runs: later.runs, now: at(45, started))
        #expect(back.state.goal.flavor == .buildDistance)
        #expect(back.state.savedGoal == nil)
        #expect(back.notes.contains { $0.text == "Two runs fit your week now, so your full plan is back. The date of your 10K race has passed, so I'll keep building your distance." })
    }

    @Test func habitIntakeGrowsToTwoRunsWithASecondDay() throws {
        var intake = CoachFixtures.regularIntake()
        intake.runDays = [.sunday]
        let started = CoachFixtures.start(intake)
        #expect(started.assessment.habitMode)
        #expect(started.assessment.runsCap == 1)

        let simulation = CoachFixtures.follow(started, days: 9)
        let back = schedule([.wednesday, .sunday], state: simulation.state, runs: simulation.runs, now: at(9, started))
        #expect(!back.state.assessment.habitMode)
        #expect(back.state.assessment.runsCap == 2)
        #expect(back.notes.contains { $0.text == "Two runs fit your week now, so your full plan is back." })

        let after = CoachFixtures.follow(back.state, runs: simulation.runs, days: 12, from: 9)
        let planned = try week(at: at(16, started), in: after.state)
        #expect(planned.kind != .habit)
        #expect(planned.sessions.filter { $0.kind.isRun }.count == 2)
        #expect(planned.plannedVolume > 0)
    }

    @Test func aRefusedGoalSetAsideAtIntakeComesBack() throws {
        var intake = tenKIntake(weeks: 20)
        let goal = intake.goal
        intake.runDays = [.sunday]
        let check = CoachEngine.checkGoal(goal, intake: intake, level: .steady, now: CoachFixtures.day(0), calendar: calendar)
        #expect(check.refusal == .fewRunDays)
        let habitGoal = try #require(check.alternatives.first?.goal)

        let started = CoachEngine.startPlan(
            intake: intake,
            goal: habitGoal,
            level: .steady,
            savedGoal: check.savedGoal,
            savedGoalEarliest: check.savedGoalEarliest,
            runs: [],
            now: CoachFixtures.day(0),
            calendar: calendar
        ).state
        #expect(started.savedGoal == goal)
        #expect(started.assessment.habitMode)

        let simulation = CoachFixtures.follow(started, days: 9)
        let back = schedule([.tuesday, .thursday, .sunday], state: simulation.state, runs: simulation.runs, now: at(9, started))
        #expect(back.state.goal == goal)
        #expect(back.state.event != nil)
        #expect(back.notes.contains { $0.text.hasSuffix("Your 10K goal is back on.") })
    }

    // MARK: A late weekly check-in

    /// The weekly check-in for a week that has already closed, sent before any run in the week after it.
    func lateCheckIn(for date: Date, state: CoachState, runs: [LoggedRun], now: Date) -> CoachUpdate {
        let week = state.weekIndex(on: date, calendar: calendar)
        let checkIn = WeeklyCheckIn(answeredAt: now, week: .aboutRight, legs: .same, energy: .same, lifeStress: .same, motivation: .same, ill: false)
        return CoachEngine.submitWeeklyCheckIn(checkIn, week: week, state: state, runs: runs, now: now, calendar: calendar)
    }

    @Test func aLateCheckInKeepsTheGoalThatCameBack() throws {
        let intake = tenKIntake(weeks: 20)
        let goal = intake.goal
        let started = CoachFixtures.start(intake)
        let simulation = CoachFixtures.follow(started, days: 9, week: nil)
        let habit = schedule([.sunday], state: simulation.state, runs: simulation.runs, now: at(9, started))
        let habitWeeks = CoachFixtures.follow(habit.state, runs: simulation.runs, days: 12, from: 9, week: nil)

        // A new week opens with nothing run yet, then a second run day brings the 10K back.
        let opened = CoachEngine.refresh(state: habitWeeks.state, runs: habitWeeks.runs, now: at(21, started), calendar: calendar)
        let back = schedule([.tuesday, .thursday, .sunday], state: opened.state, runs: habitWeeks.runs, now: at(21, started).addingTimeInterval(600))
        #expect(back.state.goal == goal)
        let event = try #require(back.state.event)

        // Last week's check-in comes in late and reviews that week again, without undoing the change.
        let late = lateCheckIn(for: at(20, started), state: back.state, runs: habitWeeks.runs, now: at(21, started).addingTimeInterval(1_200))
        #expect(late.state.goal == goal)
        #expect(late.state.event == event)
        #expect(late.state.paces.racePace == back.state.paces.racePace)
        #expect(late.state.cycle.runsPerWeek == back.state.cycle.runsPerWeek)
    }

    @Test func aLateCheckInKeepsHabitMode() throws {
        let intake = tenKIntake(weeks: 20)
        let started = CoachFixtures.start(intake)
        let simulation = CoachFixtures.follow(started, days: 14, week: nil)
        let opened = CoachEngine.refresh(state: simulation.state, runs: simulation.runs, now: at(14, started), calendar: calendar)
        let habit = schedule([.sunday], state: opened.state, runs: simulation.runs, now: at(14, started).addingTimeInterval(600))
        #expect(habit.state.event == nil)

        let late = lateCheckIn(for: at(13, started), state: habit.state, runs: simulation.runs, now: at(14, started).addingTimeInterval(1_200))
        #expect(late.state.assessment.habitMode)
        #expect(late.state.event == nil)
        #expect(late.state.paces.racePace == nil)
        #expect(late.state.cycle.runsPerWeek == 1)
    }

    @Test func aLateCheckInKeepsAMovedRace() throws {
        let started = CoachFixtures.start(tenKIntake(weeks: 6))
        let raceDay = try #require(started.event?.raceDate)
        let days = calendar.dateComponents([.day], from: started.startDate, to: raceDay).day ?? 0
        // Every run but the race, and no weekly check-ins.
        let simulation = CoachFixtures.follow(started, days: days + 1, week: nil, skip: { session, _ in session.kind == .race })
        let opened = CoachEngine.refresh(state: simulation.state, runs: simulation.runs, now: at(days + 1, started), calendar: calendar)
        #expect(opened.questions.contains(.didYouRace))
        let newDate = CoachFixtures.day(14, hour: 9, from: raceDay)
        let (moved, _) = CoachEngine.answer(.didYouRace(.raceMoved(to: newDate)), state: opened.state, runs: simulation.runs, now: at(days + 1, started).addingTimeInterval(600), calendar: calendar)
        let event = try #require(moved.state.event)
        #expect(event.raceDate == calendar.startOfDay(for: newDate))

        let late = lateCheckIn(for: raceDay, state: moved.state, runs: simulation.runs, now: at(days + 1, started).addingTimeInterval(1_200))
        #expect(late.state.event?.raceDate == event.raceDate)
    }

    // MARK: A Severe pause (AD-13c)

    @Test func aSeverePauseKeepsTheGoalSavedUntilReady() throws {
        let intake = tenKIntake(weeks: 20)
        let goal = intake.goal
        let started = CoachFixtures.start(intake)
        let simulation = CoachFixtures.follow(started, days: 9)
        let habit = schedule([.sunday], state: simulation.state, runs: simulation.runs, now: at(9, started))
        let severe = CoachEngine.reportInjury(level: .severe, area: .calfAchilles, origin: .planScreen, runID: nil, state: habit.state, runs: simulation.runs, now: at(10, started), calendar: calendar)
        #expect(severe.state.status.isPaused)

        // A Severe pause holds every goal (RC-1): the second run day ends habit mode, and the 10K waits for Ready.
        let back = schedule([.tuesday, .thursday, .sunday], state: severe.state, runs: simulation.runs, now: at(11, started))
        #expect(back.state.status.isPaused)
        #expect(!back.state.assessment.habitMode)
        #expect(back.state.savedGoal == goal)
        #expect(back.notes.contains { $0.text == "Two runs fit your week now. Your full plan and your 10K goal come back when you're ready." })

        let ready = CoachEngine.resume(state: back.state, runs: simulation.runs, now: at(13, started), calendar: calendar)
        #expect(ready.state.goal == goal)
        #expect(ready.state.savedGoal == nil)
        #expect(ready.state.event != nil)
        #expect(ready.notes.contains { $0.text == "I checked your 10K goal again, and it fits now, so it's back on." })
    }

    @Test func aGoalPickedDuringASeverePauseIsCheckedAtReady() throws {
        let intake = tenKIntake(weeks: 4)
        let started = CoachFixtures.start(intake)
        let simulation = CoachFixtures.follow(started, days: 9)
        let severe = CoachEngine.reportInjury(level: .severe, area: .calfAchilles, origin: .planScreen, runID: nil, state: simulation.state, runs: simulation.runs, now: at(9, started), calendar: calendar)
        let paused = CoachFixtures.follow(severe.state, runs: simulation.runs, days: 28, from: 9)

        // Race day passed during the pause: "Did you race?", then "What next?" with a new race.
        let (stopped, _) = CoachEngine.answer(.didYouRace(.didNotStart), state: paused.state, runs: paused.runs, now: at(37, started), calendar: calendar)
        let next = tenK(inWeeks: 26, from: started)
        let (picked, _) = CoachEngine.answer(.nextGoal(.newGoal(next)), state: stopped.state, runs: paused.runs, now: at(37, started), calendar: calendar)
        #expect(picked.state.savedGoal == next)
        #expect(picked.state.status.isPaused)
        #expect(picked.notes.contains { $0.text == "Let's get you back running first. Your goal is saved, and I'll check it again when you're ready." })

        let ready = CoachEngine.resume(state: picked.state, runs: paused.runs, now: at(38, started), calendar: calendar)
        #expect(ready.state.goal == next)
        #expect(ready.state.savedGoal == nil)
        #expect(ready.notes.contains { $0.text == "I checked your 10K goal again, and it fits now, so it's back on." })
    }

    // MARK: The weekly check

    @Test func aGoalSavedForLaterComesBackOnItsDate() throws {
        let base = keepingDistance(saved: nil)
        let saved = tenK(inWeeks: 20, from: base)
        let state = keepingDistance(saved: saved, earliest: 14)
        let waiting = CoachFixtures.follow(state, days: 14)
        #expect(waiting.state.savedGoal == saved)
        #expect(waiting.state.goal.maintain)

        // The week ending as the earliest date arrives brings it back.
        let closed = CoachEngine.refresh(state: waiting.state, runs: waiting.runs, now: at(14, state), calendar: calendar)
        #expect(closed.state.goal == saved)
        #expect(closed.state.savedGoal == nil)
        #expect(closed.state.event != nil)
        #expect(closed.notes.contains { $0.text == "I checked your 10K goal again, and it fits now, so it's back on." })
    }

    @Test func aSavedRaceWhoseDatePassedIsLetGo() throws {
        let base = keepingDistance(saved: nil)
        var saved = tenK(inWeeks: 1, from: base)
        saved.eventDate = CoachFixtures.day(10, hour: 9, from: base.startDate)
        let state = keepingDistance(saved: saved, earliest: 30)
        let simulation = CoachFixtures.follow(state, days: 14)
        let closed = CoachEngine.refresh(state: simulation.state, runs: simulation.runs, now: at(14, state), calendar: calendar)
        #expect(closed.state.savedGoal == nil)
        #expect(closed.state.goal.maintain)
        #expect(!closed.notes.contains { $0.text.contains("10K") })
    }

    @Test func aRaceInTrainingKeepsTheGoalSaved() throws {
        let intake = tenKIntake(weeks: 20)
        var state = CoachFixtures.start(intake)
        let half = GoalChoice(flavor: .event, distance: .halfMarathon, eventDate: intake.goal.eventDate)
        state.savedGoal = half
        let simulation = CoachFixtures.follow(state, days: 21)
        #expect(simulation.state.goal == intake.goal)
        #expect(simulation.state.savedGoal == half)
    }
}
