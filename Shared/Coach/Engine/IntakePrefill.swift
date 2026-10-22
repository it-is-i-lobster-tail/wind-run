//
//  IntakePrefill.swift
//  Wind Run
//

import Foundation

/// The runner's answers kept between plans, so the next setup only asks what changed (Brendon, 2026-10-22).
///
/// Stored as JSON in the app's `CoachProfile`, which syncs with runs and plans when iCloud Sync is on.
struct SavedCoachAnswers: Codable, Hashable {
    /// The last setup's answers, with the date each was given.
    var intake: CoachIntake
    /// "Have you finished this distance?" for every distance asked about, since each plan asks it for its own goal.
    var finished: [String: FinishedDistance] = [:]
    var savedAt: Date

    init(intake: CoachIntake, savedAt: Date) {
        self.intake = intake
        self.savedAt = savedAt
        remember(intake, at: savedAt)
    }

    mutating func remember(_ intake: CoachIntake, at date: Date) {
        self.intake = intake
        if let answer = intake.finished { finished[intake.goal.distance.rawValue] = answer }
        savedAt = date
    }

    /// The intake for a new plan toward a goal of `flavor`: every saved answer, with the date it was given, and a
    /// fresh goal. Answers that belong to one plan (level, race details, a goal-specific "finished") start empty.
    func newIntake(flavor: CoachGoal, unit: DistanceUnit, now: Date, calendar: Calendar) -> CoachIntake {
        var intake = self.intake
        let previous = intake.goal
        let distance = previous.flavor == flavor && flavor.distances.contains(previous.distance)
            ? previous.distance
            : CoachIntake.defaultDistance(for: flavor)
        intake.goal = CoachIntake.defaultGoal(flavor: flavor, distance: distance, now: now, calendar: calendar)
        intake.goal.runWalk = previous.flavor == flavor && previous.runWalk
        intake.level = nil
        intake.eventDetails = nil
        intake.distanceUnit = unit
        intake.answeredAt = now
        // Age isn't asked or used (Brendon, 2026-10-22), so an answer from an older setup is dropped.
        intake.birthYear = nil
        applyFinished(to: &intake)
        intake.ageBreak(to: now, calendar: calendar)
        return intake
    }

    /// Sets "Have you finished this distance?" from the saved answer for the intake's goal distance.
    ///
    /// Once "Your running so far" has been answered it isn't asked again (Brendon, 2026-10-22), so a distance with no
    /// saved answer counts as not finished yet, and the runs can still turn that into a yes (`IntakePrefill`).
    func applyFinished(to intake: inout CoachIntake) {
        intake.finished = finished[intake.goal.distance.rawValue]
        guard intake.finished == nil else { return }
        if intake.isDone(.history), intake.answerDates[.history] != nil {
            intake.finished = FinishedDistance.no
            intake.markAnswered(.finished, at: intake.answeredAt)
        } else {
            intake.answerDates[.finished] = nil
            intake.skippedSteps.remove(.finished)
        }
    }
}

extension CoachIntake {
    static func defaultDistance(for flavor: CoachGoal) -> RaceDistance {
        flavor == .event ? .tenK : .fiveK
    }

    /// A new goal of `flavor`: race day 16 weeks out for events.
    static func defaultGoal(flavor: CoachGoal, distance: RaceDistance, now: Date, calendar: Calendar) -> GoalChoice {
        var goal = GoalChoice(flavor: flavor, distance: distance)
        if flavor == .event {
            goal.eventDate = calendar.date(byAdding: .weekOfYear, value: 16, to: calendar.startOfDay(for: now))
        }
        return goal
    }

    /// Gives answers with no recorded date, from plans set up before dates were kept, the intake's own date.
    mutating func dateUndatedAnswers() {
        for step in IntakeStep.allCases where answerDates[step] == nil && isAnswered(step) {
            answerDates[step] = answeredAt
        }
    }

    /// Moves a saved break and running history on to `now`: the break began that many more weeks ago, and months of
    /// running grow while there's no break.
    mutating func ageBreak(to now: Date, calendar: Calendar) {
        guard let answered = answerDates[.history] else { return }
        let days = Double(IntakeFlow.days(from: answered, to: now, calendar: calendar))
        guard days >= 7 else { return }
        if let weeks = breakBeganWeeksAgo {
            breakBeganWeeksAgo = min(104, weeks + (days / 7).rounded(.down))
        } else if let history, history > .notYet {
            let months = (monthsRunning ?? history.lowMonths) + days / 30.44
            monthsRunning = months
            if months >= 24 {
                self.history = .overTwoYears
            } else if months >= 12 {
                self.history = .oneToTwoYears
            } else if months >= 3 {
                self.history = max(history, .threeToTwelveMonths)
            }
        }
        answerDates[.history] = now
    }
}

/// A finished workout from Wind Run or Apple Health, for filling setup in.
struct PastWorkout: Hashable {
    enum Activity: Hashable {
        /// A run; `hard` for intervals and other speed sessions.
        case run(hard: Bool)
        case other(ActivityKind)
    }

    var start: Date
    /// Moving time.
    var seconds: Double
    var meters: Double
    var activity: Activity

    init(start: Date, seconds: Double, meters: Double, activity: Activity) {
        self.start = start
        self.seconds = seconds
        self.meters = meters
        self.activity = activity
    }

    var isRun: Bool {
        if case .run = activity { return true }
        return false
    }

    var isHard: Bool { activity == .run(hard: true) }
}

/// What Apple Health has for the runner's body, read on the device when setup opens.
struct HealthBody: Hashable {
    var heightCentimeters: Double?
    var weightKilograms: Double?

    init(heightCentimeters: Double? = nil, weightKilograms: Double? = nil) {
        self.heightCentimeters = heightCentimeters
        self.weightKilograms = weightKilograms
    }
}

/// Fills setup in from Apple Health and logged runs (Brendon, 2026-10-22), so setup only asks what they can't say.
/// An answer the runner gave that still holds always wins; a filled answer counts as given today, so it isn't asked.
enum IntakePrefill {
    static func fill(
        _ intake: inout CoachIntake,
        body: HealthBody,
        workouts: [PastWorkout],
        now: Date,
        calendar: Calendar
    ) {
        let runs = workouts.filter { $0.isRun && $0.start <= now }.sorted { $0.start < $1.start }
        fillBody(&intake, body: body, now: now)
        fillFinished(&intake, runs: runs, now: now, calendar: calendar)
        if hasFourWeeksOfRuns(runs, now: now, calendar: calendar) {
            fillRunningLately(&intake, runs: runs, now: now, calendar: calendar)
        } else {
            if !intake.holds(.lastFourWeeks, now: now, calendar: calendar) {
                fillLastFourWeeks(&intake, runs: runs, now: now, calendar: calendar)
            }
            if !intake.holds(.easyPace, now: now, calendar: calendar) {
                fillEasyPace(&intake, runs: runs, now: now, calendar: calendar)
            }
        }
        fillOtherTraining(&intake, workouts: workouts, now: now, calendar: calendar)
        if intake.runDays.isEmpty {
            intake.runDays = usualRunDays(runs, now: now, calendar: calendar)
        }
    }

    /// Height and weight, where the runner hasn't given them.
    static func fillBody(_ intake: inout CoachIntake, body: HealthBody, now: Date) {
        if intake.heightCentimeters == nil { intake.heightCentimeters = body.heightCentimeters }
        if intake.weightKilograms == nil { intake.weightKilograms = body.weightKilograms }
        if intake.isAnswered(.body), intake.answerDates[.body] == nil { intake.markAnswered(.body, at: now) }
    }

    /// "Have you finished this distance?" from a run at least as long as the goal; "longer ago" past 18 months.
    /// Only a yes is filled: no run of that length may just mean it wasn't logged.
    static func fillFinished(_ intake: inout CoachIntake, runs: [PastWorkout], now: Date, calendar: Calendar) {
        let distance = intake.goal.distance.meters
        if let last = runs.last(where: { $0.meters >= distance * 0.98 }), intake.finished != .yesRecently {
            let recent = (calendar.date(byAdding: .month, value: -18, to: now) ?? now) <= last.start
            if recent || intake.finished == nil || intake.finished == .no {
                intake.finished = recent ? .yesRecently : .yesLongerAgo
                intake.markAnswered(.finished, at: now)
            }
        }
    }

    /// The last 4 weeks (IN-6) from the runs in them. It counts as answered only when every one of the 4 weeks has a
    /// run, so a runner who logs elsewhere is still asked; otherwise it's shown filled in.
    static func fillLastFourWeeks(_ intake: inout CoachIntake, runs: [PastWorkout], now: Date, calendar: Calendar) {
        let weeks = weeklyBlocks(runs, weeks: 4, now: now, calendar: calendar)
        guard weeks.contains(where: { !$0.isEmpty }) else { return }
        intake.lastFourWeeks = recentRunning(runs, endingAt: now, calendar: calendar)
        if weeks.allSatisfy({ !$0.isEmpty }) {
            intake.markAnswered(.lastFourWeeks, at: now)
        } else {
            intake.answerDates[.lastFourWeeks] = nil
            intake.skippedSteps.remove(.lastFourWeeks)
        }
    }

    /// Whether the app has 4 weeks of running: a Wind Run or Health run 28 days ago or more.
    static func hasFourWeeksOfRuns(_ runs: [PastWorkout], now: Date, calendar: Calendar) -> Bool {
        guard let first = runs.first else { return false }
        return IntakeFlow.days(from: first.start, to: now, calendar: calendar) >= 28
    }

    /// Once the app has 4 weeks of running, "Your running lately" isn't asked again (Brendon, 2026-10-22): every
    /// answer on it comes from the runs, gaps and all, and counts as given today. A gap of 4 weeks or more is a break.
    static func fillRunningLately(_ intake: inout CoachIntake, runs: [PastWorkout], now: Date, calendar: Calendar) {
        guard let last = runs.last else { return }
        intake.lastFourWeeks = recentRunning(runs, endingAt: now, calendar: calendar)
        if let began = breakBegan(runs, now: now, calendar: calendar) {
            let weeks = (Double(IntakeFlow.days(from: began, to: now, calendar: calendar)) / 7).rounded(.down)
            intake.breakBeganWeeksAgo = min(104, max(4, weeks))
            intake.beforeBreak = recentRunning(runs, endingAt: began, calendar: calendar)
        } else {
            intake.breakBeganWeeksAgo = nil
            intake.beforeBreak = nil
        }
        // Pace from the latest 8 weeks of running, before a break that's still on.
        let paceEnd = (intake.lastFourWeeks?.runsPerWeek ?? 0) > 0 ? now : last.start
        fillEasyPace(&intake, runs: runs, now: paceEnd, calendar: calendar)
        for step in SetupScreen.runningLately.steps(for: intake) {
            if !intake.isAnswered(step) {
                // Someone logging runs walks and climbs stairs easily.
                switch step {
                case .nonStop: intake.longestNonStop = intake.inferredNonStop
                case .dailyFunction: intake.dailyFunction = .good
                case .briskWalk: intake.walksBriskly30 = true
                default: break
                }
            }
            if intake.isAnswered(step) {
                intake.markAnswered(step, at: now)
            } else {
                intake.markSkipped(step, at: now)
            }
        }
    }

    /// When the latest break of 4 weeks or more began, if it ended (or is still on) within the last 26 weeks: the
    /// start of the run before it.
    static func breakBegan(_ runs: [PastWorkout], now: Date, calendar: Calendar) -> Date? {
        let window = calendar.date(byAdding: .weekOfYear, value: -26, to: now) ?? now
        var next = now
        for run in runs.reversed() {
            guard next >= window else { return nil }
            if IntakeFlow.days(from: run.start, to: next, calendar: calendar) >= 28 { return run.start }
            next = run.start
        }
        return nil
    }

    /// IN-6's answers from the 4 weeks of runs ending at `end`. Weeks with no run don't count toward the weekly range.
    static func recentRunning(_ runs: [PastWorkout], endingAt end: Date, calendar: Calendar) -> RecentRunning {
        let weeks = weeklyBlocks(runs, weeks: 4, now: end, calendar: calendar)
        let count = weeks.reduce(0) { $0 + $1.count }
        guard count > 0 else { return RecentRunning(runsPerWeek: 0, weeklyLow: .distance(meters: 0)) }
        let totals = weeks.filter { !$0.isEmpty }.map { $0.reduce(0) { $0 + $1.meters } }
        let longest = weeks.joined().map(\.meters).max()
        let hard = weeks.joined().filter(\.isHard).count
        let runsPerWeek = min(7, max(1, Int((Double(count) / 4).rounded())))
        var recent = RecentRunning(
            runsPerWeek: runsPerWeek,
            weeklyLow: .distance(meters: totals.min() ?? 0),
            weeklyHigh: (totals.max() ?? 0) > (totals.min() ?? 0) ? .distance(meters: totals.max() ?? 0) : nil,
            longest: longest.map { .distance(meters: $0) },
            hardSessionsPerWeek: min(5, Int((Double(hard) / 4).rounded()))
        )
        if runsPerWeek >= 5 {
            let quarter = weeklyBlocks(runs, weeks: 13, now: end, calendar: calendar)
            recent.fiveRunsForThreeMonths = quarter.allSatisfy { $0.count >= 5 }
        }
        return recent
    }

    /// The usual easy pace (IN-7): the median pace of the last 8 weeks' steady runs of 15 minutes or more, from 3 runs
    /// up, to the nearest 5 seconds per km.
    static func fillEasyPace(_ intake: inout CoachIntake, runs: [PastWorkout], now: Date, calendar: Calendar) {
        let start = calendar.date(byAdding: .day, value: -56, to: now) ?? now
        let paces = runs
            .filter { $0.start >= start && !$0.isHard && $0.seconds >= 15 * 60 && $0.meters >= 1_000 }
            .map { $0.seconds / $0.meters * 1_000 }
            .sorted()
        guard paces.count >= 3 else { return }
        let middle = paces.count / 2
        let median = paces.count % 2 == 0 ? (paces[middle - 1] + paces[middle]) / 2 : paces[middle]
        intake.easyPace = (median / 5).rounded() * 5
        intake.markAnswered(.easyPace, at: now)
    }

    /// Other training (IN-10) isn't asked any more (Brendon, 2026-10-22): it comes from the last 4 weeks of
    /// non-running workouts in Apple Health, and with none it counts as none. The job question goes with it.
    static func fillOtherTraining(_ intake: inout CoachIntake, workouts: [PastWorkout], now: Date, calendar: Calendar) {
        let start = calendar.date(byAdding: .day, value: -28, to: now) ?? now
        var byKind: [ActivityKind: [PastWorkout]] = [:]
        for workout in workouts where workout.start >= start && workout.start <= now {
            if case .other(let kind) = workout.activity { byKind[kind, default: []].append(workout) }
        }
        intake.otherTraining = ActivityKind.allCases.compactMap { kind -> OtherActivity? in
            guard let sessions = byKind[kind], !sessions.isEmpty else { return nil }
            let minutes = sessions.map { $0.seconds / 60 }.sorted()[sessions.count / 2]
            return OtherActivity(
                kind: kind,
                sessionsPerWeek: max(1, Int((Double(sessions.count) / 4).rounded())),
                minutes: min(240, max(10, (minutes / 5).rounded() * 5))
            )
        }
        intake.markAnswered(.otherTraining, at: now)
    }

    /// The weekdays the runner ran on in at least 2 of the last 4 weeks, as a starting point for run days.
    static func usualRunDays(_ runs: [PastWorkout], now: Date, calendar: Calendar) -> Set<Weekday> {
        var weeksByDay: [Weekday: Int] = [:]
        for week in weeklyBlocks(runs, weeks: 4, now: now, calendar: calendar) {
            let days = Set(week.compactMap { Weekday(rawValue: calendar.component(.weekday, from: $0.start)) })
            for day in days { weeksByDay[day, default: 0] += 1 }
        }
        return Set(weeksByDay.filter { $0.value >= 2 }.map(\.key))
    }

    /// The runs in each of the last `weeks` 7-day blocks ending today, oldest first.
    static func weeklyBlocks(_ runs: [PastWorkout], weeks: Int, now: Date, calendar: Calendar) -> [[PastWorkout]] {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return (0 ..< weeks).reversed().map { back in
            let blockEnd = calendar.date(byAdding: .day, value: -7 * back, to: end) ?? end
            let blockStart = calendar.date(byAdding: .day, value: -7, to: blockEnd) ?? blockEnd
            return runs.filter { $0.start >= blockStart && $0.start < blockEnd }
        }
    }
}
