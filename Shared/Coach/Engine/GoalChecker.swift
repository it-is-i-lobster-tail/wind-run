//
//  GoalChecker.swift
//  Wind Run
//

import Foundation

/// The realism check: can the goal be reached safely, by when, and what to say (RC-1 to RC-12, HL-26, PZ-6).
enum GoalChecker {
    /// RC-2's Green long run and volume for a goal, in meters (the 5K's long run also has a 30-min form). Speed
    /// Work's half always uses the time-goal row (SW-1b).
    static func greenTargets(for goal: GoalChoice) -> (longRun: Double, volume: Double) {
        switch goal.distance {
        case .mile: (1_609.344, 0)
        case .fiveK: (5_000, 0)
        case .tenK: (10_000, 15_000)
        case .halfMarathon: goal.hasTimeGoal || goal.flavor == .speedWork ? (21_000, 32_000) : (16_000, 25_000)
        case .marathon: (30_000, 40_000)
        }
    }

    /// What one run of the check reads: the runner's numbers now, at intake or from the logs.
    struct Subject {
        var intake: CoachIntake
        var assessment: RunnerAssessment
        var paces: TrainingPaces
        var level: CommitmentLevel
        var injuries: [InjuryReport]
        var input: FeasibilityInput
        /// Weekly distance now, PZ-4's durability and the fully missed weeks, for the forecast.
        var weeklyMeters: Double
        var durable: Bool?
        var missedWeeks: Int
        /// Speed Work blocks run so far and the next block's length (RC-6b, SW-3).
        var blocksDone: Int
        var blockLength: Int
        /// Interval, tempo or hill sessions done before or in the plan (RC-6a's "no speed work yet").
        var doneSpeedWork: Bool
        /// Distances raced in about the last 18 months.
        var racedDistances: Set<RaceDistance>

        var unit: DistanceUnit { intake.distanceUnit }

        /// No finish at the distance in about 18 months (TI-3). Intake's answer covers its goal distance and the
        /// shorter ones; a longer distance is a first attempt until it is raced.
        func firstTimer(at distance: RaceDistance) -> Bool {
            if racedDistances.contains(where: { $0 >= distance }) { return false }
            if distance <= intake.goal.distance { return intake.finished != .yesRecently }
            return true
        }

        func forecast(_ distance: RaceDistance, now: Date, calendar: Calendar) -> RaceForecast? {
            let context = ForecastContext(firstTime: firstTimer(at: distance), weeklyMeters: weeklyMeters, age: assessment.age, durable: durable, missedWeeks: missedWeeks)
            return PaceCalculator.forecast(distance, paces: paces, context: context, now: now, calendar: calendar)
        }
    }

    // MARK: Entry points

    /// The check at goal creation, from intake (RC-1 to RC-9). `injuries` are any open reports (RC-4 step 2b).
    static func check(
        _ goal: GoalChoice,
        intake: CoachIntake,
        assessment: RunnerAssessment,
        paces: TrainingPaces,
        level: CommitmentLevel,
        injuries: [InjuryReport] = [],
        now: Date,
        calendar: Calendar
    ) -> GoalCheck {
        let input = FeasibilityInput(intake: intake, assessment: assessment, paces: paces, level: level, injuries: injuries, now: now, calendar: calendar)
        let subject = Subject(
            intake: intake,
            assessment: assessment,
            paces: paces,
            level: level,
            injuries: injuries,
            input: input,
            weeklyMeters: FeasibilityEngine.meters(input.volumeNow, unit: input.unit, pace: input.pace),
            durable: nil,
            missedWeeks: 0,
            blocksDone: 0,
            blockLength: assessment.recoveryTier == .normal ? 8 : 6,
            doneSpeedWork: assessment.start.currentQ > 0 || intake.sessionsLastYear || intake.sessionsForAYearOrMore,
            racedDistances: []
        )
        return run(goal, subject: subject, now: now, calendar: calendar)
    }

    /// The re-run from the logs: weekly for events (EF-1), after each Speed Work retest (SW-7a), at a hand-off
    /// (RC-12a) and when the cause behind a saved goal clears (RC-1). It starts from today's P-L30, volume, paces
    /// and anchors, and the plan's injury reports.
    static func recheck(_ goal: GoalChoice, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> GoalCheck {
        let index = max(0, state.weekIndex(on: now, calendar: calendar))
        let input = FeasibilityInput(state: state, runs: runs, fromWeek: index, now: now, calendar: calendar)
        let context = PaceCalculator.forecastContext(for: goal.distance, state: state, runs: runs, now: now, calendar: calendar)
        let subject = Subject(
            intake: state.intake,
            assessment: state.assessment,
            paces: state.paces,
            level: state.level,
            injuries: state.injuries,
            input: input,
            weeklyMeters: context.weeklyMeters,
            durable: context.durable,
            missedWeeks: context.missedWeeks,
            blocksDone: state.quality.blocksDone,
            blockLength: state.quality.blockLength,
            doneSpeedWork: state.assessment.start.currentQ > 0 || !state.quality.doses.isEmpty || state.intake.sessionsLastYear,
            racedDistances: PaceCalculator.racedDistances(state.paces, now: now, calendar: calendar)
        )
        return run(goal, subject: subject, now: now, calendar: calendar)
    }

    static func refusal(_ reason: RefusalReason, message: String) -> GoalCheck {
        GoalCheck(
            verdict: .refused,
            refusal: reason,
            feasibility: nil,
            forecast: nil,
            timeGoal: nil,
            alternatives: [],
            savedGoalEarliest: nil,
            plansRunWalk: false,
            cutoffAtRisk: false,
            canInsist: false,
            message: message
        )
    }

    // MARK: The check

    static func run(_ goal: GoalChoice, subject: Subject, now: Date, calendar: Calendar) -> GoalCheck {
        let today = calendar.startOfDay(for: now)
        let input = subject.input
        let unit = subject.unit
        let raceDay = goal.flavor == .event ? goal.eventDate.map { calendar.startOfDay(for: $0) } : nil
        if let raceDay, raceDay < today {
            return refusal(.pastDate, message: "That race date has already passed. Pick a date from today on, and I'll check your goal again.")
        }
        let weeksAvailable = raceDay.map { weeks(from: today, to: $0, calendar: calendar) }

        // RC-1: refusals, which the runner can't insist past.
        if subject.injuries.contains(where: isPausedSevere) {
            var check = refusal(.severeInjury, message: "Let's get you back running first. Your goal is saved, and I'll check it again when you're ready.")
            check.savedGoal = goal
            return check
        }
        if subject.assessment.habitMode, goal.flavor != .buildDistance {
            var check = refusal(.fewRunDays, message: "With one run day a week I can't build safely toward \(phrase(goal)). Let's make running a habit first: one run plus walks each week. Your goal is saved, and a second run day unlocks it.")
            check.savedGoal = goal
            check.alternatives = [GoalAlternative(goal: GoalChoice(flavor: .buildDistance, distance: goal.distance), label: "Habit plan: one run plus walks each week", status: nil)]
            return check
        }
        if goal.flavor == .event, goal.distance > .tenK, input.earlyWindow, let weeksAvailable {
            let tenK = GoalChoice(flavor: .event, distance: .tenK, eventDate: goal.eventDate)
            let tenKFeasibility = feasibility(tenK, subject: subject, weeksAvailable: weeksAvailable, today: today, calendar: calendar)
            let windowEnd = tenKFeasibility.earlyWindowEndWeeks
            if windowEnd.map({ weeksAvailable < $0 }) ?? true {
                var message = "In your first 12 weeks and \(CoachFormat.distance(km: 200, mi: 124, unit: unit)) of regular running, I keep events to 10K or shorter, because that's when most new-runner injuries happen."
                if let windowEnd {
                    message += " Your window ends around \(CoachFormat.date(date(weeks: windowEnd, from: today, calendar: calendar), calendar: calendar))."
                }
                message += " Shall we aim for the 10K?"
                var check = refusal(.earlyWindow, message: message)
                check.savedGoal = goal
                check.savedGoalEarliest = windowEnd.map { date(weeks: $0, from: today, calendar: calendar) }
                check.alternatives = [GoalAlternative(goal: tenK, label: "10K on \(CoachFormat.date(tenK.eventDate ?? today, calendar: calendar))", status: distanceVerdict(tenKFeasibility).status)]
                return check
            }
        }
        if goal.distance == .marathon, subject.firstTimer(at: .marathon), !(input.months >= 12 - 1e-6 && input.halfDone) {
            return firstMarathonRefusal(goal, subject: subject, weeksAvailable: weeksAvailable, today: today, calendar: calendar)
        }

        // RC-2 to RC-5: the distance.
        let feasibility = feasibility(goal, subject: subject, weeksAvailable: weeksAvailable, today: today, calendar: calendar)
        switch goal.flavor {
        case .buildDistance:
            return buildDistanceCheck(goal, feasibility: feasibility, subject: subject, today: today, calendar: calendar)
        case .speedWork:
            return speedWorkCheck(goal, feasibility: feasibility, subject: subject, today: today, calendar: calendar)
        case .event:
            return eventCheck(goal, feasibility: feasibility, subject: subject, weeksAvailable: weeksAvailable, raceDay: raceDay, today: today, calendar: calendar)
        }
    }

    /// RC-1's HL-26 refusal: the half is offered, and the marathon is saved with the earliest date RC-4 gives when
    /// the 18-week block starts in the week the gate is met, or the long-run path if that is later (RC-11).
    static func firstMarathonRefusal(_ goal: GoalChoice, subject: Subject, weeksAvailable: Int?, today: Date, calendar: Calendar) -> GoalCheck {
        let unit = subject.unit
        let marathon = GoalChoice(flavor: goal.flavor == .buildDistance ? .buildDistance : .event, distance: .marathon)
        let saved = FeasibilityEngine.evaluate(marathon, input: subject.input, firstTimer: true, weeksAvailable: nil, now: today, calendar: calendar)
        let months = Int((subject.input.months + 1e-6).rounded(.down))
        let message = "A first marathon needs a year of running and a half marathon (or a \(CoachFormat.distance(km: 16, mi: 10, unit: unit)) run) first. You're at \(months) \(months == 1 ? "month" : "months"). Let's train for a half: your marathon is saved, and the earliest I can plan it is \(CoachFormat.date(saved.earliestDate, calendar: calendar))."
        var check = refusal(.firstMarathon, message: message)
        check.savedGoal = goal
        check.savedGoalEarliest = saved.earliestDate
        check.feasibility = saved
        if goal.flavor == .event, let weeksAvailable {
            check.alternatives = sameDateAlternatives(goal, subject: subject, weeksAvailable: weeksAvailable, today: today, calendar: calendar)
            let half = GoalChoice(flavor: .event, distance: .halfMarathon)
            let halfFeasibility = FeasibilityEngine.evaluate(half, input: subject.input, firstTimer: subject.firstTimer(at: .halfMarathon), weeksAvailable: nil, now: today, calendar: calendar)
            if !halfFeasibility.unreachable {
                let halfDate = date(weeks: halfFeasibility.earliestWeeks + halfFeasibility.bufferWeeks, from: today, calendar: calendar)
                var dated = half
                dated.eventDate = halfDate
                check.alternatives.append(GoalAlternative(goal: dated, label: "Half marathon on \(CoachFormat.date(halfDate, calendar: calendar))", status: .green, earliestDate: halfDate))
            }
        } else {
            check.alternatives = [GoalAlternative(goal: GoalChoice(flavor: goal.flavor, distance: .halfMarathon), label: "Half marathon", status: nil)]
        }
        return check
    }

    // MARK: Build Distance

    /// Build Distance has no date: earliest and likely weeks instead of a verdict, the RC-3 gate per rung (BD-1c),
    /// and RC-8e when the runner's time can't hold the rung.
    static func buildDistanceCheck(_ goal: GoalChoice, feasibility: Feasibility, subject: Subject, today: Date, calendar: Calendar) -> GoalCheck {
        var sentences: [String] = []
        var verdict = GoalVerdict.green
        let timeFit = timeFitSentences(goal, feasibility: feasibility, subject: subject, weeksAvailable: nil, today: today, calendar: calendar)
        if feasibility.unreachable || !timeFit.isEmpty {
            verdict = .amber
            sentences += timeFit
        } else {
            sentences.append("This fits. At \(subject.level.name) you could be ready in \(CoachFormat.weekRange(feasibility.earliestWeeks, feasibility.likelyWeeks)).")
            if let gate = gateSentence(goal, feasibility: feasibility, subject: subject, today: today, calendar: calendar) {
                sentences.append(gate)
            }
        }
        return GoalCheck(
            verdict: verdict,
            refusal: nil,
            feasibility: feasibility,
            forecast: nil,
            timeGoal: nil,
            alternatives: [],
            savedGoalEarliest: nil,
            plansRunWalk: goal.runWalk,
            cutoffAtRisk: false,
            canInsist: false,
            message: sentences.joined(separator: " ")
        )
    }

    // MARK: Speed Work

    /// Speed Work: distance first until RC-2 is Green (SW-1b), then RC-6 for the next block (SW-1a).
    static func speedWorkCheck(_ goal: GoalChoice, feasibility: Feasibility, subject: Subject, today: Date, calendar: Calendar) -> GoalCheck {
        let input = subject.input
        let rows = ReadinessTargets.make(for: goal, timeRows: true, unit: input.unit, pace: input.pace)
        let readyNow = FeasibilityEngine.statuses(after: 0, targets: rows, weeks: [], input: input)
        let ready = readyNow.long == .green && readyNow.volume == .green
        let forecast = subject.forecast(goal.distance, now: today, calendar: calendar)
        let blockStart = max(feasibility.pathWeeks ?? feasibility.earliestWeeks, input.calibrationWeeks)
        let retest = date(weeks: blockStart + subject.blockLength - 1, from: today, calendar: calendar)
        var sentences: [String] = []
        var verdict = GoalVerdict.green
        var timeGoal: TimeGoalCheck?
        var dropped = false
        var racePace: Double?

        let timeFit = timeFitSentences(goal, feasibility: feasibility, subject: subject, weeksAvailable: nil, today: today, calendar: calendar)
        if !timeFit.isEmpty {
            verdict = .amber
            sentences += timeFit
        }

        if subject.assessment.tier == .starter {
            // RC-6e: Starters set no time goal.
            dropped = true
            sentences.append(starterSentence)
        } else if goal.strongFirstTime || !goal.hasTimeGoal {
            // SW-1a: a strong first time is the central forecast with the cautious k; it needs no verdict.
            racePace = forecast?.pace
            sentences.append(contentsOf: strongFirstSentences(goal, ready: ready, feasibility: feasibility, forecast: forecast, subject: subject))
        } else if let target = goal.targetSeconds {
            if !ready {
                sentences.append("\(CoachFormat.capitalized(CoachFormat.article(for: goal.distance.sentenceName))) \(goal.distance.sentenceName) time goal needs long runs of about \(targetText(goal, feasibility: feasibility, subject: subject)) first. I'll build your distance, then add speed sessions.")
            }
            let check = timeCheck(
                goalSeconds: target,
                distance: goal.distance,
                subject: subject,
                forecast: forecast,
                weeksCounted: subject.blockLength,
                firstBlock: subject.blocksDone,
                speedWork: true,
                windowWeeks: 0,
                retestDate: retest
            )
            timeGoal = check
            sentences.append(contentsOf: speedWorkTimeSentences(goal, check: check, subject: subject, calendar: calendar))
            if check.provisional, !check.noAnchor, let date = check.retestDate {
                sentences.append("Provisional: I'll confirm this target after your first test around \(CoachFormat.date(date, calendar: calendar)).")
            }
            if check.verdict != .realistic { verdict = worse(verdict, .amber) }
            if check.verdict != .unlikely, !check.noAnchor { racePace = forecast?.pace }
        }
        var result = GoalCheck(
            verdict: verdict,
            refusal: nil,
            feasibility: feasibility,
            forecast: forecast,
            timeGoal: timeGoal,
            alternatives: [],
            savedGoalEarliest: nil,
            plansRunWalk: false,
            cutoffAtRisk: false,
            canInsist: false,
            message: sentences.joined(separator: " ")
        )
        result.timeGoalDropped = dropped
        result.racePace = dropped ? nil : racePace
        if let check = timeGoal, check.verdict == .unlikely, let forecast {
            result.alternatives = [GoalAlternative(goal: retimed(goal, forecast.central), label: "Aim for \(CoachFormat.roughClock(forecast.central))", status: nil)]
        }
        return result
    }

    static let starterSentence = "Let's get you running 30 minutes non-stop first. After your early window, a short test will give us a fair time target."

    /// SW-1a's strong first time: the distance still to build, the block, and the forecast (SW worked example).
    static func strongFirstSentences(_ goal: GoalChoice, ready: Bool, feasibility: Feasibility, forecast: RaceForecast?, subject: Subject) -> [String] {
        let unit = subject.unit
        let name = goal.distance.shortName
        var sentences: [String] = []
        if !ready {
            let longest = subject.intake.lastFourWeeks?.longest.flatMap { $0.value(in: .distance, pace: subject.input.pace) }
            let longestText = longest.map { CoachFormat.distance($0, unit: unit) }
                ?? CoachFormat.amount(subject.input.longest, in: subject.input.unit, unit: unit)
            let readiness = feasibility.pathWeeks ?? feasibility.earliestWeeks
            sentences.append("A strong first \(goal.distance.shortName) needs long runs of about \(targetText(goal, feasibility: feasibility, subject: subject)) before speed work pays off. Your longest is \(longestText), and I add at most 10% at a time with easier weeks between, so that's \(CoachFormat.weekRange(readiness, Progression.likelyWeeks(earliest: readiness))) at \(subject.level.name).")
        }
        let block = "\(subject.blockLength)-week"
        let article = CoachFormat.article(for: block)
        sentences.append(ready ? "\(CoachFormat.capitalized(article)) \(block) speed block ends with your \(name)." : "Then \(article) \(block) speed block ends with your \(name).")
        if let forecast, let anchor = PaceCalculator.allResults(subject.paces).first(where: { $0.id == forecast.anchorID }) {
            sentences.append("From your \(CoachFormat.roughClock(anchor.seconds)) \(resultName(anchor, unit: unit)), a first \(goal.distance.shortName) lands around \(CoachFormat.roughClock(forecast.central)) (likely \(CoachFormat.roughClock(forecast.low)) to \(CoachFormat.roughClock(forecast.high))).")
        } else {
            sentences.append("Your first test will give us a forecast to aim at.")
        }
        return sentences
    }

    /// SW-1a's verdict messages for the next block.
    static func speedWorkTimeSentences(_ goal: GoalChoice, check: TimeGoalCheck, subject: Subject, calendar: Calendar) -> [String] {
        let name = CoachFormat.capitalized(CoachFormat.goalName(check.goalSeconds))
        if check.noAnchor { return noAnchorSentences(goal, check: check, calendar: calendar) }
        let current = CoachFormat.roughClock(check.currentEquivalent)
        let needed = CoachFormat.percent(max(0, check.improvementNeeded))
        let realistic = CoachFormat.percent(check.realisticGain)
        let stretch = CoachFormat.percent(check.stretchGain)
        var sentences: [String] = []
        switch check.verdict {
        case .realistic:
            let block = "\(subject.blockLength)-week"
            sentences.append("\(name) is \(needed) faster than your current \(current). About \(realistic) is typical in \(CoachFormat.article(for: block)) \(block) block, so this fits. Let's go.")
        case .stretch:
            sentences.append("\(name) is \(needed) faster than your current \(current). About \(realistic) is typical in a block, up to \(stretch) in a very good one, so it's a stretch. Your sessions use your current fitness, and the end-of-block test will show where you are.")
        case .unlikely:
            sentences.append("\(name) is \(needed) faster than your current \(current). A block usually brings about \(realistic), up to \(stretch), so this block aims at \(CoachFormat.roughClock(check.interimGoal ?? check.currentEquivalent)).")
        }
        if check.multiSeason {
            sentences.append("That's more than the \(CoachFormat.percent(check.yearlyCap)) I'd expect in a year, so \(CoachFormat.goalName(check.goalSeconds)) is a multi-season goal. I'll re-check it after every test.")
        }
        return sentences
    }

    /// PZ-6: no race or test yet, so the goal waits for the first test; PZ-6a's speed bound still rules out a goal
    /// past the yearly cap.
    static func noAnchorSentences(_ goal: GoalChoice, check: TimeGoalCheck, calendar: Calendar) -> [String] {
        let name = CoachFormat.capitalized(CoachFormat.goalName(check.goalSeconds))
        if check.verdict == .unlikely, check.currentEquivalent > 0 {
            return ["\(name) would need \(CoachFormat.percent(check.improvementNeeded)) more than the fastest \(goal.distance.sentenceName) your easy pace suggests, about \(CoachFormat.roughClock(check.currentEquivalent)). That's more than the \(CoachFormat.percent(check.yearlyCap)) I'd expect in a year, so I'll train you by effort and a test will show where you are."]
        }
        let when = check.retestDate.map { ", around \(CoachFormat.date($0, calendar: calendar))," } ?? ""
        return ["I don't have a race or test time for you yet, so \(CoachFormat.goalName(check.goalSeconds)) is a stretch goal for now. Your first test\(when) will show how close it is."]
    }

    // MARK: Events

    /// Train for an Event: RC-7's verdict from the distance at taper start and the time goal, RC-8's message and
    /// offers, RC-9's insist path, PZ-6c's cut-off and RC-12's start for races over a year away.
    static func eventCheck(_ goal: GoalChoice, feasibility: Feasibility, subject: Subject, weeksAvailable: Int?, raceDay: Date?, today: Date, calendar: Calendar) -> GoalCheck {
        guard let weeksAvailable, let raceDay else {
            // No date yet: the earliest and likely weeks, as for Build Distance.
            var check = buildDistanceCheck(goal, feasibility: feasibility, subject: subject, today: today, calendar: calendar)
            check.forecast = subject.forecast(goal.distance, now: today, calendar: calendar)
            return check
        }
        let unit = subject.unit
        let input = subject.input
        let distance = distanceVerdict(feasibility)
        let forecast = subject.forecast(goal.distance, now: today, calendar: calendar)
        var sentences: [String] = []
        var verdict = distance.verdict
        var alternatives: [GoalAlternative] = []
        var timeGoal: TimeGoalCheck?
        var dropped = distance.verdict != .green
        var plansRunWalk = distance.verdict != .green

        switch distance.verdict {
        case .red, .refused:
            if distance.gateLimited, let gate = FirstAttemptGate.gate(for: goal) {
                sentences.append("A first \(raceName(goal)) needs \(feasibility.blockMinimum) weeks of training once \(gate.condition(unit: unit)), so the earliest I can plan it is \(CoachFormat.date(feasibility.earliestDate, calendar: calendar)).")
            } else {
                sentences.append(redSentence(goal, feasibility: feasibility, subject: subject, weeksAvailable: weeksAvailable))
            }
            sentences += timeFitSentences(goal, feasibility: feasibility, subject: subject, weeksAvailable: weeksAvailable, today: today, calendar: calendar)
            sentences.append("About 3 in 10 runners get injured building for a 5-10K, and 4-5 in 10 for a half or marathon.")
            alternatives = redAlternatives(goal, feasibility: feasibility, subject: subject, weeksAvailable: weeksAvailable, today: today, calendar: calendar)
        case .amber:
            sentences.append("You can likely finish, but expect to run slower and take walk breaks.")
            if distance.bufferOnly {
                sentences.append("There's no room for a missed week, so I've planned 1-minute walk breaks each km from the start.")
            }
            sentences += timeFitSentences(goal, feasibility: feasibility, subject: subject, weeksAvailable: weeksAvailable, today: today, calendar: calendar)
        case .green:
            let timeFit = timeFitSentences(goal, feasibility: feasibility, subject: subject, weeksAvailable: weeksAvailable, today: today, calendar: calendar)
            if subject.assessment.tier == .starter, goal.hasTimeGoal {
                dropped = true
                sentences.append(greenSentence(goal, feasibility: feasibility, subject: subject, today: today, calendar: calendar))
                sentences.append(starterSentence)
            } else if let target = goal.targetSeconds {
                let windowWeeks = subject.assessment.tier == .novice && input.earlyWindow ? (feasibility.earlyWindowEndWeeks ?? weeksAvailable) : 0
                var check = timeCheck(
                    goalSeconds: target,
                    distance: goal.distance,
                    subject: subject,
                    forecast: forecast,
                    weeksCounted: weeksAvailable,
                    firstBlock: 0,
                    speedWork: false,
                    windowWeeks: windowWeeks,
                    retestDate: benchmarkDate(subject: subject, feasibility: feasibility, today: today, calendar: calendar)
                )
                // RC-2: a time goal short of the time-goal rows can be no better than Stretch.
                if !feasibility.timeGoalReady, check.verdict == .realistic { check.verdict = .stretch }
                timeGoal = check
                if check.verdict == .realistic {
                    sentences.append(greenSentence(goal, feasibility: feasibility, subject: subject, today: today, calendar: calendar))
                    if let forecast, !check.noAnchor {
                        sentences.append("Your likely finish is \(CoachFormat.roughClock(forecast.low))-\(CoachFormat.roughClock(forecast.high)); about 2 in 3 runners land inside that range.")
                    }
                } else {
                    verdict = .amber
                    sentences += eventTimeSentences(goal, check: check, weeksAvailable: weeksAvailable, forecast: forecast, calendar: calendar)
                    if check.verdict == .unlikely, let forecast {
                        alternatives.append(GoalAlternative(goal: retimed(goal, forecast.central), label: "Aim for \(CoachFormat.roughClock(forecast.central))", status: .green))
                    }
                }
                if check.provisional, !check.noAnchor, let date = check.retestDate {
                    sentences.append("Provisional: I'll confirm this target after your first test around \(CoachFormat.date(date, calendar: calendar)).")
                }
            } else {
                sentences.append(greenSentence(goal, feasibility: feasibility, subject: subject, today: today, calendar: calendar))
            }
            if !timeFit.isEmpty {
                verdict = worse(verdict, .amber)
                sentences += timeFit
            }
        }

        // PZ-6c: the cut-off, from the long-run pace or the forecast's slow end.
        var cutoffAtRisk = false
        if let cutoff = goal.cutoffSeconds, cutoff > 0 {
            let estimate = input.paceKnown ? goal.distance.meters / 1_000 * input.pace * 1.10 : nil
            if let estimate, estimate > cutoff {
                cutoffAtRisk = true
                sentences.append("At your long-run pace you'd finish around \(CoachFormat.roughClock(estimate)), after the \(CoachFormat.roughClock(cutoff)) cut-off. I'll plan walk breaks, and a race with a later cut-off would suit you better.")
            } else if let forecast, forecast.high > cutoff {
                cutoffAtRisk = true
                sentences.append("Your likely finish is close to the \(CoachFormat.roughClock(cutoff)) cut-off. Walk breaks from the start keep you steady; a race with a later cut-off would take the pressure off.")
            }
            if cutoffAtRisk { plansRunWalk = true }
        }

        // RC-12: an event plan runs at most 52 weeks; until it starts, a Build Distance plan builds toward it.
        var planStartsOn: Date?
        if weeksAvailable > 52 {
            let length = min(52, feasibility.earliestWeeks + feasibility.bufferWeeks)
            let start = calendar.date(byAdding: .day, value: -7 * length, to: raceDay) ?? raceDay
            planStartsOn = start
            sentences.append("Your race is more than a year away, so its plan starts on \(CoachFormat.date(start, calendar: calendar)). Until then I'll build your distance.")
        }

        if verdict == .red { dropped = true }
        var result = GoalCheck(
            verdict: verdict,
            refusal: nil,
            feasibility: feasibility,
            forecast: forecast,
            timeGoal: timeGoal,
            alternatives: alternatives,
            savedGoalEarliest: nil,
            plansRunWalk: plansRunWalk,
            cutoffAtRisk: cutoffAtRisk,
            canInsist: verdict == .red,
            message: sentences.joined(separator: " ")
        )
        result.planStartsOn = planStartsOn
        result.timeGoalDropped = goal.hasTimeGoal && dropped
        if goal.hasTimeGoal, !dropped, let check = timeGoal, check.verdict != .unlikely, !check.noAnchor {
            result.racePace = forecast?.pace
        }
        return result
    }

    /// RC-8a: "This fits. Your long runs reach {target} by {date}, with {buffer} spare for busy or sick weeks."
    static func greenSentence(_ goal: GoalChoice, feasibility: Feasibility, subject: Subject, today: Date, calendar: Calendar) -> String {
        let path = feasibility.pathWeeks ?? feasibility.earliestWeeks
        let reached = date(weeks: path, from: today, calendar: calendar)
        return "This fits. Your long runs reach \(targetText(goal, feasibility: feasibility, subject: subject)) by \(CoachFormat.date(reached, calendar: calendar)), with \(CoachFormat.weeks(feasibility.bufferWeeks)) spare for busy or sick weeks."
    }

    /// RC-8d's reason: the long run (or, when only the volume falls short, the week) and the weeks it takes.
    static func redSentence(_ goal: GoalChoice, feasibility: Feasibility, subject: Subject, weeksAvailable: Int) -> String {
        let unit = subject.unit
        let input = subject.input
        let range = CoachFormat.weekRange(feasibility.earliestWeeks, feasibility.likelyWeeks)
        let article = CoachFormat.article(for: raceName(goal))
        if feasibility.longRunStatus <= feasibility.volumeStatus, feasibility.volumeStatus > .green, feasibility.longRunStatus == .green {
            let volume = CoachFormat.amount(input.volumeNow, in: input.unit, unit: unit)
            let target = CoachFormat.amount(feasibility.targetVolume, in: feasibility.unit, unit: unit)
            return "You run about \(volume) a week now. \(CoachFormat.capitalized(article)) \(raceName(goal)) needs about \(target) a week. I add a little each week with easier weeks between, so that takes \(range) at \(subject.level.name). You have \(CoachFormat.weeks(weeksAvailable))."
        }
        let now = CoachFormat.amount(input.longest, in: input.unit, unit: unit)
        return "You can run \(now) now. \(CoachFormat.capitalized(article)) \(raceName(goal)) needs long runs of about \(targetText(goal, feasibility: feasibility, subject: subject)). I add at most 10% to your longest run, one step at a time with easier weeks between, so that takes \(range) at \(subject.level.name). You have \(CoachFormat.weeks(weeksAvailable))."
    }

    /// RC-8c's messages for an event's Stretch or Unlikely time goal.
    static func eventTimeSentences(_ goal: GoalChoice, check: TimeGoalCheck, weeksAvailable: Int, forecast: RaceForecast?, calendar: Calendar) -> [String] {
        if check.noAnchor { return noAnchorSentences(goal, check: check, calendar: calendar) }
        let name = CoachFormat.goalName(check.goalSeconds)
        let needed = CoachFormat.percent(max(0, check.improvementNeeded))
        let realistic = CoachFormat.percent(check.realisticGain)
        switch check.verdict {
        case .realistic:
            return []
        case .stretch:
            return ["\(CoachFormat.capitalized(name)) is possible with a good block: it needs \(needed), and \(realistic) is typical. I'll mark it as a stretch goal and show your forecast as we go."]
        case .unlikely:
            let retest = check.retestDate.map { " and retest on \(CoachFormat.date($0, calendar: calendar))" } ?? ""
            let aim = forecast.map { CoachFormat.roughClock($0.central) } ?? CoachFormat.roughClock(check.currentEquivalent)
            var sentences = ["\(CoachFormat.capitalized(name)) is \(needed) faster than your current \(CoachFormat.roughClock(check.currentEquivalent)). In \(CoachFormat.weeks(weeksAvailable)), runners like you usually improve about \(realistic), and \(CoachFormat.percent(check.stretchGain)) at best. I'll train you toward \(CoachFormat.roughClock(check.interimGoal ?? check.currentEquivalent))\(retest). Keep \(name) as a stretch goal, or aim for \(aim)?"]
            if check.multiSeason {
                sentences.append("That's more than the \(CoachFormat.percent(check.yearlyCap)) I'd expect in a year, so \(name) is a multi-season goal.")
            }
            return sentences
        }
    }

    // MARK: RC-6

    /// RC-6: R against the realistic and stretch sums over the weeks counted (RC-6a to RC-6d). Without an anchor,
    /// PZ-6a's speed bound (easy pace ÷ 1.5 for a 5K) makes a goal past the yearly cap Unlikely; anything else
    /// stays a provisional stretch until the first test.
    static func timeCheck(
        goalSeconds: Double,
        distance: RaceDistance,
        subject: Subject,
        forecast: RaceForecast?,
        weeksCounted: Int,
        firstBlock: Int,
        speedWork: Bool,
        windowWeeks: Int,
        retestDate: Date?
    ) -> TimeGoalCheck {
        let gains = gainRates(subject: subject)
        let counted = max(0, weeksCounted - max(0, windowWeeks))
        let maxBlocks = subject.assessment.age >= 60 ? max(0, 2 - (speedWork ? subject.blocksDone : 0)) : nil
        let realisticSum = min(gains.cap, blockSum(gain: gains.realistic, weeks: counted, firstBlock: firstBlock, maxBlocks: maxBlocks))
        let stretchSum = min(gains.cap, blockSum(gain: gains.stretch, weeks: counted, firstBlock: firstBlock, maxBlocks: maxBlocks))
        let provisional = subject.assessment.tier == .novice

        guard let forecast else {
            // PZ-6a: the fastest plausible 5K is the easy pace ÷ 1.5.
            var current = 0.0
            if subject.input.paceKnown {
                let fiveK = 5 * subject.input.pace / 1.5
                current = PaceCalculator.equivalent(seconds: fiveK, meters: 5_000, to: distance.meters, k: distance.isHalfOrLonger ? 1.10 : 1.07)
            }
            let needed = current > 0 ? (current - goalSeconds) / current : 0
            var check = TimeGoalCheck(
                improvementNeeded: needed,
                currentEquivalent: current,
                realisticGain: realisticSum,
                stretchGain: stretchSum,
                yearlyCap: gains.cap,
                verdict: needed > gains.cap + 1e-9 ? .unlikely : .stretch,
                interimGoal: nil,
                multiSeason: needed > gains.cap + 1e-9,
                provisional: true
            )
            check.goalSeconds = goalSeconds
            check.weeksCounted = counted
            check.noAnchor = true
            check.retestDate = retestDate
            return check
        }

        let current = forecast.central
        let needed = (current - goalSeconds) / current
        let verdict: TimeVerdict
        if needed <= realisticSum + 1e-9 {
            verdict = .realistic
        } else if needed <= stretchSum + 1e-9 {
            verdict = .stretch
        } else {
            verdict = .unlikely
        }
        var check = TimeGoalCheck(
            improvementNeeded: needed,
            currentEquivalent: current,
            realisticGain: realisticSum,
            stretchGain: stretchSum,
            yearlyCap: gains.cap,
            verdict: verdict,
            interimGoal: verdict == .unlikely ? current * (1 - stretchSum) : nil,
            multiSeason: needed > gains.cap + 1e-9,
            provisional: provisional
        )
        check.goalSeconds = goalSeconds
        check.weeksCounted = counted
        check.retestDate = retestDate
        if speedWork {
            check.blocksNeeded = blocksNeeded(needed, gain: gains.realistic, blockFactor: blockShare(subject.blockLength), firstBlock: firstBlock, cap: gains.cap)
        }
        return check
    }

    /// RC-6a's gains per block and RC-6c's yearly cap, first match top to bottom.
    static func gainRates(subject: Subject) -> (realistic: Double, stretch: Double, cap: Double) {
        let assessment = subject.assessment
        let input = subject.input
        var realistic: Double
        var stretch: Double
        if assessment.overlays.trained {
            (realistic, stretch) = (0.01, 0.02)
        } else if assessment.tier == .novice, input.months < 12 {
            (realistic, stretch) = (0.06, 0.10)
        } else {
            (realistic, stretch) = (0.02, 0.06)
        }
        if input.runs < 3, !subject.doneSpeedWork { stretch = realistic }
        let cap: Double
        if assessment.overlays.trained {
            cap = 0.04
        } else if input.months < 12 {
            cap = 0.16
        } else if input.runs < 3 {
            cap = 0.11
        } else {
            cap = 0.08
        }
        return (realistic, stretch, cap)
    }

    /// RC-6b: full 12-week blocks, then a leftover of 8-11 weeks as a full block, 4-7 weeks at 2/3 and under 4 at
    /// 1/3, each block earning half the one before.
    static func blockSum(gain: Double, weeks: Int, firstBlock: Int = 0, maxBlocks: Int? = nil) -> Double {
        var total = 0.0
        var left = max(0, weeks)
        var block = firstBlock
        var counted = 0
        while left > 0 {
            if let maxBlocks, counted >= maxBlocks { break }
            let share: Double
            if left >= 12 {
                share = 1
                left -= 12
            } else {
                share = blockShare(left)
                left = 0
            }
            total += gain * pow(0.5, Double(block)) * share
            block += 1
            counted += 1
        }
        return total
    }

    /// A block's share of its gain by length: 8 weeks or more a full block, 4-7 two thirds, under 4 one third.
    static func blockShare(_ weeks: Int) -> Double {
        switch weeks {
        case 8...: 1
        case 4...7: 2.0 / 3.0
        case 1...3: 1.0 / 3.0
        default: 0
        }
    }

    /// RC-6c: the blocks the realistic gains need to reach R, or nil when R passes the yearly cap.
    static func blocksNeeded(_ needed: Double, gain: Double, blockFactor: Double, firstBlock: Int, cap: Double) -> Int? {
        guard needed > 0 else { return 0 }
        guard needed <= cap + 1e-9, gain > 0, blockFactor > 0 else { return nil }
        var total = 0.0
        for count in 1 ... 12 {
            total += gain * blockFactor * pow(0.5, Double(firstBlock + count - 1))
            if total >= needed - 1e-9 { return count }
        }
        return nil
    }

    /// EV-10's first benchmark: the 8th plan week after calibration, before the anchor turns 26 weeks old, and
    /// never in the early window (PZ-3).
    static func benchmarkDate(subject: Subject, feasibility: Feasibility, today: Date, calendar: Calendar) -> Date {
        var weeks = feasibility.calibrationWeeks + 8
        if let anchor = PaceCalculator.anchorInForce(subject.paces, now: today, calendar: calendar) {
            let age = FeasibilityInput.weeksBetween(anchor.date, today, calendar: calendar)
            weeks = min(weeks, max(1, PaceCalculator.anchorWeeks - age - 1))
        }
        if subject.input.earlyWindow { weeks = max(weeks, (feasibility.earlyWindowEndWeeks ?? weeks) + 1) }
        return date(weeks: weeks, from: today, calendar: calendar)
    }

    // MARK: RC-7 and RC-8

    /// RC-7's distance part: Red when the distance lands Red or RC-3's gate and block don't fit; Amber when it lands
    /// Amber or reaches Green only by using the buffer; Green with the buffer to spare.
    static func distanceVerdict(_ feasibility: Feasibility) -> (verdict: GoalVerdict, status: DistanceStatus, bufferOnly: Bool, gateLimited: Bool) {
        guard let available = feasibility.weeksAvailable else {
            return (.green, feasibility.status, false, false)
        }
        if feasibility.status == .red { return (.red, .red, false, false) }
        if let gate = feasibility.gateWeeks, gate + feasibility.blockMinimum > available {
            return (.red, .red, false, true)
        }
        if feasibility.status == .amber { return (.amber, .amber, false, false) }
        if available >= feasibility.earliestWeeks + feasibility.bufferWeeks { return (.green, .green, false, false) }
        return (.amber, .amber, true, false)
    }

    static func worse(_ lhs: GoalVerdict, _ rhs: GoalVerdict) -> GoalVerdict {
        func rank(_ verdict: GoalVerdict) -> Int {
            switch verdict {
            case .green: 0
            case .amber: 1
            case .red: 2
            case .refused: 3
            }
        }
        return rank(lhs) >= rank(rhs) ? lhs : rhs
    }

    /// RC-8d's offers for a Red event, in order: the same date at the longest Green distance (with the next one up
    /// when it lands Amber, as a walk-break finish), the same distance at its earliest Green date, and a run-walk
    /// finish on the date for a 5K or 10K. A Red half or marathon is never offered with walk breaks.
    static func redAlternatives(_ goal: GoalChoice, feasibility: Feasibility, subject: Subject, weeksAvailable: Int, today: Date, calendar: Calendar) -> [GoalAlternative] {
        var alternatives = sameDateAlternatives(goal, subject: subject, weeksAvailable: weeksAvailable, today: today, calendar: calendar)
        if !feasibility.unreachable {
            let greenDate = date(weeks: feasibility.earliestWeeks + feasibility.bufferWeeks, from: today, calendar: calendar)
            var later = goal
            later.eventDate = greenDate
            alternatives.append(GoalAlternative(goal: later, label: "\(goal.distance.name) on \(CoachFormat.date(greenDate, calendar: calendar))", status: .green, earliestDate: greenDate))
        }
        if goal.distance == .fiveK || goal.distance == .tenK, !goal.runWalk {
            var runWalk = goal
            runWalk.runWalk = true
            runWalk.targetSeconds = nil
            let check = self.feasibility(runWalk, subject: subject, weeksAvailable: weeksAvailable, today: today, calendar: calendar)
            if (check.gateWeeks ?? 0) + check.blockMinimum <= weeksAvailable {
                alternatives.append(GoalAlternative(goal: runWalk, label: "\(goal.distance.name) on \(CoachFormat.date(goal.eventDate ?? today, calendar: calendar)) as a run-walk", status: .amber, walkBreaks: true))
            }
        }
        return alternatives
    }

    /// RC-8d's first offer: the same date at the longest Green distance, plus the next one up with walk breaks
    /// when it lands Amber.
    static func sameDateAlternatives(_ goal: GoalChoice, subject: Subject, weeksAvailable: Int, today: Date, calendar: Calendar) -> [GoalAlternative] {
        let day = CoachFormat.date(goal.eventDate ?? today, calendar: calendar)
        var above: (goal: GoalChoice, verdict: GoalVerdict)?
        for distance in CoachGoal.event.distances.filter({ $0 < goal.distance }).sorted(by: >) {
            let shorter = GoalChoice(flavor: .event, distance: distance, eventDate: goal.eventDate)
            let verdict = distanceVerdict(feasibility(shorter, subject: subject, weeksAvailable: weeksAvailable, today: today, calendar: calendar)).verdict
            if verdict == .green {
                var alternatives = [GoalAlternative(goal: shorter, label: "\(distance.name) on \(day)", status: .green)]
                if let above, above.verdict == .amber {
                    alternatives.append(GoalAlternative(goal: above.goal, label: "\(above.goal.distance.name) on \(day), finish with walk breaks", status: .amber, walkBreaks: true))
                }
                return alternatives
            }
            above = (shorter, verdict)
        }
        return []
    }

    /// RC-8e: the long run or the week doesn't fit the runner's time (RC-4 step 2a), with the shorter distance that
    /// does.
    static func timeFitSentences(_ goal: GoalChoice, feasibility: Feasibility, subject: Subject, weeksAvailable: Int?, today: Date, calendar: Calendar) -> [String] {
        guard feasibility.longRunTimeLimited || feasibility.volumeTimeLimited else { return [] }
        let input = subject.input
        let name = raceName(goal)
        let article = CoachFormat.capitalized(CoachFormat.article(for: name))
        var fallback = ""
        for distance in RaceDistance.allCases.filter({ $0 < goal.distance && goal.flavor.distances.contains($0) }).sorted(by: >) {
            var shorter = goal
            shorter.distance = distance
            shorter.targetSeconds = nil
            let check = self.feasibility(shorter, subject: subject, weeksAvailable: weeksAvailable, today: today, calendar: calendar)
            if !check.longRunTimeLimited, !check.volumeTimeLimited, !check.unreachable {
                fallback = " If not, \(CoachFormat.article(for: distance.sentenceName)) \(distance.sentenceName) fits your week."
                break
            }
        }
        if feasibility.longRunTimeLimited, let limit = feasibility.longRunLimitSeconds {
            let target = FeasibilityEngine.meters(feasibility.targetLongRun, unit: feasibility.unit, pace: input.pace) / 1_000 * input.pace
            let minutes = Int((target / 60).rounded(.up))
            let day = subject.intake.longRunDay?.name ?? "your long-run day"
            return ["Your longest free slot is \(Int((limit / 60).rounded())) min. \(article) \(name) needs a long run of about \(minutes) min. Can you free up \(minutes) min on \(day)?\(fallback)"]
        }
        let volume = FeasibilityEngine.meters(feasibility.targetVolume, unit: feasibility.unit, pace: input.pace) / 1_000 * input.pace
        let capacity = feasibility.volumeCapacitySeconds ?? 0
        return ["\(article) \(name) needs about \(Int((volume / 60).rounded(.up))) min of running a week, and your run days hold \(Int((capacity / 60).rounded())) min. Can you add time or a run day?\(fallback)"]
    }

    /// BD-1c, RC-3: the gate sentence when the gate and its block set the earliest date.
    static func gateSentence(_ goal: GoalChoice, feasibility: Feasibility, subject: Subject, today: Date, calendar: Calendar) -> String? {
        guard let gateWeeks = feasibility.gateWeeks, gateWeeks > 0, let gate = FirstAttemptGate.gate(for: goal),
              gateWeeks + feasibility.blockMinimum >= feasibility.earliestWeeks
        else { return nil }
        return "A first \(raceName(goal)) needs \(feasibility.blockMinimum) weeks of training once \(gate.condition(unit: subject.unit)), so the earliest I can plan it is \(CoachFormat.date(feasibility.earliestDate, calendar: calendar))."
    }

    // MARK: Pieces

    static func feasibility(_ goal: GoalChoice, subject: Subject, weeksAvailable: Int?, today: Date, calendar: Calendar) -> Feasibility {
        FeasibilityEngine.evaluate(goal, input: subject.input, firstTimer: subject.firstTimer(at: goal.distance), weeksAvailable: weeksAvailable, now: today, calendar: calendar)
    }

    /// A Severe report whose pause is still on: the runner hasn't said "Ready" yet (AD-13c).
    static func isPausedSevere(_ report: InjuryReport) -> Bool {
        report.level == .severe && report.status.isOpen && report.readyAt == nil && report.returnStart == nil
    }

    /// Whole 7-day blocks from today to race day (RC-7).
    static func weeks(from today: Date, to day: Date, calendar: Calendar) -> Int {
        max(0, (calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: day)).day ?? 0) / 7)
    }

    static func date(weeks: Int, from today: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 7 * weeks, to: today) ?? today
    }

    /// The goal with another target time.
    static func retimed(_ goal: GoalChoice, _ seconds: Double) -> GoalChoice {
        var goal = goal
        goal.targetSeconds = seconds.rounded()
        goal.strongFirstTime = false
        return goal
    }

    /// The race in a sentence: "half marathon", "10K run-walk".
    static func raceName(_ goal: GoalChoice) -> String {
        goal.runWalk ? "\(goal.distance.sentenceName) run-walk" : goal.distance.sentenceName
    }

    /// The goal after "toward": "a half marathon", "a sub-20 5K".
    static func phrase(_ goal: GoalChoice) -> String {
        let name = goal.targetSeconds.map { "\(CoachFormat.goalName($0)) \(goal.distance.sentenceName)" } ?? goal.distance.sentenceName
        return "\(CoachFormat.article(for: name)) \(name)"
    }

    /// RC-2's long-run target in the runner's words. The 5K's is 30 minutes non-stop when that comes before 5 km.
    static func targetText(_ goal: GoalChoice, feasibility: Feasibility, subject: Subject) -> String {
        let unit = subject.unit
        if goal.distance == .fiveK {
            let fiveKm = FeasibilityEngine.amount(meters: 5_000, unit: feasibility.unit, pace: subject.input.pace)
            if feasibility.targetLongRun < fiveKm * 0.999 { return "30 minutes" }
            return CoachFormat.distance(km: 5, mi: 3.1, unit: unit)
        }
        if feasibility.unit == .time {
            return CoachFormat.minutes(feasibility.targetLongRun)
        }
        return CoachFormat.distance(feasibility.targetLongRun, unit: unit, digits: 0)
    }

    /// A result's distance in a sentence: "10K", "half marathon", or "2.6 km".
    static func resultName(_ result: RaceResult, unit: DistanceUnit) -> String {
        for distance in RaceDistance.allCases where abs(result.meters - distance.meters) <= 0.01 * distance.meters {
            return distance.sentenceName
        }
        return CoachFormat.distance(result.meters, unit: unit)
    }
}
