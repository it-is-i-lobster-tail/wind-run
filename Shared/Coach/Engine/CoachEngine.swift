//
//  CoachEngine.swift
//  Wind Run
//

import Foundation

/// A prompt to open one of the runner's own screens, from a routed answer (AD-9, AD-10, AD-11).
enum CoachRoute: String, Codable, Hashable {
    /// Open Report injury.
    case reportInjury
    /// Ask AD-3's wellness questions now.
    case wellnessQuestions
    /// Open Life happens on "Busy".
    case lifeHappensBusy
    /// Open Life happens on "Travelling".
    case lifeHappensTravel
}

/// "Why did you miss them?" (AD-9) and "Everything OK?" (AD-9's dip check), and AD-10's two-drops question.
enum MissedRunsReason: String, Codable, CaseIterable {
    case busy
    case travel
    case sick
    case injured
    case wornOut
    case fine
    case other

    var name: String {
        switch self {
        case .busy: "Busy"
        case .travel: "Travel"
        case .sick: "Sick"
        case .injured: "Injured"
        case .wornOut: "Worn out"
        case .fine: "Fine"
        case .other: "Other"
        }
    }
}

/// Answers to the coach's simpler questions.
enum CoachAnswer: Codable, Hashable {
    /// RB-7: "Want next week a quarter lighter?"
    case lighterWeek(Bool)
    /// CL-4: the next level, offered once.
    case levelUp(Bool)
    /// AD-9 missed runs, AD-9 dip check, AD-10 two ramp drops.
    case missedRuns(MissedRunsReason)
    case dipCheck(MissedRunsReason)
    case rampDrops(MissedRunsReason)
    /// AD-9: "Move Sunday's long run to Tuesday?"
    case moveKeySession(sessionID: UUID, toDay: Int, accept: Bool)
    /// AD-18: "Want to pick up one step easier?"
    case ladderEasierRestart(Bool)
}

/// The coach's entry points. Every call is pure: it takes the plan's state, the runner's logged runs, the
/// time and a calendar, and returns the new state with what to say and what to ask. The app stores the state
/// and calls `refresh` at app open, after each saved run and when the day changes.
enum CoachEngine {
    // MARK: Intake

    /// The intake screens that apply to these answers, in order.
    static func intakeSteps(_ intake: CoachIntake) -> [IntakeStep] {
        intake.steps
    }

    /// Tier, overlays, risk score, recovery tier, the levels on offer and the starting numbers.
    static func assess(_ intake: CoachIntake, now: Date, calendar: Calendar) -> RunnerAssessment {
        RunnerAssessor.assess(intake, now: now, calendar: calendar)
    }

    /// The realism check for a goal at a level (RC-1 to RC-9).
    static func checkGoal(_ goal: GoalChoice, intake: CoachIntake, level: CommitmentLevel, now: Date, calendar: Calendar) -> GoalCheck {
        let assessment = RunnerAssessor.assess(intake, now: now, calendar: calendar)
        let paces = PaceCalculator.initialPaces(intake, now: now, calendar: calendar)
        return GoalChecker.check(goal, intake: intake, assessment: assessment, paces: paces, level: min(level, assessment.levels.ceiling), now: now, calendar: calendar)
    }

    /// Builds the plan and its first week. `insisted` is the runner's "I understand this isn't recommended" (RC-9).
    static func startPlan(
        intake: CoachIntake,
        goal: GoalChoice,
        level: CommitmentLevel,
        insisted: Bool = false,
        runs: [LoggedRun],
        now: Date,
        calendar: Calendar
    ) -> CoachUpdate {
        var intake = intake
        intake.goal = goal
        let assessment = RunnerAssessor.assess(intake, now: now, calendar: calendar)
        let level = min(level, assessment.levels.ceiling)
        intake.level = level
        var paces = PaceCalculator.initialPaces(intake, now: now, calendar: calendar)
        let check = GoalChecker.check(goal, intake: intake, assessment: assessment, paces: paces, level: level, now: now, calendar: calendar)
        if goal.hasTimeGoal, let forecast = check.forecast, check.timeGoal?.verdict != .unlikely {
            paces.racePace = forecast.pace
        }
        let today = calendar.startOfDay(for: now)

        // An event plan's weeks end on race day (EV-1), so the first week may have started before today. When
        // fewer than 3 of its days, or none of the runner's run days, are left, the plan starts the next week.
        var startDate = today
        var event: EventState?
        if goal.flavor == .event, let eventDate = goal.eventDate {
            let raceDay = calendar.startOfDay(for: eventDate)
            let days = calendar.dateComponents([.day], from: today, to: raceDay).day ?? 0
            let weeks = max(0, Int((Double(days - 6) / 7).rounded(.up)))
            startDate = calendar.date(byAdding: .day, value: -6 - 7 * weeks, to: raceDay) ?? today
            let daysLeft = 7 - (calendar.dateComponents([.day], from: startDate, to: today).day ?? 0)
            let runDayLeft = (0 ..< daysLeft).contains { offset in
                guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return false }
                return intake.runDays.isEmpty || intake.runDays.contains(Weekday(of: day, calendar: calendar))
            }
            if daysLeft < 3 || !runDayLeft, let later = calendar.date(byAdding: .day, value: 7, to: startDate), later < raceDay {
                startDate = later
            }
            event = eventState(raceDay: raceDay, startDate: startDate, goal: goal, check: check, assessment: assessment, calendar: calendar)
        }

        let start = assessment.start
        var state = CoachState(
            rulesVersion: CoachState.currentRulesVersion,
            intake: intake,
            goal: goal,
            insisted: insisted,
            savedGoal: nil,
            startDate: startDate,
            status: .active,
            level: level,
            levelChanges: [],
            assessment: assessment,
            paces: paces,
            v0: start.v0,
            weeks: [],
            cycle: CycleState(runsPerWeek: start.runsPerWeek, lastLoadingVolume: start.v0, lastLoadingLongRun: start.planningLongest),
            quality: QualityState(),
            ladder: assessment.starterEntry.map(LadderCoach.initialState(for:)),
            gap: nil,
            fatigue: FatigueState(),
            event: event,
            injuries: [],
            illnesses: [],
            lifeEvents: [],
            otherSessions: [],
            morningChecks: [],
            readiness: [],
            heat: HeatState(),
            runReview: RunReviewState(),
            eventReview: EventReviewState(),
            shownOnce: []
        )
        state.createdAt = now
        if start.currentQ > 0, QualityPlanner.gateBlocker(state: state, runs: runs, now: now, calendar: calendar) == nil {
            state.quality.gateMetOn = now
        }
        var notes = [CoachNote(.safety, SafetyText.safetyLine)]
        if insisted { notes.append(CoachNote(.plan, "You chose this goal against my advice. I'll keep every safety limit, and I'll tell you each week how it's going.")) }
        let update = refresh(state: state, runs: runs, now: now, calendar: calendar)
        notes += update.notes
        return CoachUpdate(state: update.state, notes: notes, questions: update.questions)
    }

    /// EV-1's phase dates, placed backward from race day.
    static func eventState(raceDay: Date, startDate: Date, goal: GoalChoice, check: GoalCheck, assessment: RunnerAssessment, calendar: Calendar) -> EventState {
        let taperStart = calendar.date(byAdding: .day, value: -(goal.distance.taperDays - 1), to: raceDay) ?? raceDay
        let weeksBeforeTaper = max(0, (calendar.dateComponents([.day], from: startDate, to: taperStart).day ?? 0) / 7)
        let calibration = assessment.start.calibrates ? Progression.calibrationWeeks : 0
        let speedBlock = goal.hasTimeGoal ? Progression.speedBlockWeeks : 0
        let feasibility = check.feasibility
        let pathWeeks = max(0, (feasibility?.earliestWeeks ?? 0) - calibration - speedBlock - Progression.taperWeeks(for: goal.distance) - 6)
        let spare = weeksBeforeTaper - calibration - speedBlock - pathWeeks
        let specific = min(weeksBeforeTaper, spare >= 6 ? 6 : max(4, spare))
        let specificStart = calendar.date(byAdding: .day, value: -7 * specific, to: taperStart) ?? taperStart
        var speedStart: Date?
        if speedBlock > 0, weeksBeforeTaper - specific - speedBlock >= calibration + 3 {
            speedStart = calendar.date(byAdding: .day, value: -7 * speedBlock, to: specificStart)
        }
        var event = EventState(
            raceDate: raceDay,
            taperStart: taperStart,
            specificStart: specificStart,
            speedBlockStart: speedStart,
            bufferWeeks: feasibility?.bufferWeeks ?? 0,
            status: check.verdict == .green ? .onTrack : .goalAtRisk
        )
        event.cutoffRisk = check.cutoffAtRisk
        return event
    }

    // MARK: Every day

    /// Brings the plan up to date: matches runs, closes finished weeks with their review, plans the current week,
    /// and lists what the coach is waiting on. Call at app open, after each saved run and when the day changes.
    static func refresh(state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = RunReviewer.syncMatches(state, runs: runs, now: now, calendar: calendar)
        var notes: [CoachNote] = []
        var questions: [CoachQuestion] = []
        switch state.status {
        case .complete, .stopped:
            return CoachUpdate(state: state)
        case .active, .paused:
            break
        }

        for run in runs.sorted(by: { $0.start < $1.start }) where run.start >= state.startDate && !state.runReview.reviewedRunIDs.contains(run.id) {
            state = RunReviewer.review(run, state: state, runs: runs, now: now, calendar: calendar).0
        }

        let today = state.weekIndex(on: now, calendar: calendar)
        var index = state.weeks.last?.plan.index ?? -1
        while index < today {
            if let last = state.weeks.last, last.review == nil {
                let update = closeWeek(last.plan.index, state: state, runs: runs, now: now, calendar: calendar)
                state = update.state
                notes += update.notes
                questions += update.questions
            }
            index += 1
            state = WeekPlanner.planWeek(index, state: state, runs: runs, now: now, calendar: calendar)
            // A session matched before the week was planned (a run on the plan's first day) is matched now.
            for run in runs where run.start >= state.weekStart(index, calendar: calendar) {
                state = RunReviewer.review(run, state: state, runs: runs, now: now, calendar: calendar).0
            }
            if index == today, let week = state.weeks.last?.plan {
                notes += week.notes
            }
        }
        state = markMissed(state, now: now, calendar: calendar)
        questions += pendingQuestions(state, runs: runs, now: now, calendar: calendar)
        return CoachUpdate(state: state, notes: unique(notes), questions: unique(questions))
    }

    /// A finished week: its review, then each module's week-end step.
    static func closeWeek(_ index: Int, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var update = WeeklyReviewer.review(week: index, state: state, runs: runs, now: now, calendar: calendar)
        for step in [InjuryCoach.weekEnded, LadderCoach.weekEnded, EventReviewer.weekEnded] {
            let next = step(index, update.state, runs, now, calendar)
            update = CoachUpdate(state: next.state, notes: update.notes + next.notes, questions: update.questions + next.questions)
        }
        return update
    }

    /// Reviews a saved run, then brings the plan up to date. `runs` includes the new run. Calling it again for
    /// the same run (after its check-in) updates the review without counting the run twice.
    static func logRun(_ run: LoggedRun, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> (CoachUpdate, RunReview) {
        var runs = runs
        if !runs.contains(where: { $0.id == run.id }) { runs.append(run) }
        let refreshed = refresh(state: state, runs: runs, now: now, calendar: calendar)
        var (state, review) = RunReviewer.review(run, state: refreshed.state, runs: runs, now: now, calendar: calendar)
        var questions = review.questions
        var notes = review.notes
        var modules = [IllnessCoach.runLogged, InjuryCoach.runLogged, LadderCoach.runLogged]
        if case .planned(let sessionID) = review.match, let (week, session) = locate(sessionID, in: state),
           state.weeks[week].plan.sessions[session].kind == .race {
            modules.append(EventReviewer.raceLogged)
        }
        for module in modules {
            let update = module(run, state, now, calendar)
            state = update.state
            questions += update.questions
            notes += update.notes
        }
        if let checkIn = run.checkIn {
            switch checkIn.effectiveWhatHappened {
            case .unwellInHeat? where !state.heat.illnessDates.contains(where: { $0 >= run.start }):
                let heat = IllnessCoach.reportHeatIllness(state: state, now: now, calendar: calendar)
                state = heat.state
                notes += heat.notes
                notes.append(CoachNote(.safety, SafetyText.heatLines))
            case .somethingHurt? where !state.injuries.contains(where: { $0.runID == run.id }):
                questions.append(.reportInjury(origin: .runSummary, runID: run.id))
            case .feltIll?:
                if state.activeIllness == nil {
                    let ill = IllnessCoach.report(kind: nil, bedBound: false, state: state, runs: runs, now: now, calendar: calendar)
                    state = ill.state
                    questions += ill.questions
                }
            default:
                break
            }
        }
        state = replanCurrentWeek(state, runs: runs, now: now, calendar: calendar)
        questions += refreshed.questions
        notes += refreshed.notes
        return (CoachUpdate(state: state, notes: unique(notes), questions: unique(questions)), review)
    }

    // MARK: Check-ins

    /// The weekly check-in (AD-3) for plan week `week`. A check-in that comes after the week was reviewed
    /// reviews it again, as long as the next week has no run in it yet.
    static func submitWeeklyCheckIn(_ checkIn: WeeklyCheckIn, week: Int, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        guard let position = state.weeks.firstIndex(where: { $0.plan.index == week }) else { return CoachUpdate(state: state) }
        state.weeks[position].checkIn = checkIn
        state.otherSessions += checkIn.otherSessions.filter { session in !state.otherSessions.contains { $0.id == session.id } }
        var notes: [CoachNote] = []
        var questions: [CoachQuestion] = []

        if checkIn.ill == true, !state.illnesses.contains(where: { $0.reportedAt >= state.weeks[position].plan.start }) {
            let ill = IllnessCoach.report(kind: nil, bedBound: false, state: state, runs: runs, now: now, calendar: calendar)
            state = ill.state
            questions += ill.questions
            state.heat.highRiskUntil = calendar.date(byAdding: .day, value: 10, to: now)
        }

        if state.weeks[position].review != nil, let next = state.weeks.firstIndex(where: { $0.plan.index == week + 1 }),
           !state.weeks[next].plan.sessions.contains(where: { if case .done = $0.status { return true } else { return false } }) {
            let review = closeWeek(week, state: state, runs: runs, now: now, calendar: calendar)
            state = review.state
            notes += review.notes
            questions += review.questions
            // The next week is planned again from the new review, not from the first one.
            state.weeks[next].planBaseline = nil
            state = WeekPlanner.planWeek(week + 1, state: state, runs: runs, now: now, calendar: calendar)
            notes += state.weeks.first { $0.plan.index == week + 1 }?.plan.notes ?? []
        }
        let refreshed = refresh(state: state, runs: runs, now: now, calendar: calendar)
        return CoachUpdate(state: refreshed.state, notes: unique(notes + refreshed.notes), questions: unique(questions + refreshed.questions))
    }

    /// The optional next-morning check (AD-2).
    static func submitMorningCheck(_ check: MorningCheck, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        state.morningChecks.append(check)
        return CoachUpdate(state: state)
    }

    /// The pre-session check (RB-8), with the heat answer when there's no weather source (AD-16).
    static func submitReadiness(_ answer: ReadinessAnswer, heat: HeatAnswer?, sessionID: UUID, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        state.readiness.append(ReadinessRecord(date: now, sessionID: sessionID, answer: answer, heat: heat))
        var notes: [CoachNote] = []
        var questions: [CoachQuestion] = []
        guard let (weekPosition, sessionPosition) = locate(sessionID, in: state) else { return CoachUpdate(state: state) }
        var session = state.weeks[weekPosition].plan.sessions[sessionPosition]
        let name = session.kind.name.lowercased()

        switch answer {
        case .goodToGo:
            break
        case .belowNormal:
            if session.kind != .race {
                session.madeEasy = .readiness
                session.effort = .easy
                session.blocks = []
                notes.append(CoachNote(.plan, "Let's make today an easy run of the same length, or move your \(name) by a day or two. Nothing to make up."))
            }
        case .unwell:
            let ill = IllnessCoach.report(kind: nil, bedBound: false, state: state, runs: runs, now: now, calendar: calendar)
            state = ill.state
            questions += ill.questions
        }

        // AD-16: heat tiers without a weather source.
        if let heat, answer != .unwell {
            let highRisk = state.heat.isHighRisk(on: now)
            let tier = min(3, heat.tier + (highRisk ? 1 : 0))
            switch tier {
            case 2:
                if session.isQuality, var dose = session.dose, !dose.continuous {
                    dose.reps = max(1, Int((Double(dose.reps) * 2 / 3).rounded()))
                    session.dose = dose
                    notes.append(CoachNote(.plan, "It's forecast hot at your run time. Move today's \(name) indoors or to a cooler hour, or do a third fewer reps."))
                } else if session.kind == .long {
                    session.target = session.target.scaled(by: 0.75)
                    notes.append(CoachNote(.plan, "It's hot, so today's long run is a quarter shorter. Run by effort and sip if you're thirsty."))
                }
            case 3:
                if session.isQuality || session.kind == .long {
                    session.madeEasy = .readiness
                    session.effort = .easy
                    session.blocks = []
                    session.target = session.target.capped(at: Load(meters: 0, seconds: 30 * 60))
                    notes.append(CoachNote(.plan, "Too hot for a long run or hard session outside today. Try the treadmill, a bike or swim, or an easy 30 minutes."))
                } else {
                    notes.append(CoachNote(.plan, "Too hot to run outside safely today. Try the treadmill, a bike or a swim, or move your run to a cooler day."))
                }
            default:
                break
            }
            if tier >= 1 { notes.append(CoachNote(.safety, SafetyText.heatLines)) }
        }
        state.weeks[weekPosition].plan.sessions[sessionPosition] = session
        return CoachUpdate(state: state, notes: notes, questions: questions)
    }

    // MARK: Injury (AD-13, AD-14)

    static func reportInjury(level: InjuryLevel, area: InjuryArea?, origin: InjuryOrigin, runID: UUID?, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        let update = InjuryCoach.report(level: level, area: area, origin: origin, runID: runID, state: state, runs: runs, now: now, calendar: calendar)
        return replanned(update, runs: runs, now: now, calendar: calendar)
    }

    static func answerInjury(_ answer: InjuryAnswer, reportID: UUID, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        let update = InjuryCoach.answer(answer, reportID: reportID, state: state, runs: runs, now: now, calendar: calendar)
        return replanned(update, runs: runs, now: now, calendar: calendar)
    }

    static func setRecoveryPlan(_ settings: RecoveryPlanSettings, reportID: UUID, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        let update = InjuryCoach.setRecoveryPlan(settings, reportID: reportID, state: state, runs: runs, now: now, calendar: calendar)
        return replanned(update, runs: runs, now: now, calendar: calendar)
    }

    static func setReturn(_ settings: ReturnSettings, reportID: UUID, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        let update = InjuryCoach.setReturn(settings, reportID: reportID, state: state, runs: runs, now: now, calendar: calendar)
        return replanned(update, runs: runs, now: now, calendar: calendar)
    }

    /// The weeks a recovery plan would give, for the recovery plan screen.
    static func previewRecovery(_ settings: RecoveryPlanSettings, reportID: UUID, state: CoachState) -> [RecoveryWeekPreview] {
        InjuryCoach.previewRecovery(settings, reportID: reportID, state: state)
    }

    // MARK: Illness and life (AD-11, AD-12, AD-16)

    static func reportIllness(kind: IllnessKind?, bedBound: Bool = false, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var update = IllnessCoach.report(kind: kind, bedBound: bedBound, state: state, runs: runs, now: now, calendar: calendar)
        update.state.heat.highRiskUntil = calendar.date(byAdding: .day, value: 10, to: now)
        return replanned(update, runs: runs, now: now, calendar: calendar)
    }

    static func answerIllness(_ answer: IllnessAnswer, episodeID: UUID, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        let update = IllnessCoach.answer(answer, episodeID: episodeID, state: state, runs: runs, now: now, calendar: calendar)
        return replanned(update, runs: runs, now: now, calendar: calendar)
    }

    /// "Felt unwell in the heat", reported at any time (AD-16).
    static func reportHeatIllness(state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        let update = IllnessCoach.reportHeatIllness(state: state, now: now, calendar: calendar)
        return replanned(update, runs: runs, now: now, calendar: calendar)
    }

    /// "Life happens" (AD-11). Sick goes to the illness question; injured opens Report injury.
    static func addLifeEvent(_ event: LifeEvent, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        state.lifeEvents.append(event)
        var questions: [CoachQuestion] = []
        if event.kind == .sick {
            let ill = IllnessCoach.report(kind: nil, bedBound: false, state: state, runs: runs, now: now, calendar: calendar)
            state = ill.state
            questions += ill.questions
        }
        return replanned(CoachUpdate(state: state, questions: questions), runs: runs, now: now, calendar: calendar)
    }

    /// "Back to normal".
    static func endLifeEvent(id: UUID, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        guard let position = state.lifeEvents.firstIndex(where: { $0.id == id }) else { return CoachUpdate(state: state) }
        state.lifeEvents[position].endedAt = now
        return replanned(CoachUpdate(state: state), runs: runs, now: now, calendar: calendar)
    }

    // MARK: Answers to the coach's questions

    /// The words on a question's card: what the coach asks and the answers to tap.
    static func prompt(for question: CoachQuestion, state: CoachState, calendar: Calendar) -> CoachPrompt {
        CoachPrompts.prompt(for: question, state: state, calendar: calendar)
    }

    static func answer(_ answer: CoachAnswer, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> (CoachUpdate, CoachRoute?) {
        var state = state
        var notes: [CoachNote] = []
        switch answer {
        case .lighterWeek(let accept):
            guard accept, let position = currentWeekPosition(state, now: now, calendar: calendar) else { return (CoachUpdate(state: state), nil) }
            let today = dayOffset(state.weeks[position].plan, now: now, calendar: calendar)
            for index in state.weeks[position].plan.sessions.indices where state.weeks[position].plan.sessions[index].dayOffset >= today && state.weeks[position].plan.sessions[index].status.isPlanned {
                let session = state.weeks[position].plan.sessions[index]
                guard session.kind.isRun, !session.isKey else { continue }
                let shorter = session.target.scaled(by: 0.75)
                state.weeks[position].plan.sessions[index].target = Load(
                    meters: shorter.meters,
                    seconds: max(shorter.seconds, min(session.target.seconds, CoachLimits.minimumRunSeconds))
                )
            }
            notes.append(CoachNote(.plan, "Done: this week is a quarter lighter. Nothing to make up."))
            return (CoachUpdate(state: state, notes: notes), nil)
        case .levelUp(let accept):
            guard accept, let next = state.level.higher else { return (CoachUpdate(state: state), nil) }
            return (changeLevel(next, state: state, runs: runs, now: now, calendar: calendar), nil)
        case .missedRuns(let reason), .dipCheck(let reason), .rampDrops(let reason):
            switch reason {
            case .busy: return (CoachUpdate(state: state), .lifeHappensBusy)
            case .travel: return (CoachUpdate(state: state), .lifeHappensTravel)
            case .sick:
                return (reportIllness(kind: nil, state: state, runs: runs, now: now, calendar: calendar), nil)
            case .injured: return (CoachUpdate(state: state), .reportInjury)
            case .wornOut:
                if case .rampDrops = answer {
                    // AD-10: the two drops count as AD-6b's two STEP BACKs, so the next week is Fatigue Level 1.
                    state.fatigue.stepBacksInRow = max(state.fatigue.stepBacksInRow, 2)
                    return (CoachUpdate(state: state), nil)
                }
                return (CoachUpdate(state: state), .wellnessQuestions)
            case .fine, .other:
                return (CoachUpdate(state: state), nil)
            }
        case .moveKeySession(let sessionID, let toDay, let accept):
            guard accept else { return (CoachUpdate(state: state), nil) }
            return (moveSession(sessionID, toDay: toDay, state: state, runs: runs, now: now, calendar: calendar), nil)
        case .ladderEasierRestart(let accept):
            guard accept else { return (CoachUpdate(state: state), nil) }
            let update = LadderCoach.restartEasier(state: state, runs: runs, now: now, calendar: calendar)
            return (replanned(update, runs: runs, now: now, calendar: calendar), nil)
        }
    }

    // MARK: Changes the runner makes

    /// A new level (CL-4): AD-5 runs again at once and the current week is re-planned.
    static func changeLevel(_ level: CommitmentLevel, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        let level = min(level, state.assessment.levels.ceiling)
        guard level != state.level else { return CoachUpdate(state: state) }
        state.levelChanges.append(LevelChange(date: now, from: state.level, to: level))
        state.level = level
        state.intake.level = level
        let note = CoachNote(.level, "You're now on \(level.name). \(level.summary(stepBackEveryThird: state.assessment.recoveryTier.stepsBackEveryThird))")
        return replanned(CoachUpdate(state: state, notes: [note]), runs: runs, now: now, calendar: calendar)
    }

    /// New run days or times (IN-12). The current week is re-planned on the new days.
    static func changeSchedule(
        runDays: Set<Weekday>,
        weekdayMaxSeconds: Double?,
        weekendMaxSeconds: Double?,
        longRunDay: Weekday?,
        state: CoachState,
        runs: [LoggedRun],
        now: Date,
        calendar: Calendar
    ) -> CoachUpdate {
        var state = state
        state.intake.runDays = runDays
        state.intake.weekdayMaxSeconds = weekdayMaxSeconds
        state.intake.weekendMaxSeconds = weekendMaxSeconds
        state.intake.longRunDay = longRunDay
        state.cycle.runsPerWeek = max(1, min(state.cycle.runsPerWeek, runDays.count, state.assessment.runsCap))
        if runDays.count < 2, state.goal.flavor != .buildDistance {
            state.status = .stopped(reason: .fewRunDays, on: now)
            return CoachUpdate(state: state, notes: [CoachNote(.plan, "A plan for this goal needs at least 2 run days a week. One run a week still counts: when two fit your week, I'll build a full plan.")])
        }
        return replanned(CoachUpdate(state: state), runs: runs, now: now, calendar: calendar)
    }

    /// Moves a session to another day of its week (AD-9). A move that puts two hard days together makes the Q
    /// an easy run of the same length (RB-5).
    static func moveSession(_ sessionID: UUID, toDay day: Int, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        guard (0 ... 6).contains(day), let (weekPosition, sessionPosition) = locate(sessionID, in: state) else { return CoachUpdate(state: state) }
        var week = state.weeks[weekPosition].plan
        var session = week.sessions[sessionPosition]
        guard session.status.isPlanned, session.kind != .race else { return CoachUpdate(state: state) }
        if let event = state.event, session.isKey,
           let lastWeekStart = calendar.date(byAdding: .day, value: -6, to: event.raceDate), week.start >= lastWeekStart {
            return CoachUpdate(state: state, notes: [CoachNote(.event, "In race week your sessions stay where they are.")])
        }
        session.movedFrom = session.movedFrom ?? session.dayOffset
        session.dayOffset = day
        var notes: [CoachNote] = []
        if spaceOut(&session, among: week.sessions) {
            notes.append(CoachNote(.plan, "That puts two hard days together, so this session is now an easy run of the same length."))
        }
        week.sessions[sessionPosition] = session
        week.sessions.sort { $0.dayOffset < $1.dayOffset }
        state.weeks[weekPosition].plan = week
        return CoachUpdate(state: state, notes: notes)
    }

    /// RB-5: a Q next to another hard day becomes an easy run of the same length. Returns whether it changed.
    static func spaceOut(_ session: inout PlannedSession, among sessions: [PlannedSession]) -> Bool {
        let day = session.dayOffset
        let id = session.id
        guard session.isQuality, sessions.contains(where: { $0.id != id && abs($0.dayOffset - day) <= 1 && $0.isHardDay }) else { return false }
        session.madeEasy = .spacing
        session.effort = .easy
        session.blocks = []
        return true
    }

    static func stopPlan(state: CoachState, now: Date) -> CoachUpdate {
        var state = state
        state.status = .stopped(reason: .runner, on: now)
        return CoachUpdate(state: state)
    }

    /// The question "Ready" asks before the plan restarts, or nil when the plan isn't paused.
    static func resumeQuestion(_ state: CoachState) -> String? {
        guard case .paused(let reason, _) = state.status else { return nil }
        switch reason {
        case .heat: return "Have you felt back to normal for a full day?"
        case .illness: return "Have you felt back to normal for 2 full days?"
        case .injury: return "Ready to run again?"
        case .fatigue: return "Ready to start back?"
        }
    }

    /// "Ready": the runner confirmed `resumeQuestion`. Injury and illness restarts go through their own rules;
    /// heat and fatigue restart here, fatigue through the return ramp (AD-6b, AD-10, AD-16).
    static func resume(state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        guard case .paused(let reason, let since) = state.status else { return CoachUpdate(state: state) }
        switch reason {
        case .injury:
            let open = state.openInjuries.filter { $0.level >= .intense }
            var update = CoachUpdate(state: state)
            for report in open {
                update = InjuryCoach.answer(.ready(true), reportID: report.id, state: update.state, runs: runs, now: now, calendar: calendar)
            }
            return replanned(update, runs: runs, now: now, calendar: calendar)
        case .illness:
            guard let episode = state.activeIllness else {
                state.status = .active
                return replanned(CoachUpdate(state: state), runs: runs, now: now, calendar: calendar)
            }
            let update = IllnessCoach.answer(.ready(true), episodeID: episode.id, state: state, runs: runs, now: now, calendar: calendar)
            return replanned(update, runs: runs, now: now, calendar: calendar)
        case .heat:
            state.status = .active
            state.heat.easyRunsLeft = 2
            let note = CoachNote(.plan, "Welcome back. Your next two runs are easy, 30 minutes or less, somewhere cool or indoors.")
            return replanned(CoachUpdate(state: state, notes: [note]), runs: runs, now: now, calendar: calendar)
        case .fatigue:
            state.status = .active
            state.fatigue = FatigueState()
            let days = calendar.dateComponents([.day], from: since, to: now).day ?? 0
            let sessions = LoadMetrics.sessions(from: runs)
            let daysOff = LoadMetrics.daysSinceQualifyingRun(at: now, sessions: sessions, usualEasySeconds: nil, calendar: calendar) ?? days
            state.gap = WeeklyReviewer.startRamp(daysOff: max(daysOff, 8), state: state, runs: runs, weekEnd: now, now: now, calendar: calendar)
            return replanned(CoachUpdate(state: state), runs: runs, now: now, calendar: calendar)
        }
    }

    // MARK: Information

    /// A race forecast from the anchor in force (PZ-4), or nil with effort only.
    static func forecast(_ distance: RaceDistance, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> RaceForecast? {
        let sessions = LoadMetrics.sessions(from: runs)
        let start = calendar.date(byAdding: .day, value: -28, to: now) ?? now
        let meters = LoadMetrics.volume(from: start, to: now, sessions: sessions, unit: .distance, pace: state.paces.easyPace) / 4
        return PaceCalculator.forecast(
            distance,
            paces: state.paces,
            firstTime: state.assessment.overlays.firstTimer,
            weeklyMeters: meters,
            age: state.assessment.age,
            now: now,
            calendar: calendar
        )
    }

    /// Heart-rate ceilings and bands (PZ-11, PZ-12). Kept on the device.
    static func heartRateZones(age: Int, settings: HeartRateSettings, observedMax: Double? = nil, threshold: Double? = nil) -> HeartRateZones {
        PaceCalculator.heartRateZones(age: age, settings: settings, observedMax: observedMax, threshold: threshold)
    }

    /// The plan week containing `now`.
    static func currentWeek(_ state: CoachState, now: Date, calendar: Calendar) -> PlannedWeek? {
        let index = state.weekIndex(on: now, calendar: calendar)
        return state.weeks.first { $0.plan.index == index }?.plan
    }

    /// Today's sessions.
    static func todaysSessions(_ state: CoachState, now: Date, calendar: Calendar) -> [PlannedSession] {
        guard let week = currentWeek(state, now: now, calendar: calendar) else { return [] }
        let offset = dayOffset(week, now: now, calendar: calendar)
        return week.sessions.filter { $0.dayOffset == offset }
    }

    // MARK: Helpers

    /// Re-plans the current week after a change: done sessions and days already gone stay as they were, and a
    /// session the runner moved stays on its new day when the new plan still has it (AD-9).
    static func replanCurrentWeek(_ state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachState {
        guard let position = currentWeekPosition(state, now: now, calendar: calendar) else { return state }
        let old = state.weeks[position]
        var state = WeekPlanner.planWeek(old.plan.index, state: state, runs: runs, now: now, calendar: calendar)
        guard let newPosition = state.weeks.firstIndex(where: { $0.plan.index == old.plan.index }) else { return state }
        let today = dayOffset(old.plan, now: now, calendar: calendar)
        var week = state.weeks[newPosition].plan
        let kept = old.plan.sessions.filter { $0.dayOffset < today || !$0.status.isPlanned }
        let keptDays = Set(kept.filter { $0.dayOffset >= today && $0.kind.isRun }.map(\.dayOffset))
        let keptIDs = Set(kept.map(\.id))
        let moves = Dictionary(old.plan.sessions.filter { $0.movedFrom != nil }.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let laidOut = week.sessions.map { session -> PlannedSession in
            guard let move = moves[session.id] else { return session }
            var session = session
            session.movedFrom = move.movedFrom
            session.dayOffset = move.dayOffset
            return session
        }
        var fresh = laidOut.filter { $0.dayOffset >= today && !keptIDs.contains($0.id) && !($0.kind.isRun && keptDays.contains($0.dayOffset)) }
        for index in fresh.indices where moves[fresh[index].id] != nil {
            _ = spaceOut(&fresh[index], among: kept + fresh)
        }
        week.sessions = (kept + fresh).sorted { $0.dayOffset < $1.dayOffset }
        state.weeks[newPosition].plan = week
        state.weeks[newPosition].checkIn = old.checkIn
        state.weeks[newPosition].review = old.review
        return state
    }

    static func replanned(_ update: CoachUpdate, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        let state = replanCurrentWeek(update.state, runs: runs, now: now, calendar: calendar)
        let refreshed = refresh(state: state, runs: runs, now: now, calendar: calendar)
        var notes = update.notes
        if let week = currentWeek(refreshed.state, now: now, calendar: calendar) {
            notes += week.notes.filter { $0.topic != .safety }
        }
        return CoachUpdate(state: refreshed.state, notes: unique(notes), questions: unique(update.questions + refreshed.questions))
    }

    static func currentWeekPosition(_ state: CoachState, now: Date, calendar: Calendar) -> Int? {
        let index = state.weekIndex(on: now, calendar: calendar)
        return state.weeks.firstIndex { $0.plan.index == index }
    }

    static func dayOffset(_ week: PlannedWeek, now: Date, calendar: Calendar) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: week.start), to: calendar.startOfDay(for: now)).day ?? 0
        return days.clamped(to: 0 ... 7)
    }

    static func locate(_ sessionID: UUID, in state: CoachState) -> (Int, Int)? {
        for weekPosition in state.weeks.indices {
            if let sessionPosition = state.weeks[weekPosition].plan.sessions.firstIndex(where: { $0.id == sessionID }) {
                return (weekPosition, sessionPosition)
            }
        }
        return nil
    }

    /// Planned sessions on days already gone become missed.
    static func markMissed(_ state: CoachState, now: Date, calendar: Calendar) -> CoachState {
        var state = state
        let today = calendar.startOfDay(for: now)
        for weekPosition in state.weeks.indices {
            let week = state.weeks[weekPosition].plan
            for sessionPosition in week.sessions.indices where week.sessions[sessionPosition].status.isPlanned {
                let day = state.date(of: week.sessions[sessionPosition], in: week, calendar: calendar)
                if day < today { state.weeks[weekPosition].plan.sessions[sessionPosition].status = .missed }
            }
        }
        return state
    }

    /// What the coach is waiting on now.
    static func pendingQuestions(_ state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> [CoachQuestion] {
        var questions: [CoachQuestion] = []
        if let position = currentWeekPosition(state, now: now, calendar: calendar) {
            let week = state.weeks[position]
            let offset = dayOffset(week.plan, now: now, calendar: calendar)
            // A week with no run planned (a pause, or a first week whose run days had passed) has nothing to ask.
            func asks(_ record: WeekRecord) -> Bool {
                record.checkIn == nil && record.plan.kind != .paused && record.plan.sessions.contains { $0.kind.isRun }
            }
            if offset >= 6, asks(week) {
                questions.append(.weeklyCheckIn(weekIndex: week.plan.index))
            } else if offset <= 2, position > 0, asks(state.weeks[position - 1]) {
                questions.append(.weeklyCheckIn(weekIndex: state.weeks[position - 1].plan.index))
            }
            // RB-8 before today's Q, long run, test or race.
            for session in week.plan.sessions where session.dayOffset == offset && session.status.isPlanned
                && (session.isQuality || session.kind == .long || session.kind == .race)
                && !state.readiness.contains(where: { $0.sessionID == session.id }) {
                questions.append(.readiness(sessionID: session.id))
            }
        }
        let dayAgo = now.addingTimeInterval(-24 * 3_600)
        for run in runs where run.start >= dayAgo && run.start <= now && run.checkIn?.answeredAt == nil && run.start >= state.startDate {
            questions.append(.runCheckIn(runID: run.id))
        }
        questions += InjuryCoach.questions(state, now: now, calendar: calendar)
        questions += IllnessCoach.questions(state, now: now, calendar: calendar)
        questions += LadderCoach.questions(state, runs: runs, now: now, calendar: calendar)
        questions += EventReviewer.questions(state, runs: runs, now: now, calendar: calendar)
        return questions
    }

    static func unique<T: Hashable>(_ items: [T]) -> [T] {
        var seen = Set<T>()
        return items.filter { seen.insert($0).inserted }
    }
}
