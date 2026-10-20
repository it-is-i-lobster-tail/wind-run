//
//  RaceDay.swift
//  Wind Run
//

import Foundation

/// Race day and after (EV-9): the result, "Did you race?", recovery by the distance run, and "What next?" with
/// the hand-off it starts (RC-12a).
extension EventReviewer {
    /// A race-day run of 90% of the race distance or more is a finish (EV-9).
    static let finishShare = 0.9

    // MARK: The race

    /// Records the race (EV-9) from the run matched to it, or from "recorded elsewhere" (`run` nil). A finish
    /// with a time becomes a race result and, as the newest, the anchor in force (PZ-2): slower paces apply at
    /// once and faster ones step in (PZ-7). Under 90% of the distance is a DNF, with FB-3's question first when
    /// there is a run. With no distance it counts as a finish with no result. Once the race is recorded, another
    /// call changes nothing.
    static func recordRace(
        meters: Double?,
        seconds: Double?,
        run: LoggedRun?,
        state: CoachState,
        runs: [LoggedRun] = [],
        now: Date,
        calendar: Calendar
    ) -> CoachUpdate {
        guard let event = state.event, state.eventReview.outcome == nil else { return CoachUpdate(state: state) }
        var state = state
        let distance = state.goal.distance
        let raceDay = calendar.startOfDay(for: event.raceDate)
        state.eventReview.raceRunID = run?.id
        state.eventReview.distanceRun = meters
        if let meters, meters < finishShare * distance.meters {
            state.eventReview.outcome = .didNotFinish
            let until = easyUntil(recoveryDistance(state) ?? distance, raceDay: raceDay, calendar: calendar)
            let note = CoachNote(.event, "Not every race goes to plan. Easy running only until \(CoachFormat.date(until, calendar: calendar)), then we build again.")
            return CoachUpdate(state: state, notes: [note], questions: run.map { [CoachQuestion.whatHappened(runID: $0.id)] } ?? [])
        }
        state.eventReview.outcome = .finished
        let until = easyUntil(distance, raceDay: raceDay, calendar: calendar)
        var text = "Congratulations on finishing your \(distance.sentenceName)! Easy running only until \(CoachFormat.date(until, calendar: calendar)), then we build again."
        if meters != nil, let seconds, seconds > 0 {
            let date = run?.start ?? raceDay
            let monthStart = calendar.date(byAdding: .day, value: -28, to: date) ?? date
            let before = runs.filter { $0.id != run?.id && $0.start >= monthStart && $0.start < date }.reduce(0) { $0 + $1.meters } / 4
            let result = RaceResult(
                id: StableID.make("race-\(run?.id.uuidString ?? String(Int(raceDay.timeIntervalSince1970)))"),
                date: date,
                meters: distance.meters,
                seconds: seconds,
                source: .race,
                official: run == nil,
                course: state.intake.eventDetails?.course == .hilly ? .hilly : .flat,
                treadmill: run?.source == .treadmill,
                weeklyMetersBefore: before > 0 ? before : nil,
                runID: run?.id
            )
            let (updated, change) = PaceCalculator.recordResult(result, state: state, now: now, calendar: calendar)
            state = updated
            state.eventReview.raceResultID = result.id
            if change != .notUsed { text += " Your result has updated your paces." }
        }
        return CoachUpdate(state: state, notes: [CoachNote(.event, text)])
    }

    /// The EV-9 row recovery follows: the race distance, or for a DNF the distance run (under 10 km the 5K/10K
    /// row, 10 km to under 30 km the half's, 30 km or more the marathon's). Nil when the race didn't start: no
    /// recovery. Until the race is recorded it's the race distance, the cautious case.
    static func recoveryDistance(_ state: CoachState) -> RaceDistance? {
        switch state.eventReview.outcome {
        case .didNotStart:
            return nil
        case .didNotFinish:
            let run = state.eventReview.distanceRun ?? 0
            if run < 10_000 { return .tenK }
            return run < 30_000 ? .halfMarathon : .marathon
        case .finished, nil:
            return state.goal.distance
        }
    }

    /// EV-9's easy days after the race: 2-3 after a 5K or 10K, 7 after a half, and no hard work, leg strength or
    /// long run before day 14 after a marathon.
    static func easyDays(after distance: RaceDistance) -> Int {
        switch distance {
        case .mile, .fiveK, .tenK: 3
        case .halfMarathon: 7
        case .marathon: 14
        }
    }

    /// EV-9's recovery: a week after a 5K, 10K or half, and four after a marathon (two easy, then about 50% and
    /// 75% weeks). Then the plan is complete and the next goal is offered.
    static func recoveryDays(after distance: RaceDistance) -> Int {
        distance == .marathon ? 28 : 7
    }

    static func easyUntil(_ distance: RaceDistance, raceDay: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: easyDays(after: distance), to: raceDay) ?? raceDay
    }

    /// The day the race's recovery ends: race day itself when the race didn't start.
    static func recoveryEnd(_ state: CoachState, calendar: Calendar) -> Date? {
        guard let event = state.event else { return nil }
        let raceDay = calendar.startOfDay(for: event.raceDate)
        let days = recoveryDistance(state).map { recoveryDays(after: $0) } ?? 0
        return calendar.date(byAdding: .day, value: days, to: raceDay)
    }

    // MARK: "Did you race?"

    /// Applies "Did you race?" (EV-9); `DidYouRaceAnswer` says what each answer does. The caller re-plans the
    /// current week.
    static func answerDidYouRace(_ answer: DidYouRaceAnswer, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        guard state.event != nil else { return CoachUpdate(state: state) }
        var state = state
        state.eventReview.askedDidYouRace = true
        switch answer {
        case .recordedElsewhere(let meters, let seconds):
            return recordRace(meters: meters, seconds: seconds, run: nil, state: state, runs: runs, now: now, calendar: calendar)
        case .didNotStart:
            guard state.eventReview.outcome == nil else { return CoachUpdate(state: state) }
            state.eventReview.outcome = .didNotStart
            state.status = .stopped(reason: .didNotStart, on: now)
            if state.openInjuries.contains(where: { $0.level == .severe }) {
                // RC-1, AD-13c: the goal waits until the runner is ready.
                state.savedGoal = state.goal
                state.savedGoalEarliest = nil
            }
            let note = CoachNote(.event, "Races don't always happen, and that's OK. Pick a new date, or keep your fitness until you choose your next race.")
            return CoachUpdate(state: state, notes: [note], questions: [.nextGoal])
        case .raceMoved(let date):
            return moveRace(to: date, state: state, runs: runs, now: now, calendar: calendar)
        }
    }

    /// RC-10: a new race date. The check runs again, and the event's phases are placed back from the new race
    /// day with the buffer used so far and EF-3's and EF-9's decisions kept. A refused date changes nothing.
    static func moveRace(to date: Date, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        guard let old = state.event else { return CoachUpdate(state: state) }
        var goal = state.goal
        goal.eventDate = date
        let check = GoalChecker.recheck(goal, state: state, runs: runs, now: now, calendar: calendar)
        guard check.verdict != .refused else { return CoachUpdate(state: state, notes: [CoachNote(.event, check.message)]) }
        var state = state
        state.goal = goal
        state.intake.goal = goal
        var event = CoachEngine.eventState(
            raceDay: calendar.startOfDay(for: date),
            startDate: state.startDate,
            goal: goal,
            check: check,
            assessment: state.assessment,
            calendar: calendar
        )
        event.bufferUsed = min(old.bufferUsed, event.bufferWeeks)
        event.finishOnly = old.finishOnly
        event.walkShare = old.walkShare
        event.runWalkPattern = old.runWalkPattern
        event.finishRange = old.finishRange
        state.event = event
        state.eventReview.outcome = nil
        state.eventReview.raceRunID = nil
        state.eventReview.raceResultID = nil
        state.eventReview.distanceRun = nil
        state.eventReview.askedDidYouRace = false
        state.eventReview.timeGoal = check.timeGoal
        state.paces.racePace = check.racePace
        let note = CoachNote(.event, "Your race is now on \(CoachFormat.date(date, calendar: calendar)). \(check.message)")
        return CoachUpdate(state: state, notes: [note])
    }

    // MARK: "What next?"

    /// Applies "What next?" (BD-1g, SW-7c, EV-9); `NextGoalAnswer` says what each answer does. A new goal hands
    /// off within the plan (RC-12a); the caller re-plans the current week.
    static func answerNextGoal(_ answer: NextGoalAnswer, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        let goal: GoalChoice
        switch answer {
        case .maintain:
            return maintain(state)
        case .nextRung:
            guard let next = nextRung(after: state.goal) else {
                var update = maintain(state)
                update.notes = [CoachNote(.plan, "The marathon is the top rung. To run one, pick it as an event, and until then I'll keep your fitness where it is.")]
                return update
            }
            goal = next
        case .speedWork:
            goal = GoalChoice(flavor: .speedWork, distance: state.goal.distance)
        case .newGoal(let choice):
            goal = choice
        }
        let check = GoalChecker.recheck(goal, state: state, runs: runs, now: now, calendar: calendar)
        let startsLater = check.planStartsOn.map { $0 > calendar.startOfDay(for: now) } ?? false
        if check.verdict == .refused || startsLater {
            // RC-1, RC-12: the goal is kept with its date, and the current fitness meanwhile.
            var update = maintain(state)
            update.state.savedGoal = goal
            update.state.savedGoalEarliest = startsLater ? check.planStartsOn : check.savedGoalEarliest
            update.notes = [CoachNote(.plan, check.message)]
            return update
        }
        return handOff(to: goal, check: check, state: state, now: now, calendar: calendar)
    }

    /// Keep this distance or fitness (BD-1g, SW-7c, EV-9): the plan carries on, open-ended, at the current distance;
    /// Speed Work maintenance after Speed Work or a time goal, Build Distance maintenance otherwise.
    static func maintain(_ state: CoachState) -> CoachUpdate {
        var state = state
        let speed = state.goal.flavor == .speedWork || state.goal.hasTimeGoal
        let goal = GoalChoice(flavor: speed ? .speedWork : .buildDistance, distance: state.goal.distance, maintain: true)
        state.goal = goal
        state.intake.goal = goal
        state.event = nil
        state.status = .active
        let text = speed
            ? "Done: one quality session a week at your current level, and your weekly distance stays where it is."
            : "Done: no more distance added. Your weeks stay about where they are, with lighter weeks as before."
        return CoachUpdate(state: state, notes: [CoachNote(.plan, text)])
    }

    /// BD-1g's next rung: a run-walk rung's non-stop version, else the next distance. Nil after the marathon.
    static func nextRung(after goal: GoalChoice) -> GoalChoice? {
        if goal.runWalk { return GoalChoice(flavor: .buildDistance, distance: goal.distance) }
        guard let next = RaceDistance.allCases.first(where: { $0 > goal.distance }) else { return nil }
        return GoalChoice(flavor: .buildDistance, distance: next)
    }

    /// RC-12a's hand-off inside the plan: every derived value carries over (P-L30, W4max, V0, the anchor, tier and
    /// overlays, level, gate progress, open reports and gaps). The cycle starts with an N week once the current
    /// week ends, an event's phases are placed back from its race day from the next week, and the coach shows the
    /// new verdict.
    static func handOff(to goal: GoalChoice, check: GoalCheck, state: CoachState, now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        state.goal = goal
        state.intake.goal = goal
        state.status = .active
        state.insisted = false
        state.savedGoal = nil
        state.savedGoalEarliest = nil
        state.paces.racePace = check.racePace
        state.eventReview = EventReviewState()
        state.eventReview.timeGoal = check.timeGoal
        state.cycle.position = 0
        if goal.flavor == .event, let date = goal.eventDate {
            let next = state.weekStart(max(0, state.weekIndex(on: now, calendar: calendar) + 1), calendar: calendar)
            state.event = CoachEngine.eventState(
                raceDay: calendar.startOfDay(for: date),
                startDate: next,
                goal: goal,
                check: check,
                assessment: state.assessment,
                calendar: calendar
            )
        } else {
            state.event = nil
        }
        return CoachUpdate(state: state, notes: [CoachNote(.plan, check.message)])
    }
}
