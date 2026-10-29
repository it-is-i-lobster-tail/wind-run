//
//  BuildEngine.swift
//  Wind Run
//

import Foundation

/// The coach: starts a Build Distance plan, keeps it up to date with the runs, and takes the runner's changes.
/// Every call takes the stored state and the runs and gives back the new state.
enum BuildEngine {
    // MARK: Starting

    static func start(_ settings: BuildSettings, runs: [CoachRun], now: Date, calendar: Calendar) -> BuildPlanState {
        var settings = settings
        settings.goal.date = calendar.startOfDay(for: settings.goal.date)
        let state = BuildPlanState(
            version: BuildPlanState.currentVersion,
            settings: settings,
            createdAt: now,
            planCalendar: PlanCalendar.make(goalDate: settings.goal.date, now: now, calendar: calendar),
            status: .active,
            base: BuildPlanner.startingBase(settings),
            holdNext: false,
            lowWeeks: 0,
            weeks: [],
            injuries: []
        )
        return refresh(state, runs: runs, now: now, calendar: calendar)
    }

    // MARK: Every day

    /// Brings the plan up to date: closes finished weeks, plans the current one, matches runs to its sessions and
    /// shares what's left of the week over the runs left. Call at app open, after each run and when the day changes.
    static func refresh(_ state: BuildPlanState, runs: [CoachRun], now: Date, calendar: Calendar) -> BuildPlanState {
        guard state.status.isCurrent else { return state }
        var state = state
        let today = state.planCalendar.number(on: now, calendar: calendar)
        if today > state.planCalendar.count {
            // The goal date has passed: close the goal week and finish.
            for index in state.weeks.indices where !state.weeks[index].closed {
                close(&state, at: index, runs: runs, now: now, calendar: calendar)
            }
            state.status = .complete(on: now)
            return state
        }
        guard today >= 1 else { return state }

        for index in state.weeks.indices where !state.weeks[index].closed && state.weeks[index].number < today {
            close(&state, at: index, runs: runs, now: now, calendar: calendar)
        }
        var next = (state.weeks.last?.number ?? 0) + 1
        while next <= today {
            plan(&state, week: next, now: now, calendar: calendar)
            if next < today, let index = state.weeks.indices.last {
                close(&state, at: index, runs: runs, now: now, calendar: calendar)
            }
            next += 1
        }
        if let index = state.weeks.firstIndex(where: { $0.number == today }) {
            update(&state, at: index, runs: runs, now: now, calendar: calendar)
        }
        return state
    }

    /// Plans week `number` from the base, and sets the base for the week after.
    static func plan(_ state: inout BuildPlanState, week number: Int, now: Date, calendar: Calendar) {
        let count = state.planCalendar.count
        let baseBefore = state.base
        let holdBefore = state.holdNext
        var kind: BuildWeekKind
        var target: WeekVolume

        if state.isPaused {
            kind = .paused
            target = .zero
        } else if let index = state.injuries.firstIndex(where: { $0.isOpen && $0.recoveryStartWeek != nil }),
                  let recovery = state.injuries[index].recovery, let first = state.injuries[index].recoveryStartWeek,
                  number - first < recovery.weeks {
            kind = .recovery
            target = state.injuries[index].baseAtReport.scaled(by: recovery.share(at: number - first))
            if number - first == recovery.weeks - 1 {
                // The last recovery week: the plan builds again from it.
                state.base = state.injuries[index].baseAtReport.scaled(by: recovery.reducedShare)
                state.holdNext = false
            }
        } else {
            kind = BuildPlanner.weekKind(number, count: count, schedule: state.settings.easyWeeks)
            switch kind {
            case .goal, .easy:
                target = state.base.scaled(by: BuildLimits.easyWeekShare)
            default:
                let hold = state.holdNext || state.openInjuries.contains { $0.level == .mild }
                let timeline = BuildPlanner.timeline(state.settings, planCalendar: state.planCalendar, from: number, base: state.base, hold: hold)
                let week = timeline.weeks.first
                kind = week?.kind ?? .holding
                target = week?.volume ?? state.base
                state.base = target
                state.holdNext = false
            }
        }
        // Recovery weeks that are over close their report.
        for index in state.injuries.indices where state.injuries[index].isOpen {
            if let first = state.injuries[index].recoveryStartWeek, let recovery = state.injuries[index].recovery, number - first >= recovery.weeks {
                state.injuries[index].closedAt = now
            }
        }

        let start = state.planCalendar.start(of: number, calendar: calendar)
        var week = BuildWeek(number: number, start: start, kind: kind, target: target, baseBefore: baseBefore, holdBefore: holdBefore, sessions: [], done: .zero, closed: false)
        week.sessions = sessions(for: week, state: state, from: max(start, calendar.startOfDay(for: now)), calendar: calendar)
        state.weeks.append(week)
    }

    /// The week's runs from `from` on.
    static func sessions(for week: BuildWeek, state: BuildPlanState, from: Date, calendar: Calendar) -> [BuildSession] {
        guard week.target.meters > 0 else { return [] }
        let goal = state.settings.goal
        var dates = BuildPlanner.runDates(week: week.number, planCalendar: state.planCalendar, runDays: state.settings.runDays, from: from, calendar: calendar)
        guard week.kind == .goal else {
            return BuildPlanner.split(week.target, over: dates, longRun: true, calendar: calendar).map {
                BuildSession(date: $0.date, kind: $0.kind, target: $0.volume)
            }
        }
        // The goal week: easy runs before the event, sized as the week's other runs, and the event on the day.
        let goalDay = calendar.startOfDay(for: goal.date)
        dates = Array(dates.filter { $0 < goalDay }.suffix(max(0, state.settings.runDays.count - 1)))
        let days = max(1, state.settings.runDays.count)
        let others = days > 1 ? week.target.scaled(by: (1 - BuildPlanner.longShare(runs: days)) / Double(days - 1)) : .zero
        var sessions = dates.map { BuildSession(date: $0, kind: .easy, target: others) }
        if goalDay >= calendar.startOfDay(for: from) {
            sessions.append(BuildSession(date: goalDay, kind: .event, target: WeekVolume(meters: goal.meters, climb: goal.climbMeters)))
        }
        return sessions
    }

    /// Matches the week's runs to its sessions, marks past ones missed, and shares what's left of the week over the
    /// runs left. The long run stays the long run, easy runs stay no longer than it, and it stays within half the week.
    static func update(_ state: inout BuildPlanState, at index: Int, runs: [CoachRun], now: Date, calendar: Calendar) {
        var week = state.weeks[index]
        let start = week.start
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return }
        let weekRuns = runs.filter { $0.start >= start && $0.start < end }.sorted { $0.start < $1.start }
        week.done = WeekVolume(meters: weekRuns.reduce(0) { $0 + $1.meters }, climb: weekRuns.reduce(0) { $0 + $1.climb })

        // Matching: the session the run was started from, else a planned session that day.
        var used = Set(week.sessions.compactMap(\.status.runID))
        for run in weekRuns where !used.contains(run.id) {
            let day = calendar.startOfDay(for: run.start)
            let match = week.sessions.firstIndex { $0.id == run.plannedSessionID && $0.status.isPlanned }
                ?? week.sessions.firstIndex { $0.date == day && $0.status.isPlanned }
            if let match {
                week.sessions[match].status = .done(runID: run.id)
                used.insert(run.id)
            }
        }
        // A run deleted after it matched: its session is planned again, or missed once its day is past.
        let runIDs = Set(weekRuns.map(\.id))
        let today = calendar.startOfDay(for: now)
        for session in week.sessions.indices {
            if let runID = week.sessions[session].status.runID, !runIDs.contains(runID) {
                week.sessions[session].status = .planned
            }
            // A run with nothing planned is a rest day, so it's never missed.
            if week.sessions[session].status.isPlanned, week.sessions[session].target.meters > 0, week.sessions[session].date < today {
                week.sessions[session].status = .missed
            }
        }

        // What's left of the week, over the runs left. The goal week keeps its runs and the event as planned.
        let open = week.sessions.indices.filter { week.sessions[$0].status.isPlanned }
        if week.kind != .goal, !open.isEmpty {
            let left = WeekVolume(meters: max(0, week.target.meters - week.done.meters), climb: max(0, week.target.climb - week.done.climb))
            let hasLong = open.contains { week.sessions[$0].kind == .long }
            let split = BuildPlanner.split(left, over: open.map { week.sessions[$0].date }, longRun: hasLong, calendar: calendar)
            // Caps: the long run within half the week, an easy run no longer than the week's long run as planned.
            let allDays = BuildPlanner.runDates(week: week.number, planCalendar: state.planCalendar, runDays: state.settings.runDays, from: week.start, calendar: calendar)
            let longCap = week.target.scaled(by: 0.5)
            let easyCap = week.target.scaled(by: BuildPlanner.longShare(runs: max(1, allDays.count)))
            for (position, sessionIndex) in open.enumerated() {
                let cap = split[position].kind == .long ? longCap : easyCap
                let volume = split[position].volume
                week.sessions[sessionIndex].kind = split[position].kind
                week.sessions[sessionIndex].target = WeekVolume(meters: min(volume.meters, cap.meters), climb: min(volume.climb, cap.climb))
            }
        }
        state.weeks[index] = week
    }

    /// Closes a finished week. A building week under 90% done is repeated; two weeks in a row under half done start
    /// the plan again from what was run lately.
    static func close(_ state: inout BuildPlanState, at index: Int, runs: [CoachRun], now: Date, calendar: Calendar) {
        // At the week's end, so every run left on it counts as missed.
        update(&state, at: index, runs: runs, now: max(now, end(of: state.weeks[index], calendar: calendar)), calendar: calendar)
        state.weeks[index].closed = true
        let week = state.weeks[index]
        // A first week that started before the plan did isn't held against the runner.
        if week.start < calendar.startOfDay(for: state.createdAt) { return }
        guard week.kind.isBuilding else {
            if week.kind == .paused || week.kind == .recovery { state.lowWeeks = 0 }
            return
        }
        if week.doneShare < BuildLimits.doneShare { state.holdNext = true }
        state.lowWeeks = week.doneShare < BuildLimits.lowShare ? state.lowWeeks + 1 : 0
        if state.lowWeeks >= 2 {
            let recent = state.weeks.filter(\.closed).suffix(4)
            let average = WeekVolume(
                meters: recent.reduce(0) { $0 + $1.done.meters } / Double(max(1, recent.count)),
                climb: recent.reduce(0) { $0 + $1.done.climb } / Double(max(1, recent.count))
            )
            let floor = BuildPlanner.startingFloor(peakClimb: state.settings.goal.peakWeekClimbMeters)
            state.base = WeekVolume(
                meters: min(state.base.meters, max(average.meters, floor.meters)),
                climb: min(state.base.climb, max(average.climb, floor.climb))
            )
            state.holdNext = false
            state.lowWeeks = 0
        }
    }

    /// Just after the week's last day, for closing it.
    static func end(of week: BuildWeek, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 7, to: week.start) ?? week.start
    }

    // MARK: Changes the runner makes

    /// New run days: the rest of this week moves to them (finished runs stay), and later weeks use them.
    static func changeRunDays(_ days: [Weekday], state: BuildPlanState, runs: [CoachRun], now: Date, calendar: Calendar) -> BuildPlanState {
        var state = state
        state.settings.runDays = Array(Set(days)).sorted()
        replanCurrentWeek(&state, runs: runs, now: now, calendar: calendar, keepTarget: true)
        return refresh(state, runs: runs, now: now, calendar: calendar)
    }

    /// A new easy-week schedule. The current week is planned again if it changes kind.
    static func changeEasyWeeks(_ schedule: EasyWeekSchedule, state: BuildPlanState, runs: [CoachRun], now: Date, calendar: Calendar) -> BuildPlanState {
        var state = state
        state.settings.easyWeeks = schedule
        replanCurrentWeek(&state, runs: runs, now: now, calendar: calendar, keepTarget: false)
        return refresh(state, runs: runs, now: now, calendar: calendar)
    }

    /// Makes week `number` an easy week, or a building week again. Past weeks stay as they were.
    static func toggleEasyWeek(_ number: Int, state: BuildPlanState, runs: [CoachRun], now: Date, calendar: Calendar) -> BuildPlanState {
        let current = state.planCalendar.number(on: now, calendar: calendar)
        guard number >= current, number < state.planCalendar.count else { return state }
        return changeEasyWeeks(state.settings.easyWeeks.toggling(number, through: state.planCalendar.count), state: state, runs: runs, now: now, calendar: calendar)
    }

    /// A new peak week. Later weeks grow toward it.
    static func changePeak(_ peak: WeekVolume, state: BuildPlanState, runs: [CoachRun], now: Date, calendar: Calendar) -> BuildPlanState {
        var state = state
        state.settings.goal.peakWeekMeters = max(0, peak.meters)
        state.settings.goal.peakWeekClimbMeters = max(0, peak.climb)
        return refresh(state, runs: runs, now: now, calendar: calendar)
    }

    static func stop(_ state: BuildPlanState, now: Date) -> BuildPlanState {
        var state = state
        state.status = .stopped(on: now)
        return state
    }

    /// Plans the current week again from the base it started with. Finished runs stay as they are.
    static func replanCurrentWeek(_ state: inout BuildPlanState, runs: [CoachRun], now: Date, calendar: Calendar, keepTarget: Bool) {
        let number = state.planCalendar.number(on: now, calendar: calendar)
        guard let index = state.weeks.firstIndex(where: { $0.number == number && !$0.closed }), index == state.weeks.count - 1 else { return }
        let old = state.weeks.remove(at: index)
        let finished = old.sessions.filter { !$0.status.isPlanned }
        if keepTarget {
            var week = old
            let today = calendar.startOfDay(for: now)
            let finishedDays = Set(finished.map(\.date))
            let longDone = finished.contains { $0.kind == .long && $0.status.runID != nil }
            var fresh = sessions(for: week, state: state, from: today, calendar: calendar).filter { !finishedDays.contains($0.date) }
            if longDone { for session in fresh.indices where fresh[session].kind == .long { fresh[session].kind = .easy } }
            week.sessions = (finished + fresh).sorted { $0.date < $1.date }
            state.weeks.append(week)
        } else {
            state.base = old.baseBefore
            state.holdNext = old.holdBefore
            plan(&state, week: number, now: now, calendar: calendar)
            let last = state.weeks.count - 1
            let finishedDays = Set(finished.map(\.date))
            state.weeks[last].sessions = (finished + state.weeks[last].sessions.filter { !finishedDays.contains($0.date) }).sorted { $0.date < $1.date }
        }
        update(&state, at: state.weeks.count - 1, runs: runs, now: now, calendar: calendar)
    }

    // MARK: Injuries (AD-13, AD-14)

    /// Mild holds the plan's mileage until it's better; Intense pauses until the runner is cleared; Severe pauses until
    /// the runner is ready. The current week is planned again.
    static func reportInjury(level: InjuryLevel, area: InjuryArea?, runID: UUID?, state: BuildPlanState, runs: [CoachRun], now: Date, calendar: Calendar) -> BuildPlanState {
        var state = state
        let report = BuildInjury(id: UUID(), reportedAt: now, level: level, area: area, runID: runID, baseAtReport: state.base)
        state.injuries.append(report)
        if level != .mild { replanCurrentWeek(&state, runs: runs, now: now, calendar: calendar, keepTarget: false) }
        return refresh(state, runs: runs, now: now, calendar: calendar)
    }

    /// A report moved to another level. Back to its pause, or its hold, with nothing set up yet.
    static func changeInjuryLevel(_ level: InjuryLevel, reportID: UUID, state: BuildPlanState, runs: [CoachRun], now: Date, calendar: Calendar) -> BuildPlanState {
        var state = state
        guard let index = state.injuries.firstIndex(where: { $0.id == reportID && $0.isOpen }) else { return state }
        state.injuries[index].level = level
        state.injuries[index].clearance = nil
        state.injuries[index].recovery = nil
        state.injuries[index].recoveryStartWeek = nil
        replanCurrentWeek(&state, runs: runs, now: now, calendar: calendar, keepTarget: false)
        return refresh(state, runs: runs, now: now, calendar: calendar)
    }

    /// "Are you medically cleared to keep training?" Yes starts the recovery weeks this week.
    static func answerClearance(_ answer: ClearanceAnswer, reportID: UUID, state: BuildPlanState, runs: [CoachRun], now: Date, calendar: Calendar) -> BuildPlanState {
        var state = state
        guard let index = state.injuries.firstIndex(where: { $0.id == reportID && $0.isOpen }) else { return state }
        state.injuries[index].clearance = answer
        if answer == .yes {
            return startRecovery(.intense, reportID: reportID, state: state, runs: runs, now: now, calendar: calendar)
        }
        return state
    }

    /// Severe: "I'm ready to run again", with the return weeks.
    static func ready(reportID: UUID, state: BuildPlanState, runs: [CoachRun], now: Date, calendar: Calendar) -> BuildPlanState {
        startRecovery(.severe, reportID: reportID, state: state, runs: runs, now: now, calendar: calendar)
    }

    /// Starts, or changes, the recovery weeks of a report.
    static func startRecovery(_ settings: RecoverySettings, reportID: UUID, state: BuildPlanState, runs: [CoachRun], now: Date, calendar: Calendar) -> BuildPlanState {
        var state = state
        guard let index = state.injuries.firstIndex(where: { $0.id == reportID && $0.isOpen }) else { return state }
        state.injuries[index].recovery = settings
        if state.injuries[index].recoveryStartWeek == nil {
            state.injuries[index].recoveryStartWeek = max(1, state.planCalendar.number(on: now, calendar: calendar))
        }
        replanCurrentWeek(&state, runs: runs, now: now, calendar: calendar, keepTarget: false)
        return refresh(state, runs: runs, now: now, calendar: calendar)
    }

    /// Mild: "It's better." The plan builds again from next week.
    static func injuryBetter(reportID: UUID, state: BuildPlanState, now: Date) -> BuildPlanState {
        var state = state
        guard let index = state.injuries.firstIndex(where: { $0.id == reportID && $0.isOpen }) else { return state }
        state.injuries[index].closedAt = now
        return state
    }

    // MARK: Reading

    /// The plan's current week, if it has started.
    static func currentWeek(_ state: BuildPlanState, now: Date, calendar: Calendar) -> BuildWeek? {
        state.week(state.planCalendar.number(on: now, calendar: calendar))
    }

    /// Runs planned for today that aren't done yet.
    static func todaysSessions(_ state: BuildPlanState, now: Date, calendar: Calendar) -> [BuildSession] {
        let today = calendar.startOfDay(for: now)
        return currentWeek(state, now: now, calendar: calendar)?.sessions.filter { $0.date == today && $0.isToDo } ?? []
    }

    /// The next planned run after today.
    static func nextSession(_ state: BuildPlanState, now: Date, calendar: Calendar) -> BuildSession? {
        let today = calendar.startOfDay(for: now)
        return state.weeks.flatMap(\.sessions).filter { $0.date > today && $0.isToDo }.min { $0.date < $1.date }
    }

    /// The weeks ahead of the current one, as the plan stands.
    static func outlook(_ state: BuildPlanState, now: Date, calendar: Calendar) -> BuildTimeline {
        let current = max(0, state.planCalendar.number(on: now, calendar: calendar))
        let planned = state.week(current) != nil
        return BuildPlanner.timeline(
            state.settings,
            planCalendar: state.planCalendar,
            from: planned ? current + 1 : max(1, current),
            base: state.base,
            hold: state.holdNext || state.openInjuries.contains { $0.level == .mild }
        )
    }

    /// The session with this id and its week.
    static func locate(_ sessionID: UUID, in state: BuildPlanState) -> (week: BuildWeek, session: BuildSession)? {
        for week in state.weeks {
            if let session = week.sessions.first(where: { $0.id == sessionID }) { return (week, session) }
        }
        return nil
    }
}
