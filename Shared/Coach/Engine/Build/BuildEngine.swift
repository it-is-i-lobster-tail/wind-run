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
            injuries: [],
            timeZoneID: calendar.timeZone.identifier
        )
        return refresh(state, runs: runs, now: now, calendar: calendar)
    }

    // MARK: Every day

    /// Brings the plan up to date: closes finished weeks, plans the current one, matches runs to its sessions and
    /// shares what's left of the week over the runs left. Call at app open, after each run and when the day changes.
    static func refresh(_ state: BuildPlanState, runs: [CoachRun], now: Date, calendar: Calendar) -> BuildPlanState {
        guard state.status.isCurrent else { return state }
        var state = state
        state.version = BuildPlanState.currentVersion
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
        // A recovery that's over builds from its reduced base, even one made shorter partway, when its last week
        // was never planned. Set before the week keeps its base, so planning it again starts from there too.
        for injury in state.injuries where injury.isOpen {
            if injury.recoveryIsOver(byWeek: number), let base = injury.returnBase {
                state.base = base
                state.holdNext = false
            }
        }
        let baseBefore = state.base
        let holdBefore = state.holdNext
        var kind: BuildWeekKind
        var target: WeekVolume

        if state.isPaused {
            kind = .paused
            target = .zero
        } else if let index = state.injuries.firstIndex(where: { $0.isOpen && $0.recoveryStartWeek != nil }),
                  let recovery = state.injuries[index].recovery,
                  let recoveryWeek = state.injuries[index].recoveryIndex(ofWeek: number), recoveryWeek < recovery.weeks {
            kind = .recovery
            target = state.injuries[index].baseAtReport.scaled(by: recovery.share(at: recoveryWeek))
            if recoveryWeek == recovery.weeks - 1, let base = state.injuries[index].returnBase {
                // The last recovery week: the plan builds again from it.
                state.base = base
                state.holdNext = false
            }
        } else {
            kind = BuildPlanner.weekKind(number, count: count, schedule: state.settings.easyWeeks)
            switch kind {
            case .goal, .easy:
                target = state.base.scaled(by: BuildLimits.easyWeekShare)
            default:
                let hold = state.holdsNextBuildingWeek
                let timeline = BuildPlanner.timeline(state.settings, planCalendar: state.planCalendar, from: number, base: state.base, hold: hold)
                let week = timeline.weeks.first
                kind = week?.kind ?? .holding
                target = week?.volume ?? state.base
                state.base = target
                state.holdNext = false
            }
        }
        // Recovery weeks that are over close their report.
        for index in state.injuries.indices where state.injuries[index].isOpen && state.injuries[index].recoveryIsOver(byWeek: number) {
            state.injuries[index].closedAt = now
        }

        let start = state.planCalendar.start(of: number, calendar: calendar)
        var week = BuildWeek(number: number, start: start, kind: kind, target: target, baseBefore: baseBefore, holdBefore: holdBefore, sessions: [], done: .zero, closed: false)
        week.sessions = sessions(for: week, state: state, from: max(start, calendar.startOfDay(for: now)), calendar: calendar)
        // The event week is its runs and the event, so it reads done when they are.
        if kind == .goal { week.target = total(week.sessions) }
        state.weeks.append(week)
    }

    /// The week's runs from `from` on.
    static func sessions(for week: BuildWeek, state: BuildPlanState, from: Date, calendar: Calendar) -> [BuildSession] {
        guard week.target.meters > 0 else { return [] }
        let dates = BuildPlanner.runDates(week: week.number, planCalendar: state.planCalendar, runDays: state.settings.runDays, from: from, calendar: calendar)
        guard week.kind == .goal else {
            let shares = BuildPlanner.allocation(state.settings)
            return dates.map { date in
                let day = Weekday(of: date, calendar: calendar)
                let share = shares[day] ?? 0
                let kind: BuildSessionKind = day == state.settings.longDay ? .long : .easy
                var session = BuildSession(date: date, kind: kind, target: week.target.scaled(by: share))
                session.allocationShare = share
                return session
            }
        }
        // The goal week: easy runs before the event, and the event on the day.
        let goal = state.settings.goal
        let goalDay = calendar.startOfDay(for: goal.date)
        var sessions = runsBeforeEvent(easyWeek: week.baseBefore.scaled(by: BuildLimits.easyWeekShare), dates: dates, state: state, goalDay: goalDay, calendar: calendar)
        if goalDay >= calendar.startOfDay(for: from) {
            sessions.append(BuildSession(date: goalDay, kind: .event, target: WeekVolume(meters: goal.meters, climb: goal.climbMeters)))
        }
        return sessions
    }

    /// The goal week's easy runs before the event. The event is the week's long run (the owner, 2026-10-28), so
    /// the runs before it share what's left of the easy week once the event is counted: each at least 3 km, never
    /// longer than the week's other runs would be, and none the day before the event.
    static func runsBeforeEvent(easyWeek: WeekVolume, dates: [Date], state: BuildPlanState, goalDay: Date, calendar: Calendar) -> [BuildSession] {
        let days = state.settings.runDays.count
        guard days > 1, let dayBefore = calendar.date(byAdding: .day, value: -1, to: goalDay) else { return [] }
        let before = Array(dates.filter { $0 < dayBefore }.suffix(days - 1))
        guard !before.isEmpty else { return [] }
        let usual = easyWeek.scaled(by: (1 - min(0.5, 2 / Double(days + 1))) / Double(days - 1))
        let left = max(0, easyWeek.meters - state.settings.goal.meters) / Double(before.count)
        let each = min(usual.meters, max(left, BuildLimits.eventWeekRunMeters))
        // Fewer runs rather than ones under the shortest run.
        let total = each * Double(before.count)
        let kept = BuildPlanner.keptRuns(total, runs: before.count, longIndex: nil)
        guard !kept.isEmpty else { return [] }
        let meters = total / Double(kept.count)
        let climb = usual.meters > 0 ? usual.climb * meters / usual.meters : 0
        return before.indices.filter(kept.contains).map {
            BuildSession(date: before[$0], kind: .easy, target: WeekVolume(meters: meters, climb: climb))
        }
    }

    /// What the sessions add up to.
    static func total(_ sessions: [BuildSession]) -> WeekVolume {
        WeekVolume.sum(sessions) { $0.target }
    }

    /// Matches the week's runs to its sessions, marks past ones missed, and shares what's left of the week over the
    /// runs left. The long run stays the long run, easy runs stay no longer than it, and it stays within half the week.
    static func update(_ state: inout BuildPlanState, at index: Int, runs: [CoachRun], now: Date, calendar: Calendar) {
        var week = state.weeks[index]
        let start = week.start
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return }
        let weekRuns = runs.filter { $0.start >= start && $0.start < end }.sorted { $0.start < $1.start }
        week.done = WeekVolume.sum(weekRuns) { WeekVolume(meters: $0.meters, climb: $0.climb) }
        let today = calendar.startOfDay(for: now)
        matchRuns(weekRuns, into: &week, calendar: calendar)
        reconcile(&week, weekRuns: weekRuns, today: today, calendar: calendar)
        // Apply this to stored weeks too, before sharing mileage. The removed run becomes rest,
        // and its distance is taken out of the week instead of being moved onto an easy day.
        for index in week.sessions.indices {
            let session = week.sessions[index]
            guard session.kind == .long, session.status.isPlanned,
                  !BuildGoal.allowsLongRun(on: session.date, before: state.goalDate, calendar: calendar) else { continue }
            let share = session.allocationShare ?? BuildPlanner.shares(runs: state.settings.runDays.count).first ?? 1
            week.sessions[index].allocationShare = share
            week.sessions[index].taperRest = week.target.scaled(by: share)
            week.sessions[index].kind = .easy
            week.sessions[index].target = .zero
        }
        shareRemainder(&week, state: state, today: today, calendar: calendar)
        updatePractice(&week, state: state, calendar: calendar)
        state.weeks[index] = week
    }

    /// Matching: the session the run was started from, else a planned session that day.
    private static func matchRuns(_ weekRuns: [CoachRun], into week: inout BuildWeek, calendar: Calendar) {
        var used = Set(week.sessions.compactMap(\.status.runID))
        var swappedDays = false
        for run in weekRuns where !used.contains(run.id) {
            let day = calendar.startOfDay(for: run.start)
            let byID = week.sessions.firstIndex { $0.id == run.plannedSessionID && $0.status.isPlanned }
            guard let match = byID ?? week.plannedSessionIndex(on: day, calendar: calendar) else { continue }
            week.sessions[match].status = .done(runID: run.id)
            used.insert(run.id)
            // Another day's run, run today: the two swap days, so today shows as run and the day it came from
            // keeps today's run for later.
            let planned = week.sessions[match].date
            if byID != nil, !calendar.isDate(planned, inSameDayAs: day) {
                if let swapped = week.plannedSessionIndex(on: day, calendar: calendar) {
                    week.sessions[swapped].date = planned
                }
                week.sessions[match].date = day
                swappedDays = true
            }
        }
        if swappedDays { week.sessions.sort { $0.date < $1.date } }
    }

    /// A run deleted after it matched: its session is planned again, or missed once its day is past.
    private static func reconcile(_ week: inout BuildWeek, weekRuns: [CoachRun], today: Date, calendar: Calendar) {
        let runIDs = Set(weekRuns.map(\.id))
        let ranOn = Set(weekRuns.map { calendar.startOfDay(for: $0.start) })
        for session in week.sessions.indices {
            if let runID = week.sessions[session].status.runID, !runIDs.contains(runID) {
                week.sessions[session].status = .planned
            }
            // A run with nothing planned is a rest day, so it's never missed. Nor is a day the runner ran on:
            // what it had goes to the runs left.
            guard week.sessions[session].status.isPlanned, week.sessions[session].target.meters > 0, week.sessions[session].date < today else { continue }
            if ranOn.contains(calendar.startOfDay(for: week.sessions[session].date)) {
                week.sessions[session].target = .zero
            } else {
                week.sessions[session].status = .missed
            }
        }
    }

    /// What's left of the week, over the runs left from today. The goal week keeps its runs and the event as
    /// planned.
    private static func shareRemainder(_ week: inout BuildWeek, state: BuildPlanState, today: Date, calendar: Calendar) {
        var open = week.sessions.indices.filter { week.sessions[$0].status.isPlanned && week.sessions[$0].taperRest == nil && week.sessions[$0].date >= today }
        guard week.kind != .goal, !open.isEmpty else { return }
        let shares = BuildPlanner.allocation(state.settings)
        // Older saved plans did not store the original shares.
        for index in open where week.sessions[index].allocationShare == nil {
            let day = Weekday(of: week.sessions[index].date, calendar: calendar)
            week.sessions[index].allocationShare = shares[day]
        }
        let finishedCuts = WeekVolume.sum(week.sessions.filter { !$0.status.isPlanned || $0.taperRest != nil }) { $0.reduction }
        let remaining = WeekVolume(
            meters: max(0, week.target.meters - week.done.meters - finishedCuts.meters),
            climb: max(0, week.target.climb - week.done.climb - finishedCuts.climb)
        )
        // Higher-frequency plans keep their existing minimum-distance rule.
        if state.settings.runDays.count > 4 {
            let long = open.firstIndex { week.sessions[$0].kind == .long }
            let kept = BuildPlanner.keptRuns(remaining.meters, runs: open.count, longIndex: long)
            for (position, index) in open.enumerated() where !kept.contains(position) {
                week.sessions[index].target = .zero
            }
            open = open.enumerated().compactMap { kept.contains($0.offset) ? $0.element : nil }
        }
        let weight = open.reduce(0.0) { $0 + (week.sessions[$1].allocationShare ?? 0) }
        guard weight > 0 else { return }
        let smallRemainder = remaining.meters < BuildLimits.shortestRunMeters / 2
            && remaining.meters < week.target.meters * weight * BuildLimits.doneShare
        let longShare = shares.values.max() ?? 1
        for index in open {
            let session = week.sessions[index]
            let fraction = (session.allocationShare ?? 0) / weight
            let capShare = session.kind == .long ? max(longShare, BuildLimits.longRunMaxShare) : longShare
            let beforeTaper = BuildGoal.allowsLongRun(on: session.date, before: state.goalDate, calendar: calendar)
            let cap = week.target.scaled(by: beforeTaper ? capShare : min(capShare, session.allocationShare ?? 0))
            let cut = session.lighterReduction ?? .zero
            let volume = remaining.scaled(by: fraction)
            week.sessions[index].target = smallRemainder ? .zero : WeekVolume(
                meters: max(0, min(cap.meters, volume.meters) - cut.meters),
                climb: max(0, min(cap.climb, volume.climb) - cut.climb)
            )
        }
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
            let average = WeekVolume.sum(recent) { $0.done }.divided(by: Double(max(1, recent.count)))
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

    /// Swap roles on a run day or move the workout onto a rest day for this week.
    static func moveLongRun(to day: Weekday, state: BuildPlanState, runs: [CoachRun], now: Date, calendar: Calendar) -> BuildPlanState {
        var state = refresh(state, runs: runs, now: now, calendar: calendar)
        let number = state.planCalendar.number(on: now, calendar: calendar)
        guard state.status.isCurrent, let w = state.weeks.firstIndex(where: { $0.number == number }),
              let oldLong = state.weeks[w].movableLongRun else { return state }
        let week = state.weeks[w]
        let dates = week.longRunDestinations(on: now, event: state.goalDate, calendar: calendar)
        guard let date = dates.first(where: { Weekday(of: $0, calendar: calendar) == day }),
              let old = week.sessions.firstIndex(where: { $0.id == oldLong.id }) else { return state }
        if let new = week.sessions.firstIndex(where: { $0.date == date }) {
            if oldLong.status.isPlanned {
                state.weeks[w].sessions[old].taperRest = nil
                state.weeks[w].sessions[old].kind = .easy
                state.weeks[w].sessions[old].allocationShare = week.sessions[new].allocationShare
            }
            state.weeks[w].sessions[new].kind = .long
            state.weeks[w].sessions[new].allocationShare = oldLong.allocationShare ?? BuildPlanner.shares(runs: state.settings.runDays.count).first
        } else {
            var moved = oldLong
            moved.date = date
            moved.kind = .long
            moved.taperRest = nil
            if oldLong.status.isPlanned {
                state.weeks[w].sessions[old] = moved
            } else {
                moved.id = UUID()
                moved.status = .planned
                moved.lighterReduction = nil
                state.weeks[w].sessions.append(moved)
            }
            state.weeks[w].sessions.sort { $0.date < $1.date }
        }
        return refresh(state, runs: runs, now: now, calendar: calendar)
    }

    /// A lighter session takes a quarter off the current target, once, and credits that reduction to the week.
    static func setLighter(_ lighter: Bool, sessionID: UUID, state: BuildPlanState, runs: [CoachRun], now: Date, calendar: Calendar) -> BuildPlanState {
        var state = refresh(state, runs: runs, now: now, calendar: calendar)
        let number = state.planCalendar.number(on: now, calendar: calendar)
        guard state.status.isCurrent, let w = state.weeks.firstIndex(where: { $0.number == number && !$0.closed }),
              let i = state.weeks[w].sessions.firstIndex(where: { $0.id == sessionID && $0.kind != .event && $0.status.isPlanned }),
              state.weeks[w].sessions[i].date >= calendar.startOfDay(for: now) else { return state }
        let session = state.weeks[w].sessions[i]
        guard lighter != (session.lighterReduction != nil) else { return state }
        state.weeks[w].sessions[i].lighterReduction = lighter ? session.target.scaled(by: 0.25) : nil
        if state.weeks[w].kind == .goal {
            // Taper runs have fixed distances throughout event week.
            state.weeks[w].sessions[i].target = session.target.scaled(by: lighter ? 0.75 : 1 / 0.75)
        }
        return refresh(state, runs: runs, now: now, calendar: calendar)
    }

    /// Edits to the usual schedule also apply this week when the affected runs are still ahead.
    static func changeRunDays(_ days: [Weekday], preferredLongDay: Weekday? = nil, state: BuildPlanState, runs: [CoachRun], now: Date, calendar: Calendar) -> BuildPlanState {
        guard state.status.isCurrent, !days.isEmpty else { return state }
        var state = refresh(state, runs: runs, now: now, calendar: calendar)
        let selected = Array(Set(days)).sorted()
        let daysChanged = state.settings.runDays != selected
        let newLongDay = preferredLongDay ?? state.settings.longDay
        if !daysChanged {
            state = moveLongRun(to: newLongDay, state: state, runs: runs, now: now, calendar: calendar)
        }
        state.settings.runDays = selected
        state.settings.preferredLongDay = selected.contains(newLongDay) ? newLongDay : nil
        if daysChanged {
            replanCurrentWeek(&state, runs: runs, now: now, calendar: calendar, keepTarget: true)
        }
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
        if keepTarget {
            var week = old
            week.sessions = sessions(for: week, state: state, from: calendar.startOfDay(for: now), calendar: calendar)
            state.weeks.append(week)
        } else {
            state.base = old.baseBefore
            state.holdNext = old.holdBefore
            plan(&state, week: number, now: now, calendar: calendar)
        }
        var week = state.weeks[index]
        let finished = old.sessions.filter { !$0.status.isPlanned }
        // A one-week move onto a rest day survives a change in this week's training volume.
        if !keepTarget, let previous = old.sessions.first(where: { $0.kind == .long && $0.isToDo }),
           !state.settings.runDays.contains(Weekday(of: previous.date, calendar: calendar)),
           previous.date >= calendar.startOfDay(for: now), week.kind != .goal {
            if let long = week.sessions.firstIndex(where: { $0.kind == .long }) {
                week.sessions.remove(at: long)
            }
            if week.target.meters > 0 { week.sessions.append(previous) }
        }
        let finishedDays = Set(finished.map(\.date))
        week.sessions.removeAll { finishedDays.contains($0.date) }
        let longDone = finished.contains { $0.kind == .long && $0.status.runID != nil }
        for i in week.sessions.indices {
            if let previous = old.sessions.first(where: { $0.date == week.sessions[i].date && $0.status.isPlanned }) {
                week.sessions[i].id = previous.id
                week.sessions[i].easyInstead = previous.easyInstead
                week.sessions[i].lighterReduction = previous.lighterReduction
                if week.kind == .goal && previous.lighterReduction != nil {
                    week.sessions[i].lighterReduction = week.sessions[i].target.scaled(by: 0.25)
                    week.sessions[i].target = week.sessions[i].target.scaled(by: 0.75)
                }
                if !keepTarget && week.kind != .goal && previous.taperRest == nil {
                    week.sessions[i].kind = previous.kind
                    week.sessions[i].allocationShare = previous.allocationShare
                }
            }
            if longDone && week.sessions[i].kind == .long {
                week.sessions[i].kind = .easy
                week.sessions[i].allocationShare = BuildPlanner.shares(runs: state.settings.runDays.count).dropFirst().max() ?? 1
            }
        }
        week.sessions = (finished + week.sessions).sorted { $0.date < $1.date }
        if week.kind == .goal {
            week.target = WeekVolume.sum(week.sessions) { session in
                let cut = session.lighterReduction ?? .zero
                return WeekVolume(meters: session.target.meters + cut.meters, climb: session.target.climb + cut.climb)
            }
        }
        state.weeks[index] = week
        update(&state, at: index, runs: runs, now: now, calendar: calendar)
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
        currentWeek(state, now: now, calendar: calendar)?.sessions.filter { calendar.isDate($0.date, inSameDayAs: now) && $0.isToDo && ($0.kind != .long || BuildGoal.allowsLongRun(on: now, before: state.goalDate, calendar: calendar)) } ?? []
    }

    /// The next planned run after today.
    static func nextSession(_ state: BuildPlanState, now: Date, calendar: Calendar) -> BuildSession? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return nil }
        return state.weeks.flatMap(\.sessions).filter { $0.date >= tomorrow && $0.isToDo && ($0.kind != .long || BuildGoal.allowsLongRun(on: $0.date, before: state.goalDate, calendar: calendar)) }.min { $0.date < $1.date }
    }

    /// True when a run done today counted for one of today's sessions.
    static func ranToday(_ state: BuildPlanState, now: Date, calendar: Calendar) -> Bool {
        currentWeek(state, now: now, calendar: calendar)?.sessions.contains { calendar.isDate($0.date, inSameDayAs: now) && $0.status.runID != nil } ?? false
    }

    /// The weeks ahead of the current one, as the plan stands. Nothing ahead while the plan is paused, since it
    /// starts again from the recovery weeks; during those, the ones left come first and the plan grows from there.
    static func outlook(_ state: BuildPlanState, now: Date, calendar: Calendar) -> BuildTimeline {
        let current = max(0, state.planCalendar.number(on: now, calendar: calendar))
        let planned = state.week(current) != nil
        let first = planned ? current + 1 : max(1, current)
        if state.isPaused {
            var timeline = BuildPlanner.timeline(state.settings, planCalendar: state.planCalendar, from: first, base: state.base, hold: true)
            timeline.weeks = []
            return timeline
        }
        if let report = state.recovering, let recovery = report.recovery, let start = report.recoveryStartWeek, let base = report.returnBase {
            let after = start + recovery.weeks
            var timeline = BuildPlanner.timeline(state.settings, planCalendar: state.planCalendar, from: max(first, after), base: base, hold: false)
            let left = first < after ? Array(first ..< min(after, state.planCalendar.count + 1)) : []
            timeline.weeks = left.map { TimelineWeek(number: $0, kind: .recovery, volume: report.baseAtReport.scaled(by: recovery.share(at: $0 - start))) } + timeline.weeks
            return timeline
        }
        return BuildPlanner.timeline(
            state.settings,
            planCalendar: state.planCalendar,
            from: first,
            base: state.base,
            hold: state.holdsNextBuildingWeek
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

extension BuildEngine {
    static func updatePractice(_ week: inout BuildWeek, state: BuildPlanState, calendar: Calendar) {
        let settings = state.settings
        let count = settings.runDays.count
        let paceShare = [2: 0.4, 3: 0.3, 4: 0.2][count]
        var longDates = week.sessions.filter { $0.kind == .long }.map(\.date)
        if let previous = state.week(week.number - 1) {
            longDates += previous.sessions.filter { $0.kind == .long && $0.status.runID != nil }.map(\.date)
        }
        if let nextStart = calendar.date(byAdding: .day, value: 7, to: week.start),
           Weekday(of: nextStart, calendar: calendar) == settings.longDay,
           BuildGoal.allowsLongRun(on: nextStart, before: state.goalDate, calendar: calendar) {
            longDates.append(nextStart)
        }
        func nextToLongRun(_ date: Date) -> Bool {
            longDates.contains { abs(calendar.dateComponents([.day], from: date, to: $0).day ?? 0) <= 1 }
        }
        let paceCandidates = week.sessions.filter {
            $0.kind == .easy && $0.allocationShare == paceShare && !nextToLongRun($0.date)
        }
        // Keep the two faster sessions apart when either 20% run can carry the same pace work.
        let speedDate = settings.speedWork == true ? week.sessions.first { $0.allocationShare == 0.1 }?.date : nil
        let spaced = paceCandidates.first { candidate in
            guard let speedDate else { return true }
            return abs(calendar.dateComponents([.day], from: speedDate, to: candidate.date).day ?? 0) > 1
        }
        let finishedPace = week.sessions.first { !$0.status.isPlanned && ($0.practice == .pace || $0.practice == .shortPace) }
        let paceSlot = (finishedPace ?? spaced ?? paceCandidates.first)?.id
        for i in week.sessions.indices where week.sessions[i].status.isPlanned {
            let session = week.sessions[i]
            var practice: BuildPractice?
            if week.kind == .building, state.openInjuries.isEmpty, session.kind == .easy, session.isToDo,
               BuildGoal.allowsLongRun(on: session.date, before: state.goalDate, calendar: calendar),
               !nextToLongRun(session.date) {
                if settings.targetPace != nil, session.id == paceSlot, paceShare != nil {
                    practice = count == 2 ? .shortPace : .pace
                } else if count == 4, settings.speedWork == true, session.allocationShare == 0.1 {
                    practice = .speed
                }
            }
            week.sessions[i].practice = practice
            week.sessions[i].practicePace = practice == .pace || practice == .shortPace ? settings.targetPace : nil
        }
    }

    static func useEasyRun(_ easy: Bool, sessionID: UUID, state: BuildPlanState, runs: [CoachRun], now: Date, calendar: Calendar) -> BuildPlanState {
        var state = refresh(state, runs: runs, now: now, calendar: calendar)
        let number = state.planCalendar.number(on: now, calendar: calendar)
        guard state.status.isCurrent, let w = state.weeks.firstIndex(where: { $0.number == number && !$0.closed }),
              let i = state.weeks[w].sessions.firstIndex(where: { $0.id == sessionID && $0.isToDo && $0.practice != nil })
        else { return state }
        state.weeks[w].sessions[i].easyInstead = easy ? true : nil
        return state
    }
}
