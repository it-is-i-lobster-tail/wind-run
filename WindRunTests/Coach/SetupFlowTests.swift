//
//  SetupFlowTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// Coach setup for every coach mode: 5 questions at most, saved answers never asked again, and answers filled in from
/// Apple Health and logged runs (Brendon, 2026-10-22).
@MainActor
struct SetupFlowTests {
    private let calendar = CoachFixtures.calendar

    /// Every step of a regular runner's intake, answered on `date`.
    private func answeredIntake(_ goal: GoalChoice? = nil, on date: Date) -> CoachIntake {
        var intake = CoachFixtures.regularIntake(goal)
        intake.termsAcceptedAt = date
        intake.runs30Minutes = nil
        intake.birthYear = nil
        intake.heightCentimeters = 175
        intake.weightKilograms = 70
        for step in intake.steps {
            intake.markAnswered(step, at: date)
        }
        return intake
    }

    private func run(_ day: Int, km: Double, minutes: Double, hard: Bool = false) -> PastWorkout {
        PastWorkout(start: CoachFixtures.day(day), seconds: minutes * 60, meters: km * 1_000, activity: .run(hard: hard))
    }

    @Test func aFirstSetupAsksFiveQuestions() {
        var intake = CoachIntake(goal: GoalChoice(flavor: .buildDistance, distance: .fiveK), answeredAt: CoachFixtures.day(0))
        intake.termsAcceptedAt = CoachFixtures.day(0)
        let screens = intake.pendingScreens(now: CoachFixtures.day(0), calendar: calendar)
        #expect(screens == [.goal, .runningSoFar, .runningLately, .schedule, .body])
        #expect(screens.count <= SetupScreen.maxQuestions)
        // Age, why you run, the 30-minute question, other training, the level and heart rate aren't asked.
        let steps = Set(intake.steps)
        #expect(steps.isDisjoint(with: [.age, .reasons, .runs30, .otherTraining, .level, .heartRate, .eventDetails]))
    }

    @Test func savedAnswersAreNotAskedAgain() {
        let saved = SavedCoachAnswers(intake: answeredIntake(on: CoachFixtures.day(0)), savedAt: CoachFixtures.day(0))

        let soon = saved.newIntake(flavor: .buildDistance, unit: .kilometers, now: CoachFixtures.day(10), calendar: calendar)
        #expect(soon.pendingScreens(now: CoachFixtures.day(10), calendar: calendar) == [.goal])
        #expect(soon.runDays == [.tuesday, .thursday, .sunday])
        #expect(soon.level == nil)

        // Recent running and pace hold 4 weeks; run days 12 weeks.
        let later = saved.newIntake(flavor: .buildDistance, unit: .kilometers, now: CoachFixtures.day(40), calendar: calendar)
        #expect(later.pendingScreens(now: CoachFixtures.day(40), calendar: calendar) == [.goal, .runningLately])
        let muchLater = saved.newIntake(flavor: .buildDistance, unit: .kilometers, now: CoachFixtures.day(90), calendar: calendar)
        #expect(muchLater.pendingScreens(now: CoachFixtures.day(90), calendar: calendar) == [.goal, .runningLately, .schedule])
    }

    /// "Have you finished this distance?" is kept for each distance. Once "Your running so far" is answered it isn't
    /// asked again: a new distance counts as not finished until the runs show it.
    @Test func finishedIsKeptForEachDistance() {
        var saved = SavedCoachAnswers(intake: answeredIntake(on: CoachFixtures.day(0)), savedAt: CoachFixtures.day(0))
        #expect(saved.finished == [RaceDistance.halfMarathon.rawValue: .yesLongerAgo])

        var fiveK = saved.newIntake(flavor: .speedWork, unit: .kilometers, now: CoachFixtures.day(5), calendar: calendar)
        #expect(fiveK.goal.distance == .fiveK)
        #expect(fiveK.finished == .no)
        #expect(!fiveK.pendingScreens(now: CoachFixtures.day(5), calendar: calendar).contains(.runningSoFar))
        var logged = fiveK
        IntakePrefill.fillFinished(&logged, runs: [run(3, km: 5.1, minutes: 30)], now: CoachFixtures.day(5), calendar: calendar)
        #expect(logged.finished == .yesRecently)

        fiveK.finished = .yesRecently
        fiveK.markAnswered(.finished, at: CoachFixtures.day(5))
        saved.remember(fiveK, at: CoachFixtures.day(5))
        #expect(saved.finished[RaceDistance.halfMarathon.rawValue] == .yesLongerAgo)
        let again = saved.newIntake(flavor: .buildDistance, unit: .kilometers, now: CoachFixtures.day(6), calendar: calendar)
        #expect(again.goal.distance == .fiveK)
        #expect(again.finished == .yesRecently)
        #expect(!again.pendingScreens(now: CoachFixtures.day(6), calendar: calendar).contains(.runningSoFar))
    }

    @Test func thirtyMinutesComesFromTheRunningAnswers() {
        var intake = CoachFixtures.regularIntake()
        intake.runs30Minutes = nil
        // Longest 10 km at 6:00 per km is an hour.
        #expect(intake.canRun30Minutes)
        #expect(!intake.steps.contains(.nonStop))

        intake.lastFourWeeks = RecentRunning(runsPerWeek: 2, weeklyLow: .distance(meters: 4_000), longest: .distance(meters: 2_500))
        intake.easyPace = 420
        // 2.5 km at 7:00 per km is 17.5 minutes.
        #expect(!intake.canRun30Minutes)
        #expect(intake.inferredNonStop == .fifteenToTwentyNine)
        #expect(!intake.steps.contains(.nonStop))
        #expect(intake.steps.contains(.dailyFunction))

        intake.lastFourWeeks = RecentRunning(runsPerWeek: 0, weeklyLow: .distance(meters: 0))
        #expect(intake.inferredNonStop == nil)
        #expect(intake.steps.contains(.nonStop))

        // An answer from an earlier setup still counts.
        intake.runs30Minutes = true
        #expect(intake.canRun30Minutes)
    }

    @Test func runsAndHealthFillTheAnswersIn() {
        let now = CoachFixtures.day(55, hour: 20)
        var intake = CoachIntake(goal: GoalChoice(flavor: .buildDistance, distance: .tenK), answeredAt: now)
        intake.termsAcceptedAt = now
        var workouts: [PastWorkout] = []
        // Tuesday, Thursday and Sunday runs for the 4 weeks from Monday day 28: 5, 6 and 10.5 km at 6:00 per km.
        for week in 0 ..< 4 {
            let monday = 28 + week * 7
            workouts += [
                run(monday + 1, km: 5, minutes: 30),
                run(monday + 3, km: 6, minutes: 36, hard: week == 2),
                run(monday + 6, km: 10.5, minutes: 63),
            ]
        }
        workouts.append(PastWorkout(start: CoachFixtures.day(50), seconds: 3_600, meters: 0, activity: .other(.cycling)))

        IntakePrefill.fill(&intake, body: HealthBody(heightCentimeters: 180, weightKilograms: 72), workouts: workouts, now: now, calendar: calendar)

        let recent = intake.lastFourWeeks
        #expect(recent?.runsPerWeek == 3)
        #expect(recent?.weeklyLow == .distance(meters: 21_500))
        #expect(recent?.longest == .distance(meters: 10_500))
        #expect(intake.holds(.lastFourWeeks, now: now, calendar: calendar))
        #expect(intake.easyPace == 360)
        #expect(intake.finished == .yesRecently)
        #expect(intake.heightCentimeters == 180)
        #expect(intake.otherTraining?.map(\.kind) == [.cycling])
        #expect(intake.runDays == [.tuesday, .thursday, .sunday])
        #expect(intake.canRun30Minutes)

        // Only the history and run days (no safe default) are left to ask.
        #expect(intake.pendingScreens(now: now, calendar: calendar) == [.goal, .runningSoFar, .schedule])
    }

    /// A week with no logged run means the runner may log elsewhere: the answers are shown filled in, not taken.
    @Test func aGapInTheRunsIsShownNotTaken() {
        let now = CoachFixtures.day(60, hour: 20)
        var intake = CoachIntake(goal: GoalChoice(flavor: .buildDistance, distance: .tenK), answeredAt: now)
        let workouts = [run(40, km: 5, minutes: 30), run(55, km: 6, minutes: 36)]
        IntakePrefill.fill(&intake, body: HealthBody(), workouts: workouts, now: now, calendar: calendar)
        #expect(intake.lastFourWeeks?.runsPerWeek == 1)
        #expect(!intake.holds(.lastFourWeeks, now: now, calendar: calendar))
        #expect(intake.pendingScreens(now: now, calendar: calendar).contains(.runningLately))
        // No other training in Health counts as none.
        #expect(intake.otherTraining == [])
    }

    /// With 4 weeks of runs, "Your running lately" comes from them, gaps and all, and isn't asked.
    @Test func fourWeeksOfRunsAnswerRunningLately() {
        let now = CoachFixtures.day(60, hour: 20)
        var intake = CoachIntake(goal: GoalChoice(flavor: .buildDistance, distance: .tenK), answeredAt: now)
        intake.termsAcceptedAt = now
        // 6 km every third day from day 1, with no run from day 44 to day 54.
        let workouts = stride(from: 1, through: 59, by: 3)
            .filter { !(44 ... 54).contains($0) }
            .map { run($0, km: 6, minutes: 36) }
        IntakePrefill.fill(&intake, body: HealthBody(), workouts: workouts, now: now, calendar: calendar)
        #expect(intake.lastFourWeeks?.weeklyLow == .distance(meters: 12_000))
        #expect(intake.holds(.lastFourWeeks, now: now, calendar: calendar))
        #expect(intake.easyPace == 360)
        #expect(intake.breakBeganWeeksAgo == nil)
        #expect(!intake.pendingScreens(now: now, calendar: calendar).contains(.runningLately))
    }

    /// No run in 4 weeks is a break that began with the last run; the weeks before it come from the runs too.
    @Test func aBreakComesFromTheRuns() {
        let now = CoachFixtures.day(70, hour: 20)
        var intake = CoachIntake(goal: GoalChoice(flavor: .buildDistance, distance: .tenK), answeredAt: now)
        intake.termsAcceptedAt = now
        let workouts = stride(from: 1, through: 28, by: 3).map { run($0, km: 6, minutes: 36) }
        IntakePrefill.fill(&intake, body: HealthBody(), workouts: workouts, now: now, calendar: calendar)
        #expect(intake.lastFourWeeks?.runsPerWeek == 0)
        #expect(intake.breakBeganWeeksAgo == 6)
        #expect(intake.beforeBreak?.runsPerWeek == 3)
        #expect(intake.easyPace == 360)
        #expect(intake.canRun30Minutes)
        #expect(intake.holds(.beforeBreak, now: now, calendar: calendar))
        #expect(!intake.pendingScreens(now: now, calendar: calendar).contains(.runningLately))
    }

    /// Back after more than 12 weeks away, a new plan asks the running screens again.
    @Test func aLongBreakAsksTheRunningAgain() throws {
        let saved = SavedCoachAnswers(intake: answeredIntake(on: CoachFixtures.day(0)), savedAt: CoachFixtures.day(0))
        let back = CoachIntakeModel(flavor: .buildDistance, unit: .kilometers, saved: saved, backAfterLongBreak: true, now: CoachFixtures.day(10), calendar: calendar)
        #expect(back.screens.contains(.runningSoFar))
        #expect(back.screens.contains(.runningLately))
        let stayed = CoachIntakeModel(flavor: .buildDistance, unit: .kilometers, saved: saved, backAfterLongBreak: false, now: CoachFixtures.day(10), calendar: calendar)
        #expect(!stayed.screens.contains(.runningSoFar))
        #expect(!stayed.screens.contains(.runningLately))

        let suite = "SetupFlowTests.appOpens"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        AppOpens.record(now: CoachFixtures.day(0), calendar: calendar, defaults: defaults)
        AppOpens.record(now: CoachFixtures.day(84), calendar: calendar, defaults: defaults)
        #expect(!AppOpens.backAfterLongBreak(defaults: defaults))
        AppOpens.record(now: CoachFixtures.day(169), calendar: calendar, defaults: defaults)
        AppOpens.record(now: CoachFixtures.day(170), calendar: calendar, defaults: defaults)
        #expect(AppOpens.backAfterLongBreak(defaults: defaults))
        AppOpens.clearLongBreak(defaults: defaults)
        #expect(!AppOpens.backAfterLongBreak(defaults: defaults))
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func everyLevelStaysOpen() {
        var intake = CoachFixtures.regularIntake()
        intake.history = .underThreeMonths
        let levels = CoachEngine.assess(intake, now: CoachFixtures.day(0), calendar: calendar).levels
        #expect(levels.preset == .gentle)
        #expect(CommitmentLevel.allCases.allSatisfy { levels.allows($0) })
        #expect(levels.lockedMessage == nil)
    }
}
