//
//  FeasibilityEngine.swift
//  Wind Run
//

import Foundation

/// RC-3's gate before a first attempt's block.
enum FirstAttemptGate: String, Codable, CaseIterable {
    /// 5K run-walk: a brisk 30-min walk.
    case briskWalk30
    /// 10K run-walk: a brisk 60-min walk.
    case briskWalk60
    /// 10K: 30 min non-stop, 3 times a week.
    case tenK
    /// Half: the early window over and about 5 km 3-4 times a week.
    case half
    /// Marathon: HL-26 and about 24 km a week including a run of about 10 km.
    case marathon

    /// The block minimum after the gate, taper included (RC-3). A first 10K's 13 weeks apply only in an event whose
    /// race leaves room for them; the earliest date always uses 8.
    var blockWeeks: Int {
        switch self {
        case .briskWalk30: 7
        case .briskWalk60, .tenK: 8
        case .half: 12
        case .marathon: 18
        }
    }

    /// The gate for a first attempt at the goal; nil for the mile and a 5K without walk breaks, which have none.
    static func gate(for goal: GoalChoice) -> FirstAttemptGate? {
        switch goal.distance {
        case .mile: nil
        case .fiveK: goal.runWalk ? .briskWalk30 : nil
        case .tenK: goal.runWalk ? .briskWalk60 : .tenK
        case .halfMarathon: .half
        case .marathon: .marathon
        }
    }

    /// "once {condition}" in the gate-limited message.
    func condition(unit: DistanceUnit) -> String {
        switch self {
        case .briskWalk30: "you can walk briskly for 30 minutes"
        case .briskWalk60: "you can walk briskly for 60 minutes"
        case .tenK: "you run 30 minutes non-stop 3 times a week"
        case .half: "your early window is over and you run about \(CoachFormat.distance(5_000, unit: unit)) 3 or 4 times a week"
        case .marathon: "you've run for a year, finished a half or a \(CoachFormat.distance(16_000, unit: unit)) run, and run about \(CoachFormat.distance(24_000, unit: unit)) a week"
        }
    }
}

/// RC-2's readiness rows for a goal, in the plan's unit.
struct ReadinessTargets: Hashable {
    /// The long run is Green at or above `longGreen`, Amber down to `longAmber`, Red below it. With
    /// `continuous`, only a long run without walk breaks is Green, and walk breaks are Amber (the mile and the 5K).
    var longGreen: Double
    var longAmber: Double
    /// The weekly volume is Green at or above `volumeGreen`, Amber down to `volumeAmber`, Red below it. A zero
    /// `volumeGreen` means the goal has no volume row; a zero `volumeAmber` means its row has no Red.
    var volumeGreen: Double
    var volumeAmber: Double
    var continuous: Bool
    /// Marathon time goals also need this many long runs over 20 km in the 16 weeks before the taper.
    var longRunsOver20km: Int

    /// The rows for a goal. `timeRows` picks a half's time-goal row (21 km, 32 km) and a marathon time goal's 4 runs
    /// over 20 km; Speed Work's half always uses the time-goal row (SW-1b), and a Build Distance half builds to its
    /// 21.1 km completion run on 25 km a week (BD-1a, BD-5a). A marathon whose 30 km would take longer than 3 h 30
    /// at easy pace is Green at a 3 h 30 run and Amber from 3 h. Long-run targets stay inside HL-5.
    static func make(for goal: GoalChoice, timeRows: Bool, unit: VolumeUnit, pace: Double) -> ReadinessTargets {
        func distance(_ meters: Double) -> Double { FeasibilityEngine.amount(meters: meters, unit: unit, pace: pace) }
        func time(_ seconds: Double) -> Double { FeasibilityEngine.amount(seconds: seconds, unit: unit, pace: pace) }
        switch goal.distance {
        case .mile:
            return ReadinessTargets(longGreen: distance(1_609.344), longAmber: 0, volumeGreen: 0, volumeAmber: 0, continuous: true, longRunsOver20km: 0)
        case .fiveK:
            return ReadinessTargets(longGreen: min(distance(5_000), time(30 * 60)), longAmber: 0, volumeGreen: time(90 * 60), volumeAmber: 0, continuous: true, longRunsOver20km: 0)
        case .tenK:
            return ReadinessTargets(longGreen: distance(10_000), longAmber: distance(7_000), volumeGreen: distance(15_000), volumeAmber: distance(10_000), continuous: false, longRunsOver20km: 0)
        case .halfMarathon:
            let long: Double
            let volume: Double
            if goal.flavor == .speedWork || (timeRows && goal.flavor == .event) {
                (long, volume) = (21_000, 32_000)
            } else if goal.flavor == .buildDistance {
                (long, volume) = (RaceDistance.halfMarathon.meters, 25_000)
            } else {
                (long, volume) = (16_000, 25_000)
            }
            return ReadinessTargets(longGreen: distance(long), longAmber: distance(12_000), volumeGreen: distance(volume), volumeAmber: distance(15_000), continuous: false, longRunsOver20km: 0)
        case .marathon:
            let slow = 30 * pace > 210 * 60
            return ReadinessTargets(
                longGreen: slow ? time(210 * 60) : distance(30_000),
                longAmber: slow ? time(180 * 60) : distance(25_000),
                volumeGreen: distance(40_000),
                volumeAmber: distance(30_000),
                continuous: false,
                longRunsOver20km: timeRows ? 4 : 0
            )
        }
    }

    /// The long run's status. `session` is the whole run-walk session, which covers the distance with walk breaks.
    /// The mile is Amber with walk breaks and never Red; the 5K is Amber when a session with walk breaks covers it,
    /// Red when none does.
    func longStatus(_ value: Double, walking: Bool, session: Double) -> DistanceStatus {
        let green = longGreen * 0.999
        if continuous {
            if !walking, value >= green { return .green }
            if volumeGreen == 0 { return .amber }
            return max(value, session) >= green ? .amber : .red
        }
        if value >= green { return .green }
        return value >= longAmber * 0.999 ? .amber : .red
    }

    func volumeStatus(_ value: Double) -> DistanceStatus {
        guard volumeGreen > 0 else { return .green }
        if value >= volumeGreen * 0.999 { return .green }
        if volumeAmber == 0 { return .amber }
        return value >= volumeAmber * 0.999 ? .amber : .red
    }
}

/// A week of the feasibility simulation (RC-4), in the plan's unit.
struct ProjectedWeek: Hashable {
    enum Kind: String, Hashable {
        /// An open injury report's plan or a return ramp: nothing grows (RC-4 step 2b).
        case held
        case walkStage
        case ladder
        case calibration
        case newLongest
        case heldLongRun
        case stepBack
    }

    var kind: Kind
    /// The week's long run; on the walk stage and the ladder, the longest continuous running.
    var longRun: Double
    /// P-L30 at the week's end.
    var longest: Double
    var volume: Double
    var runs: Int
    /// On the walk stage or the ladder, runs have walk breaks.
    var walking: Bool
    /// The longest session, walking included.
    var session: Double
    /// The early window (TI-3) is over by the week's end.
    var windowOver: Bool
    /// Months of regular running by the week's end.
    var months: Double

    var isLoading: Bool { kind == .newLongest || kind == .heldLongRun }
}

/// What the feasibility simulation starts from (RC-4 step 1): the runner's numbers now, in the plan's unit.
struct FeasibilityInput: Hashable {
    var unit: VolumeUnit
    /// The easy pace for conversions, RunnerAssessor's slow fallback when there is none.
    var pace: Double
    /// An easy pace exists, so the time fit runs (RC-4 step 2a).
    var paceKnown: Bool
    var level: CommitmentLevel
    var recovery: RecoveryTier
    var riskHigh: Bool
    var tier: RunnerTier
    var age: Int
    var runsCap: Int
    var runDays: Int
    var v0: Double
    /// P-L30 now.
    var longest: Double
    /// The next loading week's base: the last loading week's planned volume, or done if lower (CL-1).
    var base: Double
    /// The weekly volume now: the mean of the last loading weeks, or V0.
    var volumeNow: Double
    var runs: Int
    var position: Int
    var loadingInRow: Int
    var weeksSinceRunAdded: Int?
    /// Weeks an open injury report's plan or a return ramp takes first (RC-4 step 2b).
    var heldWeeks: Int
    /// The walk stage or the ladder, while it lasts (TI-2, BD-2).
    var ladder: LadderState?
    var calibrationWeeks: Int
    /// Weeks left in the injury window (TI-3c), counted from the end of the held weeks when it hasn't started.
    var injuryWindowWeeks: Int
    /// Weeks left in an RB-6 level drop.
    var levelDropWeeks: Int
    var months: Double
    var earlyWindow: Bool
    var creditedWeeks: Double
    var creditedMeters: Double
    /// A finished half or a run of 16 km or more (HL-26).
    var halfDone: Bool
    var runs30: Bool
    var walksBriskly30: Bool
    /// Logged long runs over 20 km in the last 16 weeks (RC-2's marathon time-goal row).
    var longRunsOver20km: Int
    /// Straight weeks of 3 or more runs, intake's credit included (HL-12).
    var steadyWeeks: Int
    /// IN-12's longest time on the long-run day, and on each offered run day.
    var longRunLimitSeconds: Double?
    var dayLimitsSeconds: [Double]

    /// The input at intake, before any run is logged.
    init(intake: CoachIntake, assessment: RunnerAssessment, paces: TrainingPaces, level: CommitmentLevel, injuries: [InjuryReport] = [], now: Date, calendar: Calendar) {
        let start = assessment.start
        unit = start.volumeUnit
        pace = paces.easyPace ?? intake.easyPace ?? RunnerAssessor.fallbackPace
        paceKnown = paces.easyPace != nil || intake.easyPace != nil
        self.level = level
        recovery = assessment.recoveryTier
        riskHigh = assessment.risk.isHigh
        tier = assessment.tier
        age = assessment.age
        runsCap = assessment.runsCap
        runDays = intake.runDays.count
        v0 = start.v0
        longest = start.planningLongest.amount(in: start.volumeUnit)
        base = start.v0
        volumeNow = start.v0
        runs = start.runsPerWeek
        position = 0
        loadingInRow = 0
        weeksSinceRunAdded = nil
        ladder = assessment.starterEntry.map(LadderCoach.initialState(for:))
        calibrationWeeks = start.calibrates ? Progression.calibrationWeeks : 0
        (heldWeeks, injuryWindowWeeks) = FeasibilityInput.injuryWeeks(injuries, now: now, calendar: calendar)
        levelDropWeeks = FeasibilityInput.weeksUntil(assessment.recovery.levelDropUntil, from: now, calendar: calendar)
        months = assessment.monthsRunning
        earlyWindow = assessment.overlays.earlyWindow
        creditedWeeks = assessment.overlays.creditedWeeks
        creditedMeters = assessment.overlays.creditedMeters
        let reported = [intake.lastFourWeeks?.longest, intake.beforeBreak?.longest]
            .compactMap { $0?.value(in: .distance, pace: intake.easyPace ?? RunnerAssessor.fallbackPace) }
            .max() ?? 0
        halfDone = intake.finishedHalf == true
            || (intake.goal.distance.isHalfOrLonger && (intake.finished == .yesRecently || intake.finished == .yesLongerAgo))
            || reported >= 16_000
        runs30 = assessment.runs30Minutes
        walksBriskly30 = intake.walksBriskly30 == true || assessment.runs30Minutes || (intake.longestNonStop.map { $0 != .underOneMinute } ?? false)
        longRunsOver20km = 0
        let history = intake.history ?? .notYet
        let recentRuns = intake.lastFourWeeks?.runsPerWeek ?? 0
        steadyWeeks = (recentRuns >= 3 && history >= .threeToTwelveMonths) || (history >= .oneToTwoYears && recentRuns >= 2) ? 10 : 0
        (longRunLimitSeconds, dayLimitsSeconds) = FeasibilityInput.timeLimits(intake)
    }

    /// The input for a re-run from the logs (RC-4 step 1, EF-1, BD-5a), projecting from plan week `index`.
    init(state: CoachState, runs logged: [LoggedRun], fromWeek index: Int, now: Date, calendar: Calendar) {
        let assessment = state.assessment
        let sessions = LoadMetrics.sessions(from: logged)
        let weekStart = state.weekStart(index, calendar: calendar)
        unit = state.volumeUnit
        pace = state.paces.easyPace ?? state.intake.easyPace ?? RunnerAssessor.fallbackPace
        paceKnown = state.paces.easyPace != nil
        level = state.level
        recovery = assessment.recoveryTier
        riskHigh = assessment.risk.isHigh
        tier = assessment.tier
        age = assessment.age
        runsCap = assessment.runsCap
        runDays = state.intake.runDays.count
        v0 = state.v0
        longest = LoadMetrics.longest(
            before: weekStart,
            sessions: sessions,
            seed: WeekPlanner.seed(for: state),
            countFrom: state.gap?.startedAt,
            ceiling: state.gap.map(\.referenceLongRun),
            capOnly: WeekPlanner.raceRunIDs(state),
            calendar: calendar
        ).amount(in: state.volumeUnit)
        let loading = state.weeks
            .filter { $0.plan.index < index && ($0.plan.kind == .loading || $0.plan.kind == .hold) }
            .map { record -> Double in
                let done = LoadMetrics.doneVolume(week: record.plan.index, planStart: state.startDate, sessions: sessions, unit: state.volumeUnit, pace: state.paces.easyPace, calendar: calendar)
                return min(record.plan.plannedVolume, done)
            }
        base = loading.last ?? state.v0
        let recent = Array(loading.suffix(4))
        volumeNow = recent.isEmpty ? state.v0 : recent.reduce(0, +) / Double(recent.count)
        runs = state.cycle.runsPerWeek
        position = state.cycle.position
        loadingInRow = state.cycle.loadingInRow
        weeksSinceRunAdded = state.cycle.lastRunAddedWeek.map { index - $0 }
        ladder = state.ladder.flatMap { $0.form == .done ? nil : $0 }
        let calibrationEnd = Progression.calibrationWeeks + WeekPlanner.extraCalibrationWeeks(state)
        calibrationWeeks = assessment.start.calibrates ? max(0, calibrationEnd - index) : 0
        var (held, window) = FeasibilityInput.injuryWeeks(state.injuries, now: weekStart, calendar: calendar)
        if let ramp = state.gap, ramp.step > 0 {
            held = max(held, Int(((1 - ramp.share) / ramp.step - 1e-9).rounded(.up)))
        }
        heldWeeks = held
        injuryWindowWeeks = window
        levelDropWeeks = FeasibilityInput.weeksUntil(assessment.recovery.levelDropUntil, from: weekStart, calendar: calendar)
        let weeksSoFar = Double(max(0, index))
        months = assessment.monthsRunning + weeksSoFar / CoachLimits.weeksPerMonth
        earlyWindow = assessment.overlays.earlyWindow
        let regular = RunnerAssessor.loggedRegularRunning(state: state, sessions: sessions, before: weekStart, calendar: calendar)
        creditedWeeks = assessment.overlays.creditedWeeks + regular.weeks
        creditedMeters = assessment.overlays.creditedMeters + regular.meters
        let intakeInput = FeasibilityInput.intakeFlags(state.intake, assessment: assessment)
        halfDone = intakeInput.halfDone || sessions.contains { $0.meters >= 16_000 }
        runs30 = assessment.runs30Minutes || state.ladder?.form == .done || QualityPlanner.ranThirtyMinutes(logged)
        walksBriskly30 = intakeInput.walksBriskly30 || runs30 || (state.ladder.map { $0.form != .walkStage } ?? false)
        let sixteenWeeksAgo = calendar.date(byAdding: .day, value: -16 * 7, to: weekStart) ?? weekStart
        longRunsOver20km = sessions.filter { $0.start >= sixteenWeeksAgo && $0.start < weekStart && $0.meters > 20_000 }.count
        steadyWeeks = QualityPlanner.steadyWeeks(state: state, runs: logged, now: now, calendar: calendar)
        (longRunLimitSeconds, dayLimitsSeconds) = FeasibilityInput.timeLimits(state.intake)
    }

    /// HL-26's half and the brisk walk, from intake's answers.
    static func intakeFlags(_ intake: CoachIntake, assessment: RunnerAssessment) -> (halfDone: Bool, walksBriskly30: Bool) {
        let reported = [intake.lastFourWeeks?.longest, intake.beforeBreak?.longest]
            .compactMap { $0?.value(in: .distance, pace: intake.easyPace ?? RunnerAssessor.fallbackPace) }
            .max() ?? 0
        let half = intake.finishedHalf == true
            || (intake.goal.distance.isHalfOrLonger && (intake.finished == .yesRecently || intake.finished == .yesLongerAgo))
            || reported >= 16_000
        let walks = intake.walksBriskly30 == true || assessment.runs30Minutes || (intake.longestNonStop.map { $0 != .underOneMinute } ?? false)
        return (half, walks)
    }

    /// IN-12's limits: the long-run day's, or the longer of the two without one, and each offered day's.
    static func timeLimits(_ intake: CoachIntake) -> (Double?, [Double]) {
        guard intake.weekdayMaxSeconds != nil || intake.weekendMaxSeconds != nil else { return (nil, []) }
        let longDay = intake.longRunDay.flatMap { intake.maxSeconds(on: $0) }
            ?? [intake.weekdayMaxSeconds, intake.weekendMaxSeconds].compactMap { $0 }.max()
        let days = intake.runDays.sorted().compactMap { intake.maxSeconds(on: $0) }
        return (longDay, days)
    }

    /// Whole weeks from `date` until `end`, rounded up; 0 when it has passed.
    static func weeksUntil(_ end: Date?, from date: Date, calendar: Calendar) -> Int {
        guard let end, end > date else { return 0 }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: end)).day ?? 0
        return Int((Double(days) / 7).rounded(.up))
    }

    /// RC-4 step 2b: the weeks the open reports' plans take first, and the injury window after them. An end that
    /// isn't known yet is assumed at the next weekly check.
    static func injuryWeeks(_ injuries: [InjuryReport], now: Date, calendar: Calendar) -> (held: Int, window: Int) {
        var held = 0
        var window = 0
        for report in injuries {
            if report.status.isOpen || { if case .cleared = report.status { return true } else { return false } }() {
                switch report.level {
                case .mild:
                    // The current week and AD-14a's holding week after it clears.
                    held = max(held, report.status.isOpen ? 2 : 1)
                case .intense:
                    let plan = report.recoveryPlan ?? .standard
                    let rampWeeks = plan.rampStep.map { Int(((1 - plan.reducedShare) / $0 - 1e-9).rounded(.up)) } ?? 0
                    let total = plan.restWeeks + plan.reducedWeeks + rampWeeks + plan.repeatedRampWeeks.count + (report.recoveryStart == nil ? 1 : 0)
                    let done = report.recoveryStart.map { weeksBetween($0, now, calendar: calendar) } ?? 0
                    held = max(held, max(1, total - done))
                case .severe:
                    let settings = report.returnPlan
                    let share = settings?.share ?? 0.5
                    let step = settings?.rampStep ?? 0.25
                    let ramp = step > 0 ? Int(((1 - share) / step - 1e-9).rounded(.up)) : 0
                    let returnWeeks = (settings?.weeks ?? 2) + ramp
                    let done = report.returnStart.map { weeksBetween($0, now, calendar: calendar) } ?? 0
                    held = max(held, (report.returnStart == nil ? 1 : 0) + max(0, returnWeeks - done))
                }
            }
            if report.everIntenseOrSevere {
                if let first = report.firstRunBack {
                    window = max(window, InjuryCoach.windowWeeks - weeksBetween(first, now, calendar: calendar))
                } else if !report.status.isClosed {
                    window = max(window, InjuryCoach.windowWeeks)
                }
            }
        }
        return (held, max(0, window))
    }

    static func weeksBetween(_ start: Date, _ end: Date, calendar: Calendar) -> Int {
        max(0, (calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0) / 7)
    }
}

/// The feasibility engine (RC-4): the plan simulated week by week on the level's cycle inside the hard limits.
/// Like the RC-5 table, it never lets HL-6's 60% long-run share hold a step: that rule moves volume between runs,
/// and the volume path already counts the weekly growth.
enum FeasibilityEngine {
    /// Weeks simulated: three years, past any plan the app builds (RC-12).
    static let horizonWeeks = 160

    static func amount(meters: Double, unit: VolumeUnit, pace: Double) -> Double {
        unit == .distance ? meters : meters / 1_000 * pace
    }

    static func amount(seconds: Double, unit: VolumeUnit, pace: Double) -> Double {
        unit == .time ? seconds : (pace > 0 ? seconds / pace * 1_000 : 0)
    }

    static func meters(_ value: Double, unit: VolumeUnit, pace: Double) -> Double {
        unit == .distance ? value : (pace > 0 ? value / pace * 1_000 : 0)
    }

    /// HL-14's ceiling for the simulation: the higher of V0, the Green volume + 10% and the completion week
    /// (the goal's long run plus each other run at 20 min).
    static func volumeCeiling(_ targets: ReadinessTargets, input: FeasibilityInput) -> Double {
        let twenty = amount(seconds: CoachLimits.minimumRunSeconds, unit: input.unit, pace: input.pace)
        let completion = targets.longGreen + Double(max(0, input.runs - 1)) * twenty
        return max(input.v0, targets.volumeGreen * 1.10, completion)
    }

    // MARK: Simulation

    /// The weeks ahead, as the planner would build them if every session were done: the injury plan, the walk
    /// stage or ladder, calibration, then the level's cycle (CL-1, CL-2, HL-1, HL-4, HL-9, HL-11, HL-14, TI-3c,
    /// RB-3, RB-6). The long run holds at `longCap` once there, and the time fit caps both paths (RC-4 step 2a).
    static func project(_ input: FeasibilityInput, longCap: Double, volumeCeiling: Double, weeks horizon: Int) -> [ProjectedWeek] {
        let unit = input.unit
        let pace = input.pace
        let thirty = amount(seconds: 30 * 60, unit: unit, pace: pace)
        let longLimit = input.paceKnown ? input.longRunLimitSeconds.map { amount(seconds: $0, unit: unit, pace: pace) } : nil
        let capacityFor: (Int) -> Double? = { runs in
            guard input.paceKnown, !input.dayLimitsSeconds.isEmpty else { return nil }
            let best = input.dayLimitsSeconds.sorted(by: >).prefix(max(1, runs))
            return amount(seconds: best.reduce(0, +), unit: unit, pace: pace)
        }

        var weeks: [ProjectedWeek] = []
        var longest = input.longest
        var base = input.base
        var runs = input.runs
        var position = input.position
        var loadingInRow = input.loadingInRow
        var sinceRunAdded = input.weeksSinceRunAdded ?? 99
        var ladder = input.ladder
        var calibrationLeft = input.calibrationWeeks
        var heldLeft = input.heldWeeks
        var windowLeft = input.injuryWindowWeeks
        var dropLeft = input.levelDropWeeks
        var creditedWeeks = input.creditedWeeks
        var creditedMeters = input.creditedMeters
        var windowOver = !input.earlyWindow
        var months = input.months
        let stepWeeks = input.riskHigh || input.age >= 65 ? 2 : 1

        for _ in 0 ..< horizon {
            months += 1 / CoachLimits.weeksPerMonth
            var week: ProjectedWeek
            if heldLeft > 0 {
                heldLeft -= 1
                week = ProjectedWeek(kind: .held, longRun: longest, longest: longest, volume: base, runs: runs, walking: ladder != nil, session: longest, windowOver: windowOver, months: months)
            } else if var current = ladder {
                week = ladderWeek(&current, runs: &runs, input: input, stepWeeks: stepWeeks, months: months, windowOver: windowOver)
                if current.form == .done {
                    ladder = nil
                    longest = thirty
                    base = 3 * thirty
                    runs = max(runs, 3)
                } else {
                    ladder = current
                }
            } else if calibrationLeft > 0 {
                calibrationLeft -= 1
                week = ProjectedWeek(kind: .calibration, longRun: longest, longest: longest, volume: 0.9 * input.v0, runs: runs, walking: false, session: longest, windowOver: windowOver, months: months)
            } else {
                var level = input.level
                if dropLeft > 0 { level = level.lower }
                if windowLeft > 0 { level = min(level.lower, .steady) }
                let cycle = CycleWeek.cycle(for: level, stepBackEveryThird: input.recovery.stepsBackEveryThird, twoWeekHold: windowLeft > 0)
                var cycleWeek = cycle[position % cycle.count]
                if cycleWeek.isLoading, loadingInRow >= CoachLimits.loadingWeeksInRow { cycleWeek = .stepBack }
                if cycleWeek == .stepBack {
                    position = 0
                    loadingInRow = 0
                    let long = CoachLimits.stepBackLongRun * longest
                    week = ProjectedWeek(kind: .stepBack, longRun: long, longest: longest, volume: CoachLimits.stepBackVolume * base, runs: runs, walking: false, session: long, windowOver: windowOver, months: months)
                } else {
                    let fullHold = cycleWeek == .heldLongRun && input.riskHigh
                    var volume = fullHold ? base : base * (1 + level.loadingRate)
                    var long = longest
                    if cycleWeek == .newLongest {
                        long = min(longest * CoachLimits.sessionGrowth, max(longCap, longest))
                    }
                    if !windowOver, creditedWeeks < CoachLimits.earlyWindowWeeks {
                        // HL-11: in the first 12 weeks of regular running, runs stay at 30 minutes or less.
                        long = min(long, max(thirty, longest))
                        volume = min(volume, max(Double(runs) * thirty, base))
                    }
                    if let longLimit { long = min(long, max(longLimit, 0)) }
                    if volume >= volumeCeiling { volume = max(volumeCeiling, base) }
                    if let capacity = capacityFor(maxRuns(input)) { volume = min(volume, max(capacity, base)) }
                    position += 1
                    loadingInRow += 1
                    sinceRunAdded += 1
                    if position == 1, canAddRun(input, runs: runs, level: level), sinceRunAdded >= 4, runs >= 1,
                       (volume - long) / Double(max(1, runs - 1)) > long * CoachLimits.otherRunShare {
                        runs += 1
                        sinceRunAdded = 0
                    }
                    let isNew = long > longest + 1e-9
                    longest = max(longest, long)
                    base = volume
                    week = ProjectedWeek(kind: isNew ? .newLongest : .heldLongRun, longRun: long, longest: longest, volume: volume, runs: runs, walking: false, session: long, windowOver: windowOver, months: months)
                }
                windowLeft = max(0, windowLeft - 1)
            }
            dropLeft = max(0, dropLeft - 1)
            if week.kind != .walkStage {
                creditedWeeks += 1
                creditedMeters += meters(week.volume, unit: unit, pace: pace)
            }
            if !windowOver, creditedWeeks >= CoachLimits.earlyWindowWeeks, creditedMeters >= CoachLimits.earlyWindowMeters {
                windowOver = true
            }
            week.windowOver = windowOver
            weeks.append(week)
        }
        return weeks
    }

    /// The most runs a week the plan can reach: the level's target inside HL-9 and the days offered (BD-3c).
    static func maxRuns(_ input: FeasibilityInput) -> Int {
        let levelCap: Int
        switch input.level {
        case .gentle: levelCap = input.runs
        case .steady: levelCap = input.tier == .novice ? 3 : (input.tier == .regular ? 4 : 5)
        case .ambitious: levelCap = input.runsCap
        }
        return max(input.runs, min(levelCap, input.runsCap, input.runDays == 0 ? 5 : input.runDays, 5))
    }

    static func canAddRun(_ input: FeasibilityInput, runs: Int, level: CommitmentLevel) -> Bool {
        let levelCap: Int
        switch level {
        case .gentle: levelCap = runs
        case .steady: levelCap = input.tier == .novice ? 3 : (input.tier == .regular ? 4 : 5)
        case .ambitious: levelCap = input.runsCap
        }
        return runs < min(levelCap, input.runsCap, input.runDays == 0 ? 5 : input.runDays, 5)
    }

    /// One week on the walk stage or the ladder: walks grow 5 min a week to 30, the short run-walk ratios last a
    /// week each (2 at 65+, at risk ≥2 or at Gentle), and ladder steps a week each (2 at 65+ or risk ≥2) with a
    /// repeat week after every 3rd step at Gentle (TI-2a, TI-2b, BD-2b, BD-2c). Every session is done.
    static func ladderWeek(_ ladder: inout LadderState, runs: inout Int, input: FeasibilityInput, stepWeeks: Int, months: Double, windowOver: Bool) -> ProjectedWeek {
        let unit = input.unit
        let pace = input.pace
        let sessions = max(2, min(3, runs))
        switch ladder.form {
        case .walkStage:
            let minutes = max(ladder.walkMinutes, 5)
            let walk = amount(seconds: minutes * 60, unit: unit, pace: pace)
            if minutes >= 30 {
                ladder.form = .runWalk
                ladder.stepIndex = 0
                ladder.weeksOnStep = 0
            } else {
                ladder.walkMinutes = min(30, minutes + 5)
            }
            return ProjectedWeek(kind: .walkStage, longRun: 0, longest: 0, volume: 0, runs: sessions, walking: true, session: walk, windowOver: windowOver, months: months)
        case .runWalk, .done:
            let index = ladder.stepIndex.clamped(to: 0 ... RunWalkStep.lastIndex)
            let step = RunWalkStep.sequence[index]
            let walkSeconds = step.walkSeconds ?? 90
            let running = walkSeconds > 0 ? step.sessionSeconds * step.runSeconds / (step.runSeconds + walkSeconds) : step.sessionSeconds
            let week = ProjectedWeek(
                kind: .ladder,
                longRun: amount(seconds: step.runSeconds, unit: unit, pace: pace),
                longest: amount(seconds: step.runSeconds, unit: unit, pace: pace),
                volume: amount(seconds: Double(sessions) * running, unit: unit, pace: pace),
                runs: sessions,
                walking: walkSeconds > 0,
                session: amount(seconds: step.sessionSeconds, unit: unit, pace: pace),
                windowOver: windowOver,
                months: months
            )
            ladder.weeksOnStep += 1
            var needed = step.isShortRunWalk ? (stepWeeks == 2 || input.level == .gentle ? 2 : 1) : stepWeeks
            if !step.isShortRunWalk, stepWeeks == 1, input.level == .gentle, (index - RunWalkStep.ladderStart + 1) % 3 == 0 {
                needed += 1
            }
            if ladder.weeksOnStep >= needed {
                ladder.weeksOnStep = 0
                if index >= RunWalkStep.lastIndex {
                    ladder.form = .done
                } else {
                    ladder.stepIndex = index + 1
                    ladder.stepsTaken += 1
                }
            }
            runs = sessions
            return week
        }
    }

    // MARK: Reading the simulation

    /// P-L30 after `count` simulated weeks, whether those runs still have walk breaks, and the longest session.
    static func longValue(after count: Int, weeks: [ProjectedWeek], input: FeasibilityInput) -> (value: Double, walking: Bool, session: Double) {
        guard count > 0, !weeks.isEmpty else {
            return (input.longest, input.ladder != nil, input.longest)
        }
        let week = weeks[min(count, weeks.count) - 1]
        return (week.longest, week.walking, max(week.session, week.longest))
    }

    /// The weekly volume after `count` simulated weeks: the last loading week's, or the volume now.
    static func volumeValue(after count: Int, weeks: [ProjectedWeek], input: FeasibilityInput) -> Double {
        weeks.prefix(max(0, count)).last(where: \.isLoading)?.volume ?? input.volumeNow
    }

    static func statuses(after count: Int, targets: ReadinessTargets, weeks: [ProjectedWeek], input: FeasibilityInput) -> (long: DistanceStatus, volume: DistanceStatus) {
        let long = longValue(after: count, weeks: weeks, input: input)
        return (
            targets.longStatus(long.value, walking: long.walking, session: long.session),
            targets.volumeStatus(volumeValue(after: count, weeks: weeks, input: input))
        )
    }

    /// Weeks before the level's cycle: the injury plan, the walk stage or ladder, and calibration.
    static func leadingWeeks(_ weeks: [ProjectedWeek]) -> Int {
        weeks.prefix { [.held, .walkStage, .ladder, .calibration].contains($0.kind) }.count
    }

    /// Weeks until both the long run and the volume are Green (RC-4 steps 3 and 4), counting the leading weeks;
    /// nil when Green never comes inside the simulation.
    static func pathWeeks(_ targets: ReadinessTargets, weeks: [ProjectedWeek], input: FeasibilityInput) -> (long: Int?, volume: Int?) {
        let lead = leadingWeeks(weeks)
        var long: Int?
        var volume: Int?
        for count in 0 ... weeks.count {
            let status = statuses(after: count, targets: targets, weeks: weeks, input: input)
            if long == nil, status.long == .green { long = max(count, lead) }
            if volume == nil, status.volume == .green { volume = max(count, lead) }
            if long != nil, volume != nil { break }
        }
        return (long, volume)
    }

    /// Weeks until RC-3's gate is met, 0 when it already is, nil when it never is inside the simulation.
    static func gateWeeks(_ gate: FirstAttemptGate, weeks: [ProjectedWeek], input: FeasibilityInput) -> Int? {
        let unit = input.unit
        let pace = input.pace
        for count in 0 ... weeks.count {
            let week = count > 0 ? weeks[count - 1] : nil
            let walking = week?.walking ?? (input.ladder != nil)
            let onWalkStage = week.map { $0.kind == .walkStage } ?? (input.ladder?.form == .walkStage)
            let runs = week?.runs ?? input.runs
            let longest = week?.longest ?? input.longest
            let volume = volumeValue(after: count, weeks: weeks, input: input)
            let windowOver = week?.windowOver ?? !input.earlyWindow
            let months = week?.months ?? input.months
            let met: Bool
            switch gate {
            case .briskWalk30:
                met = input.walksBriskly30 || (count > 0 && !onWalkStage)
            case .briskWalk60:
                met = input.runs30 || (count > 0 && !walking && week?.kind != .walkStage)
            case .tenK:
                // Able to run 30 minutes non-stop, on 3 runs a week (RC-11 reads the gate this way).
                met = !walking && runs >= 3
                    && (input.runs30 || longest >= amount(seconds: 30 * 60, unit: unit, pace: pace) * 0.999)
            case .half:
                met = windowOver && !walking && runs >= 3 && volume >= amount(meters: 15_000, unit: unit, pace: pace) * 0.999
            case .marathon:
                let sixteen = amount(meters: 16_000, unit: unit, pace: pace)
                met = months >= 12 - 1e-6
                    && (input.halfDone || weeks.prefix(count).contains { $0.longest >= sixteen * 0.999 } || input.longest >= sixteen * 0.999)
                    && volume >= amount(meters: 24_000, unit: unit, pace: pace) * 0.999
                    && longest >= amount(meters: 10_000, unit: unit, pace: pace) * 0.999
            }
            if met { return count }
        }
        return nil
    }

    /// The first simulated week the early window is over by, nil when it already is or never ends in view.
    static func earlyWindowEnd(_ weeks: [ProjectedWeek], input: FeasibilityInput) -> Int? {
        guard input.earlyWindow else { return nil }
        return weeks.firstIndex(where: \.windowOver).map { $0 + 1 }
    }

    /// The first simulated week HL-12's Q gate can be met by: the early window over and 8 straight weeks of 3 or
    /// more runs (10 at 50+), intake's credit included, every planned run done.
    static func qualityGateWeeks(_ weeks: [ProjectedWeek], input: FeasibilityInput) -> Int? {
        let needed = input.age >= 50 ? 10 : 8
        var streak = input.steadyWeeks
        if streak >= needed, !input.earlyWindow, input.runs30 { return 0 }
        for (index, week) in weeks.enumerated() {
            streak = week.runs >= 3 && !week.walking ? streak + 1 : 0
            if streak >= needed, week.windowOver { return index + 1 }
        }
        return nil
    }

    // MARK: The check

    /// RC-4 for one goal: the paths, earliest and likely weeks, buffer, and the status at taper start when the goal
    /// has a date. `weeksAvailable` is the whole 7-day blocks from today to race day (RC-7).
    static func evaluate(_ goal: GoalChoice, input: FeasibilityInput, firstTimer: Bool, weeksAvailable: Int?, now: Date, calendar: Calendar) -> Feasibility {
        let unit = input.unit
        let pace = input.pace
        let finishRows = ReadinessTargets.make(for: goal, timeRows: false, unit: unit, pace: pace)
        let timeRows: ReadinessTargets? = goal.flavor == .event && goal.hasTimeGoal && goal.distance.isHalfOrLonger
            ? ReadinessTargets.make(for: goal, timeRows: true, unit: unit, pace: pace)
            : nil
        let pathRows = timeRows ?? finishRows
        let ceiling = volumeCeiling(pathRows, input: input)
        let horizon = max((weeksAvailable ?? 0) + 1, horizonWeeks)
        // HL-5: the long run stops at 35 km or 3 h 30, whichever comes first.
        let ceilingLong = min(
            amount(meters: CoachLimits.longRunCeiling.meters, unit: unit, pace: pace),
            amount(seconds: CoachLimits.longRunCeiling.seconds, unit: unit, pace: pace)
        )
        let longCap = min(pathRows.longGreen, ceilingLong)
        let weeks = project(input, longCap: longCap, volumeCeiling: ceiling, weeks: horizon)

        let speed = goal.flavor == .event && goal.hasTimeGoal ? Progression.speedBlockWeeks : 0
        let taper = goal.flavor == .event ? Progression.taperWeeks(for: goal.distance) : 0
        let calibration = input.calibrationWeeks
        let paths = pathWeeks(pathRows, weeks: weeks, input: input)
        let path: Int? = paths.long.flatMap { long in paths.volume.map { max(long, $0) } }
        var earliest = (path ?? horizon) + speed + taper

        var gateWeeksValue: Int?
        var block = 0
        if firstTimer, goal.flavor != .speedWork, let gate = FirstAttemptGate.gate(for: goal) {
            block = gate.blockWeeks
            let weeksToGate = gateWeeks(gate, weeks: weeks, input: input)
            gateWeeksValue = weeksToGate ?? horizon
            earliest = max(earliest, (weeksToGate ?? horizon) + block)
        }
        let buffer = Progression.bufferWeeks(buildWeeks: max(0, earliest - calibration - taper), recovery: input.recovery)
        let likely = Progression.likelyWeeks(earliest: earliest)

        // The status at taper start: with a date, after the weeks before the speed block and taper; without one,
        // when the paths are done.
        let buildWeeks: Int
        if let weeksAvailable {
            buildWeeks = max(0, min(weeks.count, weeksAvailable - speed - taper))
        } else {
            buildWeeks = min(weeks.count, path ?? weeks.count)
        }
        let finish = statuses(after: buildWeeks, targets: finishRows, weeks: weeks, input: input)
        var timeReady = true
        if let timeRows {
            let time = statuses(after: buildWeeks, targets: timeRows, weeks: weeks, input: input)
            timeReady = time.long == .green && time.volume == .green
            if timeRows.longRunsOver20km > 0 {
                let twenty = amount(meters: 20_000, unit: unit, pace: pace)
                let window = weeks.prefix(buildWeeks).suffix(16)
                let count = window.filter { $0.longRun > twenty }.count + (buildWeeks < 16 ? input.longRunsOver20km : 0)
                timeReady = timeReady && count >= timeRows.longRunsOver20km
            }
        }
        let long = longValue(after: buildWeeks, weeks: weeks, input: input)
        let volume = volumeValue(after: buildWeeks, weeks: weeks, input: input)
        let raceAmount = amount(meters: goal.distance.meters, unit: unit, pace: pace)
        let longLimit = input.paceKnown ? input.longRunLimitSeconds : nil
        let capacity = input.paceKnown && !input.dayLimitsSeconds.isEmpty
            ? input.dayLimitsSeconds.sorted(by: >).prefix(maxRuns(input)).reduce(0, +)
            : nil

        var feasibility = Feasibility(
            earliestWeeks: earliest,
            likelyWeeks: likely,
            earliestDate: calendar.date(byAdding: .day, value: 7 * earliest, to: now) ?? now,
            likelyDate: calendar.date(byAdding: .day, value: 7 * likely, to: now) ?? now,
            bufferWeeks: buffer,
            projectedLongest: Load(long.value, in: unit, pace: input.paceKnown ? pace : nil),
            projectedVolume: volume,
            longRunStatus: finish.long,
            volumeStatus: finish.volume,
            status: max(finish.long, finish.volume),
            raceToLongest: long.value > 0 ? raceAmount / long.value : 0,
            longRunTimeLimited: longLimit.map { amount(seconds: $0, unit: unit, pace: pace) < pathRows.longGreen * 0.999 } ?? false,
            volumeTimeLimited: capacity.map { pathRows.volumeGreen > 0 && amount(seconds: $0, unit: unit, pace: pace) < pathRows.volumeGreen * 0.999 } ?? false
        )
        feasibility.unit = unit
        feasibility.targetLongRun = pathRows.longGreen
        feasibility.targetVolume = pathRows.volumeGreen
        feasibility.weeksAvailable = weeksAvailable
        feasibility.heldWeeks = input.heldWeeks
        feasibility.calibrationWeeks = calibration
        feasibility.ladderWeeks = weeks.prefix { $0.kind == .walkStage || $0.kind == .ladder || $0.kind == .held }.filter { $0.kind != .held }.count
        feasibility.gateWeeks = gateWeeksValue
        feasibility.blockMinimum = block
        feasibility.timeGoalReady = timeReady
        feasibility.longRunLimitSeconds = longLimit
        feasibility.volumeCapacitySeconds = capacity
        feasibility.unreachable = path == nil
        feasibility.earlyWindowEndWeeks = earlyWindowEnd(weeks, input: input)
        feasibility.pathWeeks = path
        return feasibility
    }
}
