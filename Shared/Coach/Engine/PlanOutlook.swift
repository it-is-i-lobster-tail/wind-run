//
//  PlanOutlook.swift
//  Wind Run
//

import Foundation

/// The coming weeks as the plan expects them today: the runner does every planned run as planned, rates it
/// easy and calls each week "about right". Real runs and check-ins re-plan each week as it comes, so this is a
/// preview, never a promise.
enum PlanOutlook {
    static func weeks(_ count: Int, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> [PlannedWeek] {
        guard count > 0, state.status.isActive else { return [] }
        let current = state.weekIndex(on: now, calendar: calendar)
        let wanted = (current + 1) ... (current + count)
        let lastStart = state.weekStart(current + count, calendar: calendar)
        var state = state
        var runs = runs
        var captured: [Int: PlannedWeek] = [:]

        func capture() {
            for record in state.weeks where wanted.contains(record.plan.index) && captured[record.plan.index] == nil {
                captured[record.plan.index] = record.plan
            }
        }

        var time = now
        var day = calendar.startOfDay(for: now)
        while day <= lastStart, captured.count < count {
            state = CoachEngine.refresh(state: state, runs: runs, now: time, calendar: calendar).state
            capture()
            let pace = state.paces.easyPace ?? Scheduler.fallbackEasyPace
            for session in CoachEngine.todaysSessions(state, now: time, calendar: calendar) where session.kind.isRun && session.status.isPlanned {
                let run = asPlanned(session, at: time, pace: pace)
                runs.append(run)
                state = CoachEngine.logRun(run, state: state, runs: runs, now: run.end.addingTimeInterval(3_600), calendar: calendar).0.state
                capture()
            }
            let index = state.weekIndex(on: time, calendar: calendar)
            let lastDay = calendar.date(byAdding: .day, value: 6, to: state.weekStart(index, calendar: calendar)) ?? day
            if calendar.isDate(day, inSameDayAs: lastDay), let record = state.weeks.first(where: { $0.plan.index == index }), record.checkIn == nil {
                let evening = day.addingTimeInterval(20 * 3_600)
                let checkIn = WeeklyCheckIn(answeredAt: evening, week: .aboutRight, legs: .same, energy: .same, lifeStress: .same, motivation: .same, ill: false)
                state = CoachEngine.submitWeeklyCheckIn(checkIn, week: index, state: state, runs: runs, now: evening, calendar: calendar).state
                capture()
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            time = day.addingTimeInterval(7 * 3_600)
        }
        return wanted.compactMap { captured[$0] }
    }

    /// A run that does the session exactly, at an easy rating.
    static func asPlanned(_ session: PlannedSession, at time: Date, pace: Double) -> LoggedRun {
        let seconds = session.target.seconds > 0 ? session.target.seconds : session.target.meters / 1_000 * pace
        let meters = session.target.meters > 0 ? session.target.meters : seconds / pace * 1_000
        let checkIn = RunCheckIn(answeredAt: time.addingTimeInterval(seconds + 1_800), rpe: 3, talkTest: true, feel: .ok)
        return LoggedRun(id: session.id, start: time, movingSeconds: seconds, meters: meters, source: .gps, plannedSessionID: session.id, checkIn: checkIn)
    }
}
