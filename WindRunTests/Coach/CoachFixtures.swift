//
//  CoachFixtures.swift
//  WindRunTests
//

import Foundation
@testable import WindRun

/// Shared inputs for the coach tests: a fixed calendar and start date, sample intakes, and a runner who
/// does exactly what the plan says.
@MainActor
enum CoachFixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Monday 5 January 2026, 00:00 UTC.
    static let monday = Date(timeIntervalSince1970: 1_767_571_200)

    static func day(_ offset: Int, hour: Int = 7, from start: Date? = nil) -> Date {
        (start ?? monday).addingTimeInterval(TimeInterval(offset * 86_400 + hour * 3_600))
    }

    /// A Regular runner: 16-18 km a week over 3 runs, longest 10 km, easy pace 6:00/km, no other training.
    /// TI-5 gives V0 16 km and a planning P-L30 of min(0.9 × 10, 0.5 × 16) = 8 km.
    static func regularIntake(_ goal: GoalChoice? = nil, level: CommitmentLevel = .steady) -> CoachIntake {
        var intake = CoachIntake(goal: goal ?? GoalChoice(flavor: .buildDistance, distance: .halfMarathon), answeredAt: monday)
        intake.finished = .yesLongerAgo
        intake.birthYear = 1990
        intake.runs30Minutes = true
        intake.history = .overTwoYears
        intake.lastFourWeeks = RecentRunning(
            runsPerWeek: 3,
            weeklyLow: .distance(meters: 16_000),
            weeklyHigh: .distance(meters: 18_000),
            longest: .distance(meters: 10_000)
        )
        intake.easyPace = 360
        intake.otherTraining = []
        intake.physicalWork = false
        intake.runDays = [.tuesday, .thursday, .sunday]
        intake.longRunDay = .sunday
        intake.level = level
        return intake
    }

    /// A run that does a planned session exactly, rated as asked.
    static func run(for session: PlannedSession, on date: Date, pace: Double, rpe: Int? = 3) -> LoggedRun {
        let seconds = session.target.seconds > 0 ? session.target.seconds : session.target.meters / 1_000 * pace
        let meters = session.target.meters > 0 ? session.target.meters : seconds / pace * 1_000
        var checkIn: RunCheckIn?
        if let rpe {
            checkIn = RunCheckIn(answeredAt: date.addingTimeInterval(seconds + 1_800), rpe: rpe, talkTest: rpe <= 3, feel: .ok)
        }
        return LoggedRun(start: date, movingSeconds: seconds, meters: meters, source: .gps, plannedSessionID: session.id, checkIn: checkIn)
    }

    struct Simulation {
        var state: CoachState
        var runs: [LoggedRun]
    }

    /// Runs every planned session for `days` days from the plan's first day, answering each weekly check-in.
    static func follow(
        _ state: CoachState,
        runs: [LoggedRun] = [],
        days: Int,
        from first: Int = 0,
        rpe: Int? = 3,
        week feel: WeekFeel? = .aboutRight,
        skip: (PlannedSession, Int) -> Bool = { _, _ in false }
    ) -> Simulation {
        var state = state
        var runs = runs
        for offset in first ..< first + days {
            let morning = day(offset, from: state.startDate)
            state = CoachEngine.refresh(state: state, runs: runs, now: morning, calendar: calendar).state
            let pace = state.paces.easyPace ?? 378
            for session in CoachEngine.todaysSessions(state, now: morning, calendar: calendar) where session.kind.isRun && session.status.isPlanned {
                if skip(session, offset) { continue }
                let run = run(for: session, on: morning, pace: pace, rpe: rpe)
                runs.append(run)
                let later = morning.addingTimeInterval(run.movingSeconds + 3_600)
                state = CoachEngine.logRun(run, state: state, runs: runs, now: later, calendar: calendar).0.state
            }
            let weekIndex = state.weekIndex(on: morning, calendar: calendar)
            let weekDay = (calendar.dateComponents([.day], from: state.startDate, to: morning).day ?? 0) % 7
            if weekDay == 6, let feel {
                let evening = day(offset, hour: 20, from: state.startDate)
                let checkIn = WeeklyCheckIn(answeredAt: evening, week: feel, legs: .same, energy: .same, lifeStress: .same, motivation: .same, ill: false)
                state = CoachEngine.submitWeeklyCheckIn(checkIn, week: weekIndex, state: state, runs: runs, now: evening, calendar: calendar).state
            }
        }
        return Simulation(state: state, runs: runs)
    }

    /// Starts a plan on the fixture Monday.
    static func start(_ intake: CoachIntake, runs: [LoggedRun] = [], insisted: Bool = false) -> CoachState {
        CoachEngine.startPlan(
            intake: intake,
            goal: intake.goal,
            level: intake.level ?? .steady,
            insisted: insisted,
            runs: runs,
            now: day(0),
            calendar: calendar
        ).state
    }
}
