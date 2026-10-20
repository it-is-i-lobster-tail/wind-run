//
//  LadderCoach.swift
//  Wind Run
//

import Foundation

/// The walk stage, the short run-walk and the run-walk ladder to 30 minutes (TI-2, TI-6, BD-2, AD-18).
enum LadderCoach {
    // MARK: Numbers

    /// TI-2c: NHS week 1 holds 8 minutes of running a session, the least a run-walk session holds when HL-2
    /// trims repeats (BD-2a).
    static let smallestSessionRunning: Double = 8 * 60
    /// TI-2a: walks grow by at most 5 minutes a week, until 30 brisk minutes on 3 days (TI-6).
    static let walkStepMinutes: Double = 5
    static let walkGoalMinutes: Double = 30
    static let walkGoalDays = 3
    /// TI-2a: a walk counts at its length when it lasts 80% of it.
    static let walkDoneShare = 0.8
    /// BD-2b: rated RPE ≤5; AD-18: a session at RPE ≥6 is a hard one.
    static let comfortableRPE = 5
    static let hardRPE = 6
    /// BD-2e: BMI ≥30 runs ≤3 km in week 1 (3 × 1 km), adds ≤10% a week by time in weeks 2-4, then ≤30% a week.
    static let bmiThreshold: Double = 30
    static let bmiFirstWeekMeters: Double = 3_000
    static let bmiSessionMeters: Double = 1_000
    static let bmiEarlyGrowth = 1.10
    static let bmiLaterGrowth = 1.30
    static let bmiTimeWeeks = 4
    /// AD-18's gap rows: up to 7 days repeats the step, 8-14 days goes back one, 15-28 days two, longer asks where.
    static let gapDays = 8
    static let shortGapDays = 14
    static let longGapDays = 28
    /// AD-18: two idle weeks bring the one-tap easier restart.
    static let idleDays = 14
    /// AD-18: a non-stop segment counts as longer than the step's when it is this much longer (GPS margin).
    static let longerSegmentMargin: Double = 30
    /// TI-6: 30 minutes non-stop, less the same margin.
    static let finishSeconds: Double = 30 * 60 - 30
    /// The last segment of a session is shortened in steps of 30 seconds (BD-2a).
    static let pieceStep: Double = 30
    /// HL-11: strides once a week from 20 minutes non-stop.
    static let stridesSegment: Double = 20 * 60

    // MARK: Types

    /// AD-18's gap: the last run before it, its length in days and its row, and where the runner restarts.
    struct Gap: Hashable {
        var lastRunDay: Date
        var days: Int
        /// 1: 8-14 days, 2: 15-28 days, 3: longer.
        var tier: Int
        /// Where the runner was before the gap, and where the gap row restarts them.
        var base: LadderPosition
        var position: LadderPosition
    }

    /// Where a week is planned, and what moved it there.
    struct Restart: Hashable {
        var position: LadderPosition
        /// Nil when the week stays at the ladder's position.
        var reason: LadderMoveReason?
        var gap: Gap?
        /// Injury reports whose restart is in force.
        var injuries: [UUID]
    }

    /// What limits the week's running.
    enum RunningLimit: Hashable {
        /// HL-2 by running minutes (BD-2a).
        case weekly
        /// BD-2e's first weeks, counted from the first week with running.
        case firstWeeks(week: Int)
    }

    /// A ladder week before it is laid out on days.
    struct Week: Hashable {
        var restart: Restart
        /// Sessions wanted: 3 walks, or 2-3 run-walk sessions (TI-2, BD-2b).
        var sessions: Int
        /// The longest session, running and walking (BD-2a), or the walk length (TI-2a).
        var sessionSeconds: Double
        /// The most running the week may hold in seconds (HL-2, BD-2e), or nil for no cap.
        var runningCap: Double?
        var limit: RunningLimit?
        /// BD-2e's first week: about 1 km of running a session.
        var sessionRunningCap: Double?
        /// An unplanned run or a longer non-stop segment the week makes room after (AD-18).
        var trigger: LoggedRun?
        /// HL-11: strides once a week from the 20-minute step.
        var strides = false
        /// An illness stage that still lets the runner run (AD-12).
        var illness: IllnessStage?
        /// An open Mild report holds the step (AD-13a).
        var mildInjury = false
        /// The 30-minute step holds fewer sessions to stay inside HL-2.
        var fewerSessions = false

        var position: LadderPosition { restart.position }

        var walking: Bool { position.form == .walkStage }
    }

    /// What an injury report means for the ladder on a day (AD-13, AD-14 in steps, AD-18).
    enum InjuryPhase: Hashable {
        case none
        /// Mild: the step repeats until the report closes.
        case hold
        /// No running: Intense's rest phase, or a pause until "Ready".
        case paused
        /// Back to running at `position`; after a Severe pause the step holds until `holdsUntil`.
        case restart(LadderPosition, holdsUntil: Date?)
    }

    /// An AD-18 offer, with the key that marks it answered.
    struct Offer: Hashable {
        var question: CoachQuestion
        var key: String
    }

    // MARK: Entry

    /// Where a starting runner begins (TI-2, BD-2d).
    static func initialState(for entry: StarterEntry) -> LadderState {
        switch entry {
        case .walkStage(let minutes):
            LadderState(form: .walkStage, walkMinutes: minutes.clamped(to: 1 ... walkGoalMinutes), stepIndex: 0)
        case .shortRunWalk:
            LadderState(form: .runWalk, stepIndex: 0)
        case .ladder(let step):
            LadderState(form: .runWalk, stepIndex: step.clamped(to: 0 ... RunWalkStep.lastIndex))
        }
    }

    /// TI-2a: the walk length the runner can manage today, asked once before the first walk.
    static func setFirstWalk(minutes: Double, state: CoachState) -> CoachState {
        guard var ladder = state.ladder, ladder.form == .walkStage, ladder.history.isEmpty else { return state }
        var state = state
        let minutes = minutes.clamped(to: 1 ... walkGoalMinutes)
        ladder.walkMinutes = minutes
        ladder.firstWalkMinutes = minutes
        ladder.entry.walkMinutes = minutes
        state.ladder = ladder
        return state
    }

    // MARK: Planning

    /// The week on the walk stage or the ladder, or nil once the ladder is done. Volume is the week's running in
    /// the plan's unit (running minutes, Terms), already inside HL-2 (BD-2a).
    static func weekTargets(_ context: PlanningContext) -> WeekTargets? {
        guard let week = self.week(context) else { return nil }
        let layout = self.layout(week, extras: [], context: context)
        let step = week.position.step
        let form: RunForm
        if week.walking {
            form = .walk
        } else if step.walkSeconds == 0 {
            form = .continuous
        } else {
            form = .runWalk(runSeconds: step.runSeconds, walkSeconds: step.walkSeconds)
        }
        return WeekTargets(
            kind: .ladder,
            volume: layout.plannedVolume,
            runs: layout.sessions.filter { $0.kind.isRun || $0.kind == .walk }.count,
            strides: week.strides ? 1 : 0,
            form: form,
            sessionCap: Load(meters: 0, seconds: week.sessionSeconds),
            notes: notes(week, context: context) + layout.notes
        )
    }

    /// The ladder week on days, for `Scheduler.layout`: walks, run-walk sessions or 30 minutes non-stop, with the
    /// targets' extras and race.
    static func layout(_ targets: WeekTargets, context: PlanningContext) -> Scheduler.Layout {
        guard let week = self.week(context) else {
            return Scheduler.Layout(sessions: [], notes: [], droppedRuns: 0, plannedVolume: 0, longRun: nil)
        }
        return layout(week, extras: targets.extras, race: targets.race, context: context)
    }

    /// The week's position, sessions and running cap.
    static func week(_ context: PlanningContext) -> Week? {
        let state = context.state
        guard let ladder = state.ladder, ladder.isActive else { return nil }
        let calendar = context.calendar
        let day = referenceDay(context)
        let runs = planRuns(state, runs: context.runs, calendar: calendar)
        let restart = plannedRestart(ladder, state: state, runs: runs, week: context.weekIndex, on: day, calendar: calendar)
        let position = restart.position
        let step = position.step
        let walking = position.form == .walkStage
        var week = Week(
            restart: restart,
            sessions: walking ? walkGoalDays : min(3, max(2, state.cycle.runsPerWeek)),
            sessionSeconds: walking ? position.walkMinutes * 60 : step.sessionSeconds
        )

        // AD-12: a cold keeps easy sessions; the first run back after an illness is one short session.
        if let episode = state.activeIllness, !episode.stopsRunning {
            week.illness = episode.stage
            if episode.stage == .firstRun {
                week.sessions = 1
                week.sessionSeconds = walking ? min(week.sessionSeconds, 20 * 60) : shortestSession(step)
            }
        }
        week.mildInjury = state.openInjuries.contains { injuryPhase($0, ladder: ladder, on: day, calendar: calendar) == .hold }
        guard !walking else { return week }

        // BD-2a: HL-2 by running minutes, with NHS week 1's 8 minutes a session as the floor (TI-2c).
        let pace = self.pace(state)
        if context.weekCap > 0 {
            let cap = Load(context.weekCap, in: context.unit, pace: pace).seconds
            week.runningCap = max(cap, Double(week.sessions) * smallestSessionRunning)
            week.limit = .weekly
        }
        // BD-2e: ≤3 km in the first week with running, then ≤10% a week by time to week 4, then ≤30%.
        if let k = bmiWeek(state, runs: runs, week: context.weekIndex, calendar: calendar) {
            let cap: Double
            if k == 0 {
                cap = bmiFirstWeekMeters / 1_000 * pace
                week.sessionRunningCap = bmiSessionMeters / 1_000 * pace
            } else {
                let previous = doneRunning(state, runs: runs, week: context.weekIndex - 1, calendar: calendar)
                cap = max(previous, bmiFirstWeekMeters / 1_000 * pace) * (k < bmiTimeWeeks ? bmiEarlyGrowth : bmiLaterGrowth)
            }
            if cap < week.runningCap ?? .infinity {
                week.runningCap = cap
                week.limit = .firstWeeks(week: k)
            }
        }
        // 30 minutes non-stop has no repeats to trim: the week holds fewer sessions instead.
        if step.walkSeconds == 0, let cap = week.runningCap {
            let fit = max(1, Int(cap / step.runSeconds + 1e-9))
            if fit < week.sessions {
                week.sessions = fit
                week.fewerSessions = true
            }
        }
        week.trigger = triggerRun(state, runs: runs, weekStart: context.weekStart, calendar: calendar)
        week.strides = step.runSeconds >= stridesSegment && state.openInjuries.isEmpty && state.activeIllness == nil
        return week
    }

    /// Days and sessions: run-walk on non-consecutive run days with 2 rest days, or walks on the run days (TI-2,
    /// HL-10). After an unplanned run the next day is rest and the next session the shortest (AD-18).
    static func layout(_ week: Week, extras: [SessionKind], race: RaceDay? = nil, context: PlanningContext) -> Scheduler.Layout {
        let calendar = context.calendar
        let intake = context.state.intake
        let days = Scheduler.WeekDays(first: Weekday(of: context.weekStart, calendar: calendar))
        let pace = self.pace(context.state)
        let step = week.position.step
        var sessions: [PlannedSession] = []
        var notes: [CoachNote] = []

        let runDays = intake.runDays.isEmpty ? Set(Weekday.allCases) : intake.runDays
        var available = (0 ..< 7).filter { runDays.contains(days.weekday($0)) }
        if let race {
            sessions.append(Scheduler.raceSession(race, context: context))
            available.removeAll { $0 == race.dayOffset || $0 == race.dayOffset - 1 }
        }
        var shortestFrom: Int?
        var restDayTaken = false
        if let trigger = week.trigger {
            let runDay = offset(of: trigger.start, context: context)
            let before = available.count
            available.removeAll { $0 == runDay || $0 == runDay + 1 }
            restDayTaken = available.count < before
            shortestFrom = runDay + 2
            // The shortest session already came last week.
            if runDay + 1 < 0, let previous = context.previousWeek,
               previous.plan.sessions.contains(where: { ($0.kind.isRun || $0.kind == .walk) && $0.dayOffset - 7 > runDay + 1 }) {
                shortestFrom = nil
            }
        }

        var chosen: [Int] = []
        if week.sessions == 1 {
            let today = max(0, offset(of: context.now, context: context))
            if let day = available.first(where: { $0 >= today }) ?? available.last { chosen = [day] }
        } else {
            var count = min(week.sessions, available.count)
            while count > 0 {
                if let set = Scheduler.chooseDays(
                    count: count,
                    from: available,
                    longDay: nil,
                    totalRuns: count,
                    noBackToBack: !week.walking,
                    tenB: false,
                    minimumRest: week.walking ? 0 : 2
                ) {
                    chosen = set
                    break
                }
                count -= 1
            }
        }

        let perSession = week.runningCap.map { $0 / Double(max(1, chosen.count)) } ?? .infinity
        let sessionCap = min(perSession, week.sessionRunningCap ?? .infinity)
        let shortestDay = shortestFrom.flatMap { from in chosen.first { $0 >= from } }
        var trimmed = false
        var stridesLeft = week.strides ? 1 : 0
        for day in chosen {
            var length = day == shortestDay ? shortestSession(step) : week.sessionSeconds
            if let dayMax = intake.maxSeconds(on: days.weekday(day)), dayMax > 0 { length = min(length, dayMax) }
            if week.walking {
                sessions.append(PlannedSession(dayOffset: day, kind: .walk, effort: .easy, target: Load(meters: 0, seconds: length), leadsWith: .time))
                continue
            }
            // The segment is never trimmed (BD-2a).
            length = max(length, step.runSeconds)
            let segments = pieces(step, sessionSeconds: length, runningCap: sessionCap)
            if segments.reduce(0, +) < pieces(step, sessionSeconds: length, runningCap: .infinity).reduce(0, +) - 0.5 { trimmed = true }
            var session = runWalkSession(step, pieces: segments, day: day, context: context)
            if day == shortestDay { session.notes.append("A shorter session today, after your extra running.") }
            if stridesLeft > 0, day != shortestDay {
                session.strides = 4
                stridesLeft -= 1
            }
            sessions.append(session)
        }
        let running = sessions.filter(\.kind.isRun).reduce(0) { $0 + plannedRunning($1) }

        if trimmed {
            switch week.limit {
            case .firstWeeks(let k)? where k == 0:
                if week.restart.reason != .firstWeeks {
                    notes.append(CoachNote(.limit, "Your first week keeps each session to about 1 km of running, about 3 km in all."))
                }
            case .firstWeeks(let k)?:
                notes.append(CoachNote(.limit, "Your running time grows by at most \(k < bmiTimeWeeks ? 10 : 30)% a week for now, so your sessions have fewer repeats."))
            case .weekly?, nil:
                notes.append(CoachNote(.limit, "This week holds \(CoachFormat.minutes(running)) of running, as much as your recent weeks allow, so your sessions have fewer repeats. Each run segment stays the same."))
            }
        }
        let placed = chosen.count
        if placed < week.sessions {
            let count = placed == 1 ? "1 \(week.walking ? "walk" : "session")" : "\(placed) \(week.walking ? "walks" : "sessions")"
            if restDayTaken {
                notes.append(CoachNote(.plan, "The day after your extra running is a rest day, so this week has \(count)."))
            } else if week.walking {
                notes.append(CoachNote(.plan, "Your days fit \(count) this week."))
            } else {
                notes.append(CoachNote(.plan, "Your run days fit \(count) this week, with a rest day between them."))
            }
        }

        // Plan items that aren't runs go on free days, as in the scheduler.
        var busy = Set(chosen)
        if let race { busy.insert(race.dayOffset) }
        var free = (0 ..< 7).filter { !busy.contains($0) }
        if free.isEmpty { free = Array(0 ..< 7) }
        for (index, kind) in extras.enumerated() {
            let day = free[(index * max(1, free.count / max(1, extras.count))) % free.count]
            let minutes: Double = kind == .walk ? 30 : 20
            sessions.append(PlannedSession(dayOffset: day, kind: kind, effort: .easy, target: Load(meters: 0, seconds: minutes * 60), leadsWith: .time))
        }

        return Scheduler.Layout(
            sessions: sessions.sorted { $0.dayOffset < $1.dayOffset },
            notes: notes,
            droppedRuns: week.walking ? 0 : max(0, week.sessions - placed),
            plannedVolume: Load(running, in: .time, pace: pace).amount(in: context.unit),
            longRun: nil
        )
    }

    /// One session's run segments: the short run-walk's ratio repeated, or the ladder's segment repeated while the
    /// session and its running allow, the last one shortened to fit. HL-2 trims repeats, never the segment (BD-2a).
    static func pieces(_ step: RunWalkStep, sessionSeconds: Double, runningCap: Double) -> [Double] {
        let segment = step.runSeconds
        if step.isShortRunWalk {
            let byTime = Int(sessionSeconds / (segment + step.plannedWalkSeconds) + 1e-9)
            let byRunning = runningCap.isFinite ? Int(runningCap / segment + 1e-9) : byTime
            return Array(repeating: segment, count: max(1, min(byTime, byRunning)))
        }
        if step.walkSeconds == 0 { return [segment] }
        let walk = step.plannedWalkSeconds
        var pieces = [segment]
        var elapsed = segment
        var running = segment
        while true {
            let room = min(sessionSeconds - elapsed - walk, runningCap - running).floored(toMultipleOf: pieceStep)
            let next = min(segment, room)
            if next < min(60, segment / 2) { break }
            pieces.append(next)
            elapsed += walk + next
            running += next
            if next < segment { break }
        }
        return pieces
    }

    /// A planned session from its segments: run-walk with timed or open walk breaks, or 30 minutes non-stop.
    static func runWalkSession(_ step: RunWalkStep, pieces: [Double], day: Int, context: PlanningContext) -> PlannedSession {
        let running = pieces.reduce(0, +)
        if step.walkSeconds == 0 {
            return PlannedSession(
                dayOffset: day,
                kind: .easy,
                effort: .easy,
                target: Load(running, in: .time, pace: pace(context.state)),
                leadsWith: .time,
                paceBand: context.state.paces.easy
            )
        }
        func work(_ seconds: Double) -> SessionStep {
            SessionStep(kind: .work, goal: .time(seconds: seconds), effort: .easy)
        }
        var blocks: [SessionBlock] = []
        var notes: [String] = []
        let walks: Double
        if step.isShortRunWalk {
            let walk = step.walkSeconds ?? 0
            blocks = [SessionBlock(repeats: pieces.count, steps: [work(step.runSeconds), SessionStep(kind: .recovery, goal: .time(seconds: walk), effort: .easy, walk: true)])]
            walks = Double(pieces.count) * walk
        } else {
            let head = pieces.dropLast()
            if !head.isEmpty {
                blocks.append(SessionBlock(repeats: head.count, steps: [work(step.runSeconds), SessionStep(kind: .recovery, goal: .open, effort: .easy, walk: true)]))
            }
            blocks.append(SessionBlock(steps: [work(pieces.last ?? step.runSeconds)]))
            notes.append("Walk breaks end when you tap. I'll remind you at 1.5 minutes.")
            walks = Double(head.count) * RunWalkStep.openWalkSeconds
        }
        return PlannedSession(
            dayOffset: day,
            kind: .runWalk,
            effort: .easy,
            target: Load(meters: 0, seconds: running + walks),
            leadsWith: .time,
            blocks: blocks,
            notes: notes
        )
    }

    /// The running a planned session holds: its timed run steps, or the whole target without steps.
    static func plannedRunning(_ session: PlannedSession) -> Double {
        guard session.kind.isRun else { return 0 }
        guard !session.blocks.isEmpty else { return session.target.seconds }
        return session.blocks.reduce(0) { total, block in
            total + Double(block.repeats) * block.steps.reduce(0) { sum, step in
                guard !step.walk, case .time(let seconds) = step.goal else { return sum }
                return sum + seconds
            }
        }
    }

    /// "The next session is the shortest" (AD-18): 15 minutes on the short run-walk, 20 on the ladder, never
    /// below the segment.
    static func shortestSession(_ step: RunWalkStep) -> Double {
        max(step.runSeconds, step.isShortRunWalk ? RunWalkStep.shortestShortSession : RunWalkStep.shortestLadderSession)
    }

    /// The "because" sentences behind the week.
    static func notes(_ week: Week, context: PlanningContext) -> [CoachNote] {
        var notes: [CoachNote] = []
        let description = self.description(week.position)
        switch week.restart.reason {
        case .gap?:
            if let gap = week.restart.gap {
                let steps = stepsBetween(gap.position, gap.base)
                let back = steps == 1 ? "one step" : "two steps"
                notes.append(CoachNote(.plan, "Welcome back. After \(gap.days) days off, this week restarts \(back) back, with \(description). Nothing to catch up."))
            }
        case .injury?:
            notes.append(CoachNote(.injury, "Back to running after your injury: this week you restart with \(description). Nothing to catch up."))
        case .firstWeeks?:
            notes.append(CoachNote(.plan, "Your first weeks keep each session to about 1 km of running, so you start with \(description)."))
        default:
            break
        }
        if week.mildInjury {
            notes.append(CoachNote(.injury, "This week repeats your step because of your injury. It stays until the injury clears."))
        }
        switch week.illness {
        case .headCold?:
            notes.append(CoachNote(.illness, "Easy sessions while you have a cold, and your step stays the same this week."))
        case .firstRun?:
            notes.append(CoachNote(.illness, "One short, easy session to start back, at a talking pace."))
        default:
            break
        }
        if week.fewerSessions {
            notes.append(CoachNote(.limit, "This week has \(week.sessions == 1 ? "1 run" : "\(week.sessions) runs") of 30 minutes, as much running as your recent weeks allow."))
        }
        // BD-2a, said once: the first week with running.
        let ranBefore = context.runs.contains { $0.start >= context.state.startDate && $0.start < context.weekStart && $0.runningSeconds > 0 }
        if !week.walking, !ranBefore {
            notes.append(CoachNote(.plan, "Slow enough to talk. Don't sprint the run parts."))
        }
        return notes
    }

    // MARK: Restarts (AD-18)

    /// Where the week is planned: the ladder's position, or a restart after an injury, a gap or BD-2e's first
    /// week, whichever is easiest.
    static func plannedRestart(_ ladder: LadderState, state: CoachState, runs: [LoggedRun], week index: Int, on day: Date, calendar: Calendar) -> Restart {
        var restart = Restart(position: ladder.position, reason: nil, gap: nil, injuries: [])
        for report in state.injuries where !ladder.handledInjuries.contains(report.id) {
            guard case .restart(let position, _) = injuryPhase(report, ladder: ladder, on: day, calendar: calendar) else { continue }
            restart.injuries.append(report.id)
            if position.isEasier(than: restart.position) {
                restart.position = position
                restart.reason = .injury
            }
        }
        if let gap = gap(ladder, state: state, runs: runs, week: index, on: day, calendar: calendar), gap.position.isEasier(than: restart.position) {
            restart.position = gap.position
            restart.reason = .gap
            restart.gap = gap
        }
        if let first = firstWeeksPosition(ladder, state: state, runs: runs, week: index, calendar: calendar), first.isEasier(than: restart.position) {
            restart.position = first
            restart.reason = .firstWeeks
        }
        return restart
    }

    /// AD-18's gap rows for a runner back on `day`: 8-14 days without a run goes back one step, 15-28 days two,
    /// longer two until the runner picks where to restart. Nil under 8 days, after an Intense or Severe report
    /// (the injury rules set the way back), or when the row is already in force.
    static func gap(_ ladder: LadderState, state: CoachState, runs: [LoggedRun], week index: Int, on day: Date, calendar: Calendar) -> Gap? {
        let back = calendar.startOfDay(for: day)
        guard let last = runs.last(where: { $0.start < back }) else { return nil }
        let lastRunDay = calendar.startOfDay(for: last.start)
        let days = calendar.dateComponents([.day], from: lastRunDay, to: back).day ?? 0
        guard days >= gapDays else { return nil }
        let dayAfter = calendar.date(byAdding: .day, value: 1, to: back) ?? back
        if state.injuries.contains(where: { $0.everIntenseOrSevere && $0.reportedAt >= last.start && $0.reportedAt < dayAfter }) { return nil }
        let tier = days <= shortGapDays ? 1 : (days <= longGapDays ? 2 : 3)
        if let handled = ladder.handledGap, handled.lastRunDay == lastRunDay, handled.tier >= tier { return nil }
        // Where the runner was: moves the step rules earned count, restarts made during the gap don't.
        let nextWeek = state.weekStart(index + 1, calendar: calendar)
        let base = ladder.history.last { $0.date <= nextWeek && ($0.date <= lastRunDay || $0.reason.isEarned) }?.position ?? ladder.entry
        let position = ladder.back(tier == 1 ? 1 : 2, from: base)
        return Gap(lastRunDay: lastRunDay, days: days, tier: tier, base: base, position: position)
    }

    /// BD-2e's first week: a step whose segment doesn't fit 1 km of running gives way to the longest one that does.
    static func firstWeeksPosition(_ ladder: LadderState, state: CoachState, runs: [LoggedRun], week index: Int, calendar: Calendar) -> LadderPosition? {
        guard ladder.form == .runWalk, !ladder.step.isShortRunWalk,
              bmiWeek(state, runs: runs, week: index, calendar: calendar) == 0 else { return nil }
        let cap = bmiSessionMeters / 1_000 * pace(state)
        guard ladder.step.runSeconds > cap else { return nil }
        let fitting = RunWalkStep.ladderIndex(minutes: cap / 60)
        return LadderPosition(form: .runWalk, stepIndex: min(fitting, ladder.stepIndex), walkMinutes: ladder.walkMinutes)
    }

    /// BD-2e applies to Starters with BMI ≥30 until the early window ends.
    static func bmiRule(_ state: CoachState) -> Bool {
        guard let bmi = state.intake.bmi, bmi >= bmiThreshold else { return false }
        return state.assessment.overlays.earlyWindow
    }

    /// BD-2e's week count: 0 for the first week with running, or nil when the rule doesn't apply.
    static func bmiWeek(_ state: CoachState, runs: [LoggedRun], week index: Int, calendar: Calendar) -> Int? {
        guard bmiRule(state) else { return nil }
        let start = state.weekStart(index, calendar: calendar)
        guard let first = runs.first(where: { $0.runningSeconds > 0 && $0.start < start }) else { return 0 }
        return max(0, index - state.weekIndex(on: first.start, calendar: calendar))
    }

    // MARK: Injuries on the ladder (AD-13, AD-14, BD-2f)

    /// What a report means for the ladder on `day`: Mild holds the step; Intense restarts 2 steps back after its
    /// rest phase; Severe (or Intense without clearance) restarts by AD-18's gap rows for the pause and holds the
    /// step through the return weeks. The runner may pick any number of steps back instead.
    static func injuryPhase(_ report: InjuryReport, ladder: LadderState, on day: Date, calendar: Calendar) -> InjuryPhase {
        let day = calendar.startOfDay(for: day)
        if case .closed(let closedOn) = report.status, calendar.startOfDay(for: closedOn) <= day { return .none }
        guard let dayAfter = calendar.date(byAdding: .day, value: 1, to: day), report.reportedAt < dayAfter else { return .none }
        let before = ladder.position(on: report.reportedAt)
        switch report.level {
        case .mild:
            return .hold
        case .intense where report.clearance == .yes:
            let cleared = report.events.first { event in
                if case .clearance(.yes) = event.kind { return true }
                return false
            }?.date
            let start = calendar.startOfDay(for: report.recoveryStart ?? cleared ?? report.reportedAt)
            let restWeeks = report.recoveryPlan?.restWeeks ?? RecoveryPlanSettings.standard.restWeeks
            guard let resume = calendar.date(byAdding: .day, value: 7 * restWeeks, to: start), day >= resume else { return .paused }
            return .restart(ladder.back(restartSteps(report, ladder: ladder, readyDay: resume, calendar: calendar), from: before), holdsUntil: nil)
        case .intense, .severe:
            guard let ready = report.readyAt, day >= calendar.startOfDay(for: ready) else { return .paused }
            let returnStart = calendar.startOfDay(for: report.returnStart ?? ready)
            let holds = calendar.date(byAdding: .day, value: 7 * (report.returnPlan?.weeks ?? 2), to: returnStart)
            return .restart(ladder.back(restartSteps(report, ladder: ladder, readyDay: ready, calendar: calendar), from: before), holdsUntil: holds)
        }
    }

    /// Steps back after a report: the runner's pick, else 2 after Intense's rest phase, else AD-18's gap rows for
    /// the days from the last run to "Ready".
    static func restartSteps(_ report: InjuryReport, ladder: LadderState, readyDay: Date, calendar: Calendar) -> Int {
        if let choice = ladder.injuryChoices.last(where: { $0.reportID == report.id }) { return max(0, choice.stepsBack) }
        if report.level == .intense, report.clearance == .yes { return 2 }
        let stopped = calendar.startOfDay(for: report.lastRunBeforePause ?? report.pauseStart ?? report.reportedAt)
        let days = calendar.dateComponents([.day], from: stopped, to: calendar.startOfDay(for: readyDay)).day ?? 0
        return days < gapDays ? 0 : (days <= shortGapDays ? 1 : 2)
    }

    /// True when the ladder plans the week despite open reports: a Mild report's repeat, or the restart after an
    /// Intense report's rest phase or a Severe report's "Ready". `InjuryCoach.weekTargets` returns nil for these.
    static func plansInjuryWeek(_ context: PlanningContext) -> Bool {
        let state = context.state
        guard let ladder = state.ladder, ladder.isActive, !state.openInjuries.isEmpty else { return false }
        let day = referenceDay(context)
        return state.openInjuries.allSatisfy { injuryPhase($0, ladder: ladder, on: day, calendar: context.calendar) != .paused }
    }

    /// True when the ladder plans the week during an illness that lets the runner run (AD-12's cold and return
    /// stages). `IllnessCoach.weekTargets` returns nil for these.
    static func plansIllnessWeek(_ context: PlanningContext) -> Bool {
        guard let ladder = context.state.ladder, ladder.isActive, let episode = context.state.activeIllness else { return false }
        return !episode.stopsRunning
    }

    /// Where an Intense or Severe report restarts the runner, for its screens, or nil.
    static func injuryRestart(for reportID: UUID, state: CoachState, now: Date, calendar: Calendar) -> LadderPosition? {
        guard let ladder = state.ladder, ladder.isActive,
              let report = state.injuries.first(where: { $0.id == reportID }), report.level >= .intense else { return nil }
        let steps = restartSteps(report, ladder: ladder, readyDay: report.readyAt ?? now, calendar: calendar)
        return ladder.back(steps, from: ladder.position(on: report.reportedAt))
    }

    /// The restarts the runner can pick after a report, from the floor up to the pre-injury step (AD-13b: any
    /// number of steps back, including none).
    static func injuryRestartOptions(for reportID: UUID, state: CoachState) -> [LadderPosition] {
        guard let ladder = state.ladder, ladder.isActive, let report = state.injuries.first(where: { $0.id == reportID }) else { return [] }
        let before = ladder.position(on: report.reportedAt)
        return positions(from: ladder.floor(for: before), to: before)
    }

    /// The runner's pick of steps back after a report.
    static func setInjuryRestart(stepsBack: Int, reportID: UUID, state: CoachState) -> CoachState {
        guard var ladder = state.ladder else { return state }
        var state = state
        ladder.injuryChoices.removeAll { $0.reportID == reportID }
        ladder.injuryChoices.append(LadderInjuryChoice(reportID: reportID, stepsBack: max(0, stepsBack)))
        state.ladder = ladder
        return state
    }

    /// BD-2f: an Intense recovery plan on the ladder ends when the runner is back on the pre-injury step.
    static func backToPreInjuryStep(_ report: InjuryReport, state: CoachState) -> Bool {
        guard let ladder = state.ladder, ladder.isActive else { return true }
        return ladder.handledInjuries.contains(report.id) && !ladder.position.isEasier(than: ladder.position(on: report.reportedAt))
    }

    /// The injury that keeps the step from moving up on `day`, as the "because" phrase, or nil.
    static func injuryBlocker(_ state: CoachState, ladder: LadderState, on day: Date, calendar: Calendar) -> String? {
        for report in state.injuries {
            switch injuryPhase(report, ladder: ladder, on: day, calendar: calendar) {
            case .hold, .paused:
                return "of your injury"
            case .restart(_, let holds?) where holds > day:
                return "you're in your return weeks"
            case .none, .restart:
                continue
            }
        }
        return nil
    }

    // MARK: Runs (AD-18)

    /// AD-18's unplanned-run row: a run on run-walk that matched no session, or one whose non-stop segment ran past
    /// the step's. Runs in a week not planned yet wait until matching has seen them.
    static func isTrigger(_ run: LoggedRun, state: CoachState, calendar: Calendar) -> Bool {
        guard let ladder = state.ladder, run.runningSeconds > 0, ladder.position(on: run.start).form == .runWalk else { return false }
        let week = state.weekIndex(on: run.start, calendar: calendar)
        guard state.weeks.contains(where: { $0.plan.index == week }) else { return false }
        guard let session = matchedSession(run, state: state) else { return true }
        guard session.kind == .runWalk, let nonStop = run.track?.longestNonStopSeconds else { return false }
        return nonStop > plannedSegment(session, ladder: ladder, on: run.start) + longerSegmentMargin
    }

    /// The latest trigger run from a week before `weekStart` to a week after.
    static func triggerRun(_ state: CoachState, runs: [LoggedRun], weekStart: Date, calendar: Calendar) -> LoggedRun? {
        let from = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
        let to = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        return runs.last { $0.start >= from && $0.start < to && isTrigger($0, state: state, calendar: calendar) }
    }

    /// The longest run step a session planned, or the step's segment.
    static func plannedSegment(_ session: PlannedSession, ladder: LadderState, on date: Date) -> Double {
        let segments = session.blocks.flatMap(\.steps).compactMap { step -> Double? in
            guard step.kind == .work, !step.walk, case .time(let seconds) = step.goal else { return nil }
            return seconds
        }
        return segments.max() ?? ladder.position(on: date).step.runSeconds
    }

    /// A saved run on the ladder: an unplanned run or a longer non-stop segment counts for volume, the next day is
    /// rest and the next session the shortest; the step never jumps (AD-18).
    static func runLogged(_ run: LoggedRun, state: CoachState, now: Date, calendar: Calendar) -> CoachUpdate {
        guard let ladder = state.ladder, ladder.isActive, isTrigger(run, state: state, calendar: calendar) else { return CoachUpdate(state: state) }
        let key = "ladderTrigger|\(run.id.uuidString)"
        guard !state.shownOnce.contains(key) else { return CoachUpdate(state: state) }
        var state = state
        state.shownOnce.insert(key)
        let text: String
        if matchedSession(run, state: state) == nil {
            text = "That extra run counts toward your week. Take tomorrow off, and your next session is a shorter one. Nothing else changes."
        } else {
            let nonStop = run.track?.longestNonStopSeconds ?? 0
            text = "You ran \(CoachFormat.minutes(nonStop)) without stopping. Nice! Take tomorrow off, and your next session is a shorter one. The ladder still moves one step at a time."
        }
        return CoachUpdate(state: state, notes: [CoachNote(.plan, text)])
    }

    // MARK: Week end

    /// The week-end step: a restart in force is recorded, 30 minutes non-stop hands off to the cycle (TI-6), and
    /// the step moves up, repeats or goes back (BD-2b, BD-2c, BD-2f, AD-18). May be called again for the same week
    /// after a late check-in, from the state the first call saw, so it never applies a step twice.
    static func weekEnded(_ index: Int, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        guard var ladder = state.ladder, ladder.isActive, (ladder.lastEndedWeek ?? -1) < index,
              let record = state.weeks.first(where: { $0.plan.index == index }) else { return CoachUpdate(state: state) }
        var state = state
        ladder.lastEndedWeek = index
        let start = record.plan.start
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let all = planRuns(state, runs: runs, calendar: calendar)
        let weekRuns = all.filter { $0.start >= start && $0.start < end }

        // The restart the week was planned with, from the day the runner came back.
        if let first = weekRuns.first {
            let day = calendar.startOfDay(for: first.start)
            let restart = plannedRestart(ladder, state: state, runs: all, week: index, on: day, calendar: calendar)
            if let reason = restart.reason, restart.position != ladder.position {
                ladder.move(to: restart.position, on: day, reason: reason)
            }
            if let gap = restart.gap { ladder.handledGap = LadderGapMark(lastRunDay: gap.lastRunDay, tier: gap.tier) }
            for id in restart.injuries where !ladder.handledInjuries.contains(id) { ladder.handledInjuries.append(id) }
        }

        if let finish = weekRuns.first(where: { finishesLadder($0, ladder: ladder, state: state, calendar: calendar) }) {
            return handOff(ladder, run: finish, record: record, state: state, runs: runs, weekEnd: end, calendar: calendar)
        }
        guard record.plan.kind == .ladder else {
            state.ladder = ladder
            return CoachUpdate(state: state)
        }
        let (next, notes) = stepRule(ladder, record: record, state: state, runs: all, weekEnd: end, calendar: calendar)
        state.ladder = next
        return CoachUpdate(state: state, notes: notes)
    }

    /// BD-2b's step rule with AD-18's hiccups; the walk stage grows by 5 minutes a week until 30 brisk minutes on
    /// 3 days start the run-walk (TI-2a, TI-6).
    static func stepRule(_ ladder: LadderState, record: WeekRecord, state: CoachState, runs: [LoggedRun], weekEnd end: Date, calendar: Calendar) -> (LadderState, [CoachNote]) {
        var ladder = ladder
        let week = record.plan
        let lastDay = calendar.date(byAdding: .day, value: -1, to: end) ?? week.start
        let walking = ladder.form == .walkStage
        let weekRuns = runs.filter { $0.start >= week.start && $0.start < end }
        let doneRuns: [LoggedRun] = week.sessions.compactMap { session in
            guard walking ? session.kind == .walk : session.kind.isRun, case .done(let id) = session.status else { return nil }
            return weekRuns.first { $0.id == id }
        }
        let hard = weekRuns.compactMap(\.rpe).filter { $0 >= hardRPE }.count
        let tooHard = record.checkIn?.week == .tooHard
        let same = walking ? "Same walks" : "Same step"

        // AD-18: two hard sessions or a "too hard" week go back a step; one hard session repeats it.
        if tooHard || hard >= 2 {
            let because = tooHard ? "you rated this week too hard" : (walking ? "two walks felt hard" : "two sessions felt hard")
            let back = ladder.back(1, from: ladder.position)
            guard back.isEasier(than: ladder.position) else {
                return (ladder, [CoachNote(.outcome, "\(same) next week, because \(because). Nothing to make up.")])
            }
            ladder.move(to: back, on: end, reason: tooHard ? .tooHard : .hardSessions)
            return (ladder, [CoachNote(.outcome, "Next week goes back a step, to \(description(back)), because \(because). Nothing to make up.")])
        }
        if hard == 1 {
            return (ladder, [CoachNote(.outcome, "\(same) next week, because one \(walking ? "walk" : "session") felt hard. Nothing to make up.")])
        }
        if let because = injuryBlocker(state, ladder: ladder, on: lastDay, calendar: calendar) {
            return (ladder, [CoachNote(.injury, "\(same) next week, because \(because).")])
        }
        if let episode = state.illnesses.last(where: { $0.reportedAt < end && ($0.endedAt ?? .distantFuture) > week.start }) {
            let because = episode.kind == .feverOrBelowNeck ? "you've been ill" : "of your cold"
            return (ladder, [CoachNote(.illness, "\(same) next week, because \(because).")])
        }

        if walking {
            // TI-6: 30 brisk minutes on 3 days (on every run day when there are fewer) start the run-walk.
            let longDays = Set(weekRuns.filter { $0.movingSeconds >= walkGoalMinutes * 60 - 60 }.map { calendar.startOfDay(for: $0.start) }).count
            let runDays = state.intake.runDays.isEmpty ? walkGoalDays : state.intake.runDays.count
            if longDays >= min(walkGoalDays, runDays) {
                let next = LadderPosition(form: .runWalk, stepIndex: 0, walkMinutes: ladder.walkMinutes)
                ladder.move(to: next, on: end, reason: .startRunWalk)
                return (ladder, [CoachNote(.milestone, "You walked briskly for 30 minutes on \(longDays) days. Next week you start run-walk: \(next.step.summary).")])
            }
            // TI-2a: two walks at their length add up to 5 minutes.
            let atLength = weekRuns.filter { $0.movingSeconds >= ladder.walkMinutes * 60 * walkDoneShare }.count
            guard atLength >= 2 else {
                return (ladder, weekRuns.isEmpty ? [] : [CoachNote(.outcome, "Same walks next week, so you can do at least two at this length. Nothing to make up.")])
            }
            let minutes = min(walkGoalMinutes, ladder.walkMinutes + walkStepMinutes)
            guard minutes > ladder.walkMinutes + 0.01 else {
                return (ladder, [CoachNote(.outcome, "Good week. Walk 30 minutes on 3 days and you start run-walk.")])
            }
            ladder.move(to: LadderPosition(form: .walkStage, stepIndex: ladder.stepIndex, walkMinutes: minutes), on: end, reason: .longerWalks)
            return (ladder, [CoachNote(.outcome, "Good week. Next week your walks are \(LadderPosition.minutesText(minutes)) minutes.")])
        }

        // BD-2b: ≥2 sessions done, rated RPE ≤5.
        guard doneRuns.count >= 2 else {
            return (ladder, doneRuns.isEmpty ? [] : [CoachNote(.outcome, "Same step next week, so you can do at least two sessions at it. Nothing to make up.")])
        }
        guard doneRuns.compactMap(\.rpe).filter({ $0 <= comfortableRPE }).count >= 2 else {
            return (ladder, [CoachNote(.outcome, "Rate two runs this week so I can move you forward.")])
        }
        ladder.weeksOnStep += 1
        if let k = bmiWeek(state, runs: runs, week: week.index, calendar: calendar), k < bmiTimeWeeks - 1 {
            return (ladder, [CoachNote(.outcome, "Good week. Your first four weeks stay at this step while your running time builds.")])
        }
        if ladder.weeksOnStep < requiredWeeks(ladder, state: state) {
            return (ladder, [CoachNote(.outcome, "Good week. One more week at this step, then the next one.")])
        }
        guard ladder.stepIndex < RunWalkStep.lastIndex else {
            return (ladder, [CoachNote(.outcome, "Good week. Next week: 30 minutes non-stop again.")])
        }
        let next = LadderPosition(form: .runWalk, stepIndex: ladder.stepIndex + 1, walkMinutes: ladder.walkMinutes)
        ladder.move(to: next, on: end, reason: .stepUp)
        return (ladder, [CoachNote(.outcome, "Good week. Next week: \(next.step.summary).")])
    }

    /// Weeks a step takes (BD-2c, TI-2b): 2 at risk score ≥2, at 65+ and under BD-2e; at Gentle 2 for each short
    /// run-walk ratio and for every 3rd ladder step; else 1.
    static func requiredWeeks(_ ladder: LadderState, state: CoachState) -> Int {
        let assessment = state.assessment
        if assessment.risk.isHigh || assessment.age >= 65 || bmiRule(state) { return 2 }
        guard state.level == .gentle else { return 1 }
        if ladder.step.isShortRunWalk { return 2 }
        let ladderStep = ladder.stepIndex - RunWalkStep.ladderStart + 1
        return ladderStep > 0 && ladderStep % 3 == 0 ? 2 : 1
    }

    /// TI-6: 30 minutes non-stop on the last step, at RPE ≤5, with no report holding the step.
    static func finishesLadder(_ run: LoggedRun, ladder: LadderState, state: CoachState, calendar: Calendar) -> Bool {
        let position = ladder.position(on: run.start)
        guard position.form == .runWalk, position.stepIndex == RunWalkStep.lastIndex,
              let rpe = run.rpe, rpe <= comfortableRPE, nonStopSeconds(run) >= finishSeconds else { return false }
        return injuryBlocker(state, ladder: ladder, on: run.start, calendar: calendar) == nil
    }

    /// The run's longest non-stop stretch: from the track, else the whole run when it logged no walking.
    static func nonStopSeconds(_ run: LoggedRun) -> Double {
        if let seconds = run.track?.longestNonStopSeconds { return seconds }
        return (run.walkingSeconds ?? 0) > 0 ? 0 : run.movingSeconds
    }

    /// TI-6's hand-off: the ladder is done, the runner is a Novice who runs 30 minutes, and the level's cycle
    /// starts from this week (BD-2d: no calibration).
    static func handOff(_ ladder: LadderState, run: LoggedRun, record: WeekRecord, state: CoachState, runs: [LoggedRun], weekEnd: Date, calendar: Calendar) -> CoachUpdate {
        var ladder = ladder
        var state = state
        ladder.finishedOn = run.start
        ladder.move(to: LadderPosition(form: .done, stepIndex: RunWalkStep.lastIndex, walkMinutes: ladder.walkMinutes), on: weekEnd, reason: .finished)
        state.ladder = ladder
        let unit = state.volumeUnit
        let pace = self.pace(state)
        state.assessment.tier = max(state.assessment.tier, .novice)
        state.assessment.runs30Minutes = true
        state.assessment.start.sustainedRunLength = max(state.assessment.start.sustainedRunLength ?? 0, Load(30 * 60, in: .time, pace: pace).amount(in: unit))
        let done = LoadMetrics.doneVolume(week: record.plan.index, planStart: state.startDate, sessions: LoadMetrics.sessions(from: runs), unit: unit, pace: pace, calendar: calendar)
        let volume = record.plan.plannedVolume > 0 ? min(record.plan.plannedVolume, done) : done
        state.v0 = volume
        state.cycle.lastLoadingVolume = volume
        state.cycle.lastLoadingLongRun = run.load
        state.cycle.position = 0
        state.cycle.loadingInRow = 0
        return CoachUpdate(state: state, notes: [CoachNote(.milestone, "You ran 30 minutes non-stop at an easy effort. That moves you up a stage.")])
    }

    // MARK: Offers (AD-18)

    /// Questions the ladder is waiting on: one AD-18 offer at a time, and the optional morning check after an
    /// unplanned run or a longer segment.
    static func questions(_ state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> [CoachQuestion] {
        var questions = offers(state, runs: runs, now: now, calendar: calendar).prefix(1).map(\.question)
        guard let ladder = state.ladder, ladder.isActive else { return questions }
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              !state.morningChecks.contains(where: { $0.date >= today }) else { return questions }
        for run in runs where run.start >= yesterday && run.start < today && isTrigger(run, state: state, calendar: calendar) {
            questions.append(.morningCheck(runID: run.id))
        }
        return questions
    }

    /// AD-18's open offers, first to show first: where to restart after more than 28 days, the one-tap restart
    /// after 2 idle weeks, and the easier week after 2 missed sessions in a row.
    static func offers(_ state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> [Offer] {
        guard let ladder = state.ladder, ladder.isActive, state.status.isActive,
              !state.openInjuries.contains(where: { $0.level >= .intense }) else { return [] }
        let today = calendar.startOfDay(for: now)
        let runs = planRuns(state, runs: runs, calendar: calendar)
        var offers: [Offer] = []
        if let gap = gap(ladder, state: state, runs: runs, week: state.weekIndex(on: now, calendar: calendar), on: today, calendar: calendar),
           gap.tier >= 3, restartOptions(state).count > 1 {
            offers.append(Offer(question: .ladderRestartWhere, key: "where|\(Int(gap.lastRunDay.timeIntervalSinceReferenceDate))"))
        }
        if ladder.back(1, from: ladder.position).isEasier(than: ladder.position) {
            let lastDay = runs.last { $0.start < now }.map { calendar.startOfDay(for: $0.start) } ?? calendar.startOfDay(for: state.startDate)
            if (calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0) >= idleDays {
                offers.append(Offer(question: .ladderIdleRestart, key: "idle|\(Int(lastDay.timeIntervalSinceReferenceDate))"))
            }
            if let pair = missedPair(state, now: now, calendar: calendar), !ladder.answeredOffers.contains("missed|\(pair.first.uuidString)") {
                offers.append(Offer(question: .ladderEasierRestart, key: "missed|\(pair.second.uuidString)"))
            }
        }
        return offers.filter { !ladder.answeredOffers.contains($0.key) }
    }

    /// The last two ladder sessions before today, when both were missed.
    static func missedPair(_ state: CoachState, now: Date, calendar: Calendar) -> (first: UUID, second: UUID)? {
        let today = calendar.startOfDay(for: now)
        let past = state.weeks
            .filter { $0.plan.kind == .ladder }
            .flatMap { record in
                record.plan.sessions
                    .filter { $0.kind.isRun || $0.kind == .walk }
                    .map { (session: $0, day: state.date(of: $0, in: record.plan, calendar: calendar)) }
            }
            .filter { $0.day < today }
            .sorted { $0.day < $1.day }
        guard past.count >= 2 else { return nil }
        let first = past[past.count - 2].session
        let second = past[past.count - 1].session
        guard first.status == .missed, second.status == .missed else { return nil }
        return (first.id, second.id)
    }

    /// AD-18's easier restart, after the runner accepts it: one step back, or the gap row's restart when that is
    /// easier.
    static func restartEasier(state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        guard var ladder = state.ladder, ladder.isActive else { return CoachUpdate(state: state) }
        var state = state
        let today = calendar.startOfDay(for: now)
        let keys = offers(state, runs: runs, now: now, calendar: calendar).map(\.key)
        let gap = self.gap(ladder, state: state, runs: planRuns(state, runs: runs, calendar: calendar), week: state.weekIndex(on: now, calendar: calendar), on: today, calendar: calendar)
        var target = ladder.back(1, from: ladder.position)
        if let gap { target = LadderPosition.easier(target, gap.position) }
        if target != ladder.position { ladder.move(to: target, on: today, reason: .easierRestart) }
        if let gap { ladder.handledGap = LadderGapMark(lastRunDay: gap.lastRunDay, tier: gap.tier) }
        for key in keys where !ladder.answeredOffers.contains(key) { ladder.answeredOffers.append(key) }
        state.ladder = ladder
        return CoachUpdate(state: state, notes: [CoachNote(.plan, "Done: you'll restart with \(description(target)). Nothing to catch up.")])
    }

    /// "Not now" to the easier restart: the offers showing now stay answered.
    static func easierRestartDeclined(state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachState {
        guard var ladder = state.ladder else { return state }
        var state = state
        for offer in offers(state, runs: runs, now: now, calendar: calendar) where offer.question != .ladderRestartWhere && !ladder.answeredOffers.contains(offer.key) {
            ladder.answeredOffers.append(offer.key)
        }
        state.ladder = ladder
        return state
    }

    /// The positions a runner back after more than 28 days can restart at: from the floor up to where they are.
    static func restartOptions(_ state: CoachState) -> [LadderPosition] {
        guard let ladder = state.ladder, ladder.isActive else { return [] }
        return positions(from: ladder.floor(for: ladder.position), to: ladder.position)
    }

    /// The runner's answer to "Where would you like to restart?" (AD-18). A position not on offer keeps the step.
    static func restart(at position: LadderPosition, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        guard var ladder = state.ladder, ladder.isActive else { return CoachUpdate(state: state) }
        var state = state
        let today = calendar.startOfDay(for: now)
        let keys = offers(state, runs: runs, now: now, calendar: calendar).map(\.key)
        let gap = self.gap(ladder, state: state, runs: planRuns(state, runs: runs, calendar: calendar), week: state.weekIndex(on: now, calendar: calendar), on: today, calendar: calendar)
        let chosen = restartOptions(state).contains(position) ? position : ladder.position
        if chosen != ladder.position { ladder.move(to: chosen, on: today, reason: .chosenRestart) }
        if let gap { ladder.handledGap = LadderGapMark(lastRunDay: gap.lastRunDay, tier: gap.tier) }
        for key in keys where !ladder.answeredOffers.contains(key) { ladder.answeredOffers.append(key) }
        state.ladder = ladder
        return CoachUpdate(state: state, notes: [CoachNote(.plan, "Done: you'll restart with \(description(chosen)). Nothing to catch up.")])
    }

    /// Every position from `low` up to `high`: walk lengths in 5-minute steps, or run-walk steps.
    static func positions(from low: LadderPosition, to high: LadderPosition) -> [LadderPosition] {
        switch high.form {
        case .walkStage:
            var result: [LadderPosition] = []
            var minutes = high.walkMinutes
            while minutes > low.walkMinutes + 0.01 {
                result.insert(LadderPosition(form: .walkStage, stepIndex: high.stepIndex, walkMinutes: minutes), at: 0)
                minutes -= walkStepMinutes
            }
            result.insert(LadderPosition(form: .walkStage, stepIndex: high.stepIndex, walkMinutes: low.walkMinutes), at: 0)
            return result
        case .runWalk, .done:
            return (low.stepIndex ... max(low.stepIndex, high.stepIndex)).map { LadderPosition(form: .runWalk, stepIndex: $0, walkMinutes: high.walkMinutes) }
        }
    }

    // MARK: Helpers

    /// The pace for converting distance and time: the easy band's middle, else a slow easy pace.
    static func pace(_ state: CoachState) -> Double {
        state.paces.easyPace ?? RunnerAssessor.fallbackPace
    }

    /// The plan's runs and walks, oldest first.
    static func planRuns(_ state: CoachState, runs: [LoggedRun], calendar: Calendar) -> [LoggedRun] {
        let start = calendar.startOfDay(for: state.startDate)
        return runs.filter { $0.start >= start && $0.movingSeconds > 0 }.sorted { $0.start < $1.start }
    }

    /// Running done in plan week `index`, in seconds.
    static func doneRunning(_ state: CoachState, runs: [LoggedRun], week index: Int, calendar: Calendar) -> Double {
        LoadMetrics.doneVolume(week: index, planStart: state.startDate, sessions: LoadMetrics.sessions(from: runs), unit: .time, pace: nil, calendar: calendar)
    }

    static func matchedSession(_ run: LoggedRun, state: CoachState) -> PlannedSession? {
        for record in state.weeks {
            if let session = record.plan.sessions.first(where: { $0.status == .done(runID: run.id) }) { return session }
        }
        return nil
    }

    /// The day restarts are measured to: today while the week runs, else its first day.
    static func referenceDay(_ context: PlanningContext) -> Date {
        let calendar = context.calendar
        let today = calendar.startOfDay(for: context.now)
        let end = calendar.date(byAdding: .day, value: 7, to: context.weekStart) ?? context.weekStart
        return today > context.weekStart && today < end ? today : context.weekStart
    }

    /// Days from the week's first day to `date`'s day.
    static func offset(of date: Date, context: PlanningContext) -> Int {
        context.calendar.dateComponents([.day], from: context.weekStart, to: context.calendar.startOfDay(for: date)).day ?? 0
    }

    /// Steps between two positions on the same stage: run-walk steps, or 5-minute walk steps.
    static func stepsBetween(_ low: LadderPosition, _ high: LadderPosition) -> Int {
        if high.form == .walkStage { return Int(((high.walkMinutes - low.walkMinutes) / walkStepMinutes).rounded(.up)) }
        return high.stepIndex - low.stepIndex
    }

    /// "20-minute walks", "1 minute of running at a time", "30 minutes non-stop".
    static func description(_ position: LadderPosition) -> String {
        position.form == .walkStage ? position.name : position.step.summary
    }
}
