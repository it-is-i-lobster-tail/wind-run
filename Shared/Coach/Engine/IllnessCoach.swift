//
//  IllnessCoach.swift
//  Wind Run
//

import Foundation

/// "Has it gone?" every 3 days with a head cold (AD-12).
enum HeadColdCheck: String, Codable, CaseIterable {
    case gone
    case stillThere
    case nowFever

    var name: String {
        switch self {
        case .gone: "Gone"
        case .stillThere: "Still there"
        case .nowFever: "Now a fever or below the neck"
        }
    }
}

/// An answer to one of the illness questions (AD-12).
enum IllnessAnswer: Codable, Hashable {
    /// "Just a head cold, or a fever or anything below the neck?"
    case kind(IllnessKind)
    case headCold(HeadColdCheck)
    /// On "Ready": "Have you felt back to normal for 2 full days?"
    case ready(Bool)
    /// Stage 2's next-day check: "Still feeling normal after yesterday's run?"
    case stillNormal(Bool)
    /// The runner feels ill again: back one stage (a relapse).
    case feelIllAgain
}

/// Illness and heat illness: the pause, the return stages and the weeks they shape (AD-12, AD-16, HL-19).
enum IllnessCoach {
    /// Marks a planning probe: the rules after this module shape the week, then the illness limits it.
    static let chainSentinel = "chain.illness"
    /// AD-12: a head cold is asked about again every 3 days.
    static let headColdCheckDays = 3
    /// AD-12 stage 3: 4 symptom-free days and 2 easy runs, the first run included.
    static let easySymptomFreeDays = 4
    static let easyRuns = 2
    /// AD-12 stage 4: no new longest run until 7 days after the first run.
    static let newLongestWaitDays = 7
    /// AD-16: an illness report makes the runner high-risk for heat for 10 days.
    static let heatRiskDays = 10
    /// AD-16: after a heat illness, 2 easy runs of 30 min or less.
    static let heatEasyRunSeconds: Double = 30 * 60

    // MARK: Reports and answers (AD-12)

    /// The runner says they're ill (AD-12). With no kind yet, head-cold rules apply until it's answered (AD-17).
    /// Saying so again while an episode is open adds to it: a fever moves a head cold to the no-running rules, and
    /// during the return it is a relapse, one stage back, or back to rest with a fever or anything below the neck
    /// (HL-19: no running).
    static func report(kind: IllnessKind?, bedBound: Bool, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        var notes: [CoachNote] = []
        settle(&state, now: now)
        let riskEnd = calendar.date(byAdding: .day, value: heatRiskDays, to: now) ?? now
        state.heat.highRiskUntil = max(state.heat.highRiskUntil ?? riskEnd, riskEnd)

        let position: Int
        if let active = state.illnesses.lastIndex(where: \.isActive) {
            position = active
            var episode = state.illnesses[position]
            if episode.kind == nil || kind == .feverOrBelowNeck { episode.kind = kind ?? episode.kind }
            episode.bedBound = episode.bedBound || bedBound
            state.illnesses[position] = episode
            switch episode.stage {
            case .headCold:
                if episode.kind == .feverOrBelowNeck { startRest(position, state: &state, now: now) }
            case .firstRun, .easy, .backToPlan:
                guard kind == .feverOrBelowNeck else {
                    notes += relapse(position, state: &state, now: now, calendar: calendar)
                    break
                }
                if ownsRamp(state.illnesses[position], state) { state.gap = nil }
                startRest(position, state: &state, now: now)
                state.illnesses[position].relapses += 1
                notes.append(CoachNote(.illness, "Sorry you're feeling ill again. With a fever or anything below the neck, no running for now. Tap 'Ready' once you've felt normal for 2 full days."))
            case .rest, .over:
                break
            }
        } else {
            var episode = IllnessEpisode(reportedAt: now, kind: kind, bedBound: bedBound)
            if episode.stage == .headCold { episode.nextCheck = calendar.date(byAdding: .day, value: headColdCheckDays, to: now) }
            state.illnesses.append(episode)
            position = state.illnesses.count - 1
        }
        InjuryCoach.syncPause(&state, now: now)
        let episode = state.illnesses[position]
        let questions: [CoachQuestion] = episode.kind == nil ? [.illnessKind(episodeID: episode.id)] : []
        return CoachUpdate(state: state, notes: notes, questions: questions)
    }

    static func answer(_ answer: IllnessAnswer, episodeID: UUID, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        guard let position = state.illnesses.firstIndex(where: { $0.id == episodeID }), state.illnesses[position].isActive else {
            return CoachUpdate(state: state)
        }
        var notes: [CoachNote] = []
        let episode = state.illnesses[position]

        switch answer {
        case .kind(let kind):
            guard episode.kind == nil else { break }
            state.illnesses[position].kind = kind
            if kind == .feverOrBelowNeck, episode.stage == .headCold { startRest(position, state: &state, now: now) }

        case .headCold(let check):
            guard episode.stage == .headCold else { break }
            switch check {
            case .gone:
                end(position, state: &state, now: now)
                notes.append(CoachNote(.illness, "Good to hear. Your usual plan is back."))
            case .stillThere:
                state.illnesses[position].nextCheck = calendar.date(byAdding: .day, value: headColdCheckDays, to: now)
            case .nowFever:
                state.illnesses[position].kind = .feverOrBelowNeck
                startRest(position, state: &state, now: now)
            }

        case .ready(let ready):
            guard episode.stage == .rest else { break }
            guard ready else {
                notes.append(CoachNote(.illness, "No rush. Tap 'Ready' again once you've felt normal for 2 full days."))
                break
            }
            // Stage 2: the 2 days the runner confirmed are the first symptom-free days.
            state.illnesses[position].symptomFreeSince = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: now))
            setStage(.firstRun, position, state: &state, now: now)
            notes.append(CoachNote(.illness, "Glad you're feeling better. We'll start with an easy 10-20 minutes."))

        case .stillNormal(let normal):
            guard episode.stage == .firstRun, let first = episode.firstRunAt else { break }
            if normal {
                state.illnesses[position].ramp = ramp(from: first, state: state, runs: runs, now: now, calendar: calendar)
                setStage(.easy, position, state: &state, now: now)
                advance(position, state: &state, now: now, calendar: calendar)
            } else {
                notes += relapse(position, state: &state, now: now, calendar: calendar)
            }

        case .feelIllAgain:
            notes += relapse(position, state: &state, now: now, calendar: calendar)
        }

        settle(&state, now: now)
        return CoachUpdate(state: state, notes: notes)
    }

    /// "Felt unwell in the heat" (AD-16): running pauses until the runner has felt normal for a full day, then 2
    /// easy runs of 30 min or less somewhere cool; the runner is high-risk for heat from then on. A pause for an
    /// injury, an illness or fatigue already covers the day off.
    static func reportHeatIllness(state: CoachState, now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        let again = !state.heat.illnessDates.isEmpty
        state.heat.illnessDates.append(now)
        state.heat.easyRunsLeft = 2
        state.heat.countedRunIDs = []
        if state.status.isActive { state.status = .paused(reason: .heat, since: now) }
        var text = "That sounds like the heat got to you. No running until you've felt normal for a full day, then two short easy runs somewhere cool."
        if again { text += " If this keeps happening, please talk to a doctor." }
        return CoachUpdate(state: state, notes: [CoachNote(.illness, text)])
    }

    // MARK: Runs and week ends

    /// A saved run moves the return stages and the heat-illness runs along. Each run counts once, however often
    /// it is reviewed.
    static func runLogged(_ run: LoggedRun, state: CoachState, now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        // AD-16: the 2 easy runs after a heat illness, once running is back.
        if state.heat.easyRunsLeft > 0, !state.status.isPaused, let last = state.heat.illnessDates.max(), run.start > last,
           !state.heat.countedRunIDs.contains(run.id) {
            state.heat.countedRunIDs.append(run.id)
            state.heat.easyRunsLeft -= 1
        }

        if let position = state.illnesses.lastIndex(where: \.isActive) {
            let episode = state.illnesses[position]
            switch episode.stage {
            case .firstRun, .easy:
                if run.start >= episode.stageStartedAt || run.start >= (episode.firstRunAt ?? .distantFuture),
                   !episode.runIDs.contains(run.id) {
                    state.illnesses[position].runIDs.append(run.id)
                    state.illnesses[position].easyRunsSinceFirst += 1
                    if episode.firstRunAt == nil { state.illnesses[position].firstRunAt = run.start }
                }
                advance(position, state: &state, now: now, calendar: calendar)
            case .headCold, .rest, .backToPlan, .over:
                break
            }
        }
        settle(&state, now: now)
        return CoachUpdate(state: state)
    }

    /// Week-end work: stage 3 moves on once its days are done, and the episode ends with its ramp (AD-12). For
    /// `CoachEngine.closeWeek`'s module steps.
    static func weekEnded(_ index: Int, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        restartRamp(after: index, state: &state, calendar: calendar)
        if let position = state.illnesses.lastIndex(where: \.isActive) {
            advance(position, state: &state, now: now, calendar: calendar)
        }
        settle(&state, now: now)
        return CoachUpdate(state: state)
    }

    // MARK: The weeks (AD-12, AD-16)

    /// The week while an illness or heat illness shapes it, or nil: the pause, the first run, the easy stage and the
    /// first days of the ramp; a head cold and the 2 easy runs after a heat illness limit the plan's own week.
    static func weekTargets(_ context: PlanningContext) -> WeekTargets? {
        let state = context.state
        guard !state.shownOnce.contains(chainSentinel) else { return nil }
        // The walk stage and the ladder plan their own weeks through a cold and the return (AD-12, AD-18).
        if LadderCoach.plansIllnessWeek(context) { return nil }
        var targets = state.activeIllness.flatMap { episodeTargets($0, context: context) }
        if state.heat.easyRunsLeft > 0, !state.status.isPaused {
            guard var week = targets ?? probe(context), week.runs > 0 else { return targets }
            week.quality = []
            week.strides = 0
            week.longRun = nil
            week.isNewLongest = false
            let cap = Load(heatEasyRunSeconds, in: .time, pace: context.easyPace ?? Scheduler.fallbackEasyPace)
            week.sessionCap = week.sessionCap.map { InjuryCoach.tighter($0, cap) } ?? cap
            let left = state.heat.easyRunsLeft == 1 ? "one more of them" : "two of them"
            week.notes.append(CoachNote(.illness, "Easy runs of 30 minutes or less, somewhere cool or indoors, because the heat got to you. Your usual runs come back after \(left)."))
            targets = week
        }
        return targets.map { InjuryCoach.unique(InjuryCoach.withoutStaleNotes($0)) }
    }

    /// The active episode's week (AD-12).
    static func episodeTargets(_ episode: IllnessEpisode, context: PlanningContext) -> WeekTargets? {
        let state = context.state
        let unit = context.unit
        let pace = context.easyPace ?? Scheduler.fallbackEasyPace
        switch episode.stage {
        case .rest:
            return .paused(notes: [CoachNote(.illness, "No running for now, because you're ill. Your plan is paused, not lost. Tap 'Ready' when you want to start back. If it drags on or keeps coming back, it's worth seeing a doctor.")])

        case .firstRun:
            // One run of 10-20 min at RPE ≤3, at most half the usual run, then the next-day check.
            let seconds = min(20 * 60, max(10 * 60, 0.5 * usualRunSeconds(context)))
            let run = Scheduler.amount(seconds: seconds, unit: unit, pace: pace)
            let done = episode.firstRunAt != nil
            let note = done
                ? "No more running until tomorrow's check, because your first run back comes before load rises."
                : "One easy run of \(Int((seconds / 60).rounded())) minutes, because you're getting over being ill."
            return WeekTargets(
                kind: .illnessReturn,
                volume: done ? 0 : run,
                runs: done ? 0 : 1,
                sessionCap: Load(run, in: unit, pace: pace),
                notes: [CoachNote(.illness, note)]
            )

        case .easy:
            // Easy runs only, no longer than usual; their load may rise from the first run.
            let usualWeek = state.cycle.lastLoadingVolume > 0 ? state.cycle.lastLoadingVolume : state.v0
            let runs = max(1, min(state.cycle.runsPerWeek, state.assessment.runsCap))
            return WeekTargets(
                kind: .illnessReturn,
                volume: 0.75 * usualWeek,
                runs: runs,
                sessionCap: Load(usualRunSeconds(context), in: .time, pace: pace),
                notes: [CoachNote(.illness, "Easy runs only for now, with no speed work or long run, because you're getting over being ill.")]
            )

        case .backToPlan:
            // AD-10's ramp shapes the week. A long run before the 7th day after the first run is no new longest run:
            // it and every other run stay within the longest run since the first run back. Such a week isn't a ramp
            // week: the ramp starts after it (`restartRamp`), so its first long run is the tier's share.
            guard let first = episode.firstRunAt, ownsRamp(episode, state),
                  let end = context.calendar.date(byAdding: .day, value: newLongestWaitDays, to: context.calendar.startOfDay(for: first)),
                  context.weekStart < end,
                  var week = probe(context), week.runs > 0,
                  let long = Scheduler.layout(week, context: context).sessions.first(where: { $0.kind == .long }),
                  let longDay = context.calendar.date(byAdding: .day, value: long.dayOffset, to: context.weekStart), longDay < end else { return nil }
            let longest = context.sessions
                .filter { $0.start >= first && $0.start < context.now }
                .reduce(Load.zero) { Load(meters: max($0.meters, $1.meters), seconds: max($0.seconds, $1.seconds)) }
            guard longest.amount(in: unit) > 0 else { return nil }
            week.sessionCap = week.sessionCap.map { InjuryCoach.tighter($0, longest) } ?? longest
            week.isNewLongest = false
            if week.kind == .ramp {
                // The ramp's opening line waits for its first week.
                week.kind = .illnessReturn
                week.notes.removeAll { $0.topic == .outcome }
            }
            week.notes.append(CoachNote(.illness, "Back to your plan, easing in. Until a week after your first run back, no run is longer than your longest since then."))
            return week

        case .headCold:
            // Easy runs no longer than usual, no Q, test or long-run step. A loading or HOLD week becomes an EASE week,
            // 10% lighter (AD-5); lighter and structured weeks keep their own volume.
            guard var week = probe(context), week.runs > 0 else { return nil }
            week.quality = []
            week.strides = 0
            week.isNewLongest = false
            if week.kind == .loading || week.kind == .hold {
                week.kind = .ease
                week.cycleWeek = nil
                week.volume *= 0.9
            }
            let usual = state.cycle.lastLoadingLongRun.amount(in: unit) > 0 ? state.cycle.lastLoadingLongRun : context.previousWeek?.plan.longRun
            if let long = week.longRun, let usual, usual.amount(in: unit) > 0 { week.longRun = long.capped(at: usual) }
            week.notes.append(CoachNote(.illness, "Easy runs only while your cold lasts, with no speed work and nothing longer than usual. Stop if it feels worse."))
            return week

        case .over:
            return nil
        }
    }

    /// The plan's own week, from the rules after this module.
    static func probe(_ context: PlanningContext) -> WeekTargets? {
        var context = context
        context.state.shownOnce.insert(chainSentinel)
        let week = WeekPlanner.weekTargets(context).0
        return week.kind == .paused ? nil : week
    }

    /// The runner's usual easy run in seconds: the middle easy run of the latest week that had one, else the usual
    /// week over its runs.
    static func usualRunSeconds(_ context: PlanningContext) -> Double {
        let state = context.state
        let pace = context.easyPace ?? Scheduler.fallbackEasyPace
        let week = state.weeks.last { $0.plan.index < context.weekIndex && $0.plan.sessions.contains { $0.kind == .easy } }?.plan
        let easy = (week?.sessions ?? [])
            .filter { $0.kind == .easy }
            .map { $0.target.seconds > 0 ? $0.target.seconds : $0.target.meters / 1_000 * pace }
            .sorted()
        if !easy.isEmpty { return easy[easy.count / 2] }
        let usual = state.cycle.lastLoadingVolume > 0 ? state.cycle.lastLoadingVolume : state.v0
        let runs = Double(max(1, state.cycle.runsPerWeek))
        return context.unit == .time ? usual / runs : usual / runs / 1_000 * pace
    }

    /// AD-5's illness rows, or nil.
    static func outcome(_ state: CoachState) -> (WeekOutcome, OutcomeReason)? {
        if isHeatPaused(state) { return (.pause, .heatIllness) }
        switch state.activeIllness?.stage {
        case .rest?: return (.pause, .illness)
        case .headCold?: return (.ease, .headCold)
        default: return nil
        }
    }

    /// Questions the active episode is waiting on (AD-12, AD-17).
    static func questions(_ state: CoachState, now: Date, calendar: Calendar) -> [CoachQuestion] {
        guard let episode = state.activeIllness else { return [] }
        var questions: [CoachQuestion] = []
        if episode.kind == nil { questions.append(.illnessKind(episodeID: episode.id)) }
        switch episode.stage {
        case .headCold:
            if let next = episode.nextCheck, now >= next { questions.append(.illnessGone(episodeID: episode.id)) }
        case .firstRun:
            if let first = episode.firstRunAt, let due = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: first)), now >= due {
                questions.append(.stillNormal(episodeID: episode.id))
            }
        case .rest, .easy, .backToPlan, .over:
            break
        }
        return questions
    }

    // MARK: Rules other modules read (AD-10, HL-19)

    /// The illness sets the way back while it rests, takes its first run or runs easy: its own ramp replaces the
    /// one a gap would start (AD-12 stage 4).
    static func setsWayBack(_ state: CoachState) -> Bool {
        switch state.activeIllness?.stage {
        case .rest?, .firstRun?, .easy?: true
        default: false
        }
    }

    /// HL-19: a fever or below-the-neck illness now, or within 48 h before the start: don't start.
    static func raceStartBlocked(_ state: CoachState, raceStart: Date) -> Bool {
        let limit = raceStart.addingTimeInterval(-48 * 3_600)
        return state.illnesses.contains { episode in
            guard episode.kind == .feverOrBelowNeck, episode.reportedAt <= raceStart else { return false }
            guard episode.stage != .rest, let free = episode.symptomFreeSince else { return episode.isActive || (episode.endedAt ?? .distantPast) > limit }
            return free > limit
        }
    }

    // MARK: Stages (AD-12)

    static func isHeatPaused(_ state: CoachState) -> Bool {
        if case .paused(.heat, _) = state.status { return true }
        return false
    }

    static func setStage(_ stage: IllnessStage, _ position: Int, state: inout CoachState, now: Date) {
        state.illnesses[position].stage = stage
        state.illnesses[position].stageStartedAt = now
    }

    /// Stage 1: no running until "Ready".
    static func startRest(_ position: Int, state: inout CoachState, now: Date) {
        setStage(.rest, position, state: &state, now: now)
        state.illnesses[position].nextCheck = nil
        state.illnesses[position].symptomFreeSince = nil
        state.illnesses[position].firstRunAt = nil
        state.illnesses[position].easyRunsSinceFirst = 0
        state.illnesses[position].runIDs = []
        state.illnesses[position].ramp = nil
    }

    static func end(_ position: Int, state: inout CoachState, now: Date) {
        setStage(.over, position, state: &state, now: now)
        state.illnesses[position].endedAt = now
    }

    /// The runner feels ill again: back one stage, which starts over; the symptom-free days count again from the
    /// next day (AD-12).
    static func relapse(_ position: Int, state: inout CoachState, now: Date, calendar: Calendar) -> [CoachNote] {
        let episode = state.illnesses[position]
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        switch episode.stage {
        case .firstRun:
            startRest(position, state: &state, now: now)
        case .easy:
            setStage(.firstRun, position, state: &state, now: now)
            state.illnesses[position].firstRunAt = nil
            state.illnesses[position].easyRunsSinceFirst = 0
            state.illnesses[position].runIDs = []
            state.illnesses[position].ramp = nil
            state.illnesses[position].symptomFreeSince = tomorrow
        case .backToPlan:
            if ownsRamp(episode, state) { state.gap = nil }
            setStage(.easy, position, state: &state, now: now)
            state.illnesses[position].easyRunsSinceFirst = 0
            state.illnesses[position].runIDs = []
            state.illnesses[position].symptomFreeSince = tomorrow
        case .headCold, .rest, .over:
            return []
        }
        state.illnesses[position].relapses += 1
        return [CoachNote(.illness, "Sorry you're feeling ill again. We'll go back one step and start it over.")]
    }

    /// Stage 3 to stage 4: 4 symptom-free days and 2 easy runs, the first run included, start the ramp set at the
    /// next-day check. Its P-L30 counts from here, so the short runs of stages 2 and 3 don't hold its long run back
    /// (AD-10: only post-return runs).
    static func advance(_ position: Int, state: inout CoachState, now: Date, calendar: Calendar) {
        let episode = state.illnesses[position]
        guard episode.stage == .easy, episode.easyRunsSinceFirst >= easyRuns, let free = episode.symptomFreeSince,
              (calendar.dateComponents([.day], from: free, to: calendar.startOfDay(for: now)).day ?? 0) >= easySymptomFreeDays else { return }
        // Walk-stage and ladder runners have no AD-10 ramp: the ladder's own rows set the way back (AD-18), so the
        // illness ends here.
        if state.ladder?.isActive == true {
            end(position, state: &state, now: now)
            return
        }
        guard var ramp = episode.ramp else { return }
        setStage(.backToPlan, position, state: &state, now: now)
        ramp.startedAt = now
        state.illnesses[position].ramp = ramp
        state.gap = ramp
    }

    /// A stage-4 week that kept its long run back (no new longest run until 7 days after the first run) wasn't a ramp
    /// week, so the review left the ramp as it was. P-L30 counts from the next week, which starts the ramp with the
    /// tier's long run (AD-10, AD-12).
    static func restartRamp(after index: Int, state: inout CoachState, calendar: Calendar) {
        guard let position = state.illnesses.lastIndex(where: \.isActive), state.illnesses[position].stage == .backToPlan,
              ownsRamp(state.illnesses[position], state),
              state.weeks.first(where: { $0.plan.index == index })?.plan.kind == .illnessReturn,
              var ramp = state.gap else { return }
        let weekEnd = state.weekStart(index + 1, calendar: calendar)
        guard weekEnd > ramp.startedAt else { return }
        ramp.startedAt = weekEnd
        state.illnesses[position].ramp = ramp
        state.gap = ramp
    }

    /// Whether the plan's ramp is this episode's stage-4 ramp.
    static func ownsRamp(_ episode: IllnessEpisode, _ state: CoachState) -> Bool {
        guard let ramp = state.gap, let own = episode.ramp else { return false }
        return ramp.startedAt == own.startedAt
    }

    /// Stage 4's ramp: AD-10's for the days from the last qualifying run to the first run back, at least G1 after a
    /// fever or a bed-bound illness. Its reference comes from the weeks before the illness.
    static func ramp(from first: Date, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> GapRamp {
        let sessions = LoadMetrics.sessions(from: runs)
        let daysOff = LoadMetrics.daysSinceQualifyingRun(at: first, sessions: sessions, usualEasy: nil, calendar: calendar)
            ?? (calendar.dateComponents([.day], from: calendar.startOfDay(for: state.startDate), to: calendar.startOfDay(for: first)).day ?? 0)
        return WeeklyReviewer.startRamp(daysOff: daysOff, usualEasy: nil, state: state, runs: runs, weekEnd: first, now: now, calendar: calendar)
    }

    /// The episode ends with its ramp (AD-12 stage 4), and the plan's status follows the illness.
    static func settle(_ state: inout CoachState, now: Date) {
        if let position = state.illnesses.lastIndex(where: \.isActive), state.illnesses[position].stage == .backToPlan,
           !ownsRamp(state.illnesses[position], state) {
            end(position, state: &state, now: now)
        }
        InjuryCoach.syncPause(&state, now: now)
    }
}
