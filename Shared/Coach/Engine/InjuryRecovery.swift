//
//  InjuryRecovery.swift
//  Wind Run
//

import Foundation

/// Where a week falls in an Intense recovery plan or a Severe return (AD-14b, AD-14c).
enum RecoveryStage: Hashable {
    /// Phase 1 of the recovery plan: no running.
    case rest
    /// Phase 2: a share of the pre-injury week.
    case reduced(share: Double)
    /// A Severe return week (0 is the first), at the return's share.
    case returnWeek(number: Int, share: Double)
    /// The ramp back to the pre-injury week (0 is its first week).
    case ramp(position: Int, share: Double)

    /// Share of the pre-injury week, 0 for a week off.
    var share: Double {
        switch self {
        case .rest: 0
        case .reduced(let share), .returnWeek(_, let share), .ramp(_, let share): share
        }
    }

    var isRest: Bool { self == .rest }

    var isRamp: Bool {
        if case .ramp = self { return true }
        return false
    }
}

/// The weeks a recovery plan or return would give, and how many the hard limits add (AD-14b).
struct RecoveryProjection: Hashable {
    var weeks: [RecoveryWeekPreview]
    /// The plan's own length, without HL-1 and HL-2.
    var plannedWeeks: Int

    /// Weeks the safety limits add.
    var addedWeeks: Int { max(0, weeks.count - plannedWeeks) }
}

/// One modelled week: planned, and assumed done as planned (AD-14b's projection).
private struct ModelWeek {
    var volume: Double
    var longRun: Double
    /// Run after a Severe return started: only these count for the return's long run (AD-14c).
    var sinceReturn: Bool
}

extension InjuryCoach {
    /// A projection stops here, so a plan that can't reach the pre-injury week still ends.
    static let projectionLimit = 104

    // MARK: The plan in force

    /// The recovery plan in force: the runner's, or the default (AD-13b: the plan is never left unset).
    static func recoverySettings(_ report: InjuryReport) -> RecoveryPlanSettings {
        (report.recoveryPlan ?? .standard).normalized
    }

    /// The return in force: the runner's, or AD-14c's default for the pause.
    static func returnSettings(_ report: InjuryReport, calendar: Calendar) -> ReturnSettings {
        defaultReturn(for: report, now: report.readyAt ?? report.pauseStart ?? report.reportedAt, calendar: calendar)
    }

    /// AD-14c's default return, or the return the runner already set: 2 weeks; 50% of the pre-injury week after a
    /// pause of 4 weeks or less, else 30%; easy jogging when the pre-injury long run was 30 min or more non-stop and
    /// the pause was 4 weeks or less, else jog/walk; then AD-10's step for the pause's gap tier.
    static func defaultReturn(reportID: UUID, state: CoachState, now: Date, calendar: Calendar) -> ReturnSettings {
        guard let report = state.injuries.first(where: { $0.id == reportID }) else {
            return ReturnSettings(weeks: 2, form: .jogging, share: 0.5, rampStep: GapTier.g1.step)
        }
        return defaultReturn(for: report, now: now, calendar: calendar)
    }

    static func defaultReturn(for report: InjuryReport, now: Date, calendar: Calendar?) -> ReturnSettings {
        if let plan = report.returnPlan { return plan.normalized }
        let days = pauseDays(report, now: now, calendar: calendar)
        let short = days <= 28
        let form: ReturnForm = report.baseline.ranThirtyMinutesNonStop && short ? .jogging : .jogWalk
        return ReturnSettings(weeks: 2, form: form, share: short ? 0.5 : 0.3, rampStep: rampStep(daysOff: days))
    }

    /// AD-10's step for a pause's gap tier: G0 and G1 +25, G2 +20, G3 +15, G4 +10 points a week.
    static func rampStep(daysOff: Int) -> Double {
        let tier = GapTier(daysOff: daysOff)
        return (tier == .g0 ? GapTier.g1 : tier).step
    }

    /// AD-14c: the pause runs from the last run before it to Ready, or to `now` before Ready. Without a calendar the
    /// days are counted in whole 24-hour spans.
    static func pauseDays(_ report: InjuryReport, now: Date, calendar: Calendar?) -> Int {
        let start = report.lastRunBeforePause ?? report.pauseStart ?? report.reportedAt
        let end = report.readyAt ?? now
        guard let calendar else { return max(0, Int((end.timeIntervalSince(start) / 86_400).rounded(.down))) }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0)
    }

    // MARK: Stages

    /// The first plan week of a recovery or return starting on `start`: its own week when it starts on the week's
    /// first two days, else the next one. The days before it run as its first week.
    static func firstWeek(from start: Date, state: CoachState, calendar: Calendar) -> Int {
        let index = max(0, state.weekIndex(on: start, calendar: calendar))
        let offset = calendar.dateComponents([.day], from: state.weekStart(index, calendar: calendar), to: calendar.startOfDay(for: start)).day ?? 0
        return offset <= 1 ? index : index + 1
    }

    /// The plan week the report's recovery or return counts from, or nil when it has none.
    static func firstRecoveryWeek(_ report: InjuryReport, state: CoachState, calendar: Calendar) -> Int? {
        switch report.mode {
        case .recoveryPlan: report.recoveryStart.map { firstWeek(from: $0, state: state, calendar: calendar) }
        case .returning: report.returnStart.map { firstWeek(from: $0, state: state, calendar: calendar) }
        default: nil
        }
    }

    /// Where plan week `index` falls in the report's recovery plan or return, or nil outside one.
    static func stage(_ report: InjuryReport, week index: Int, state: CoachState, calendar: Calendar) -> RecoveryStage? {
        guard let first = firstRecoveryWeek(report, state: state, calendar: calendar) else { return nil }
        let week = max(0, index - first)
        switch report.mode {
        case .recoveryPlan:
            return recoveryStage(week, settings: recoverySettings(report))
        case .returning:
            let settings = returnSettings(report, calendar: calendar)
            let drops = Set(report.returnDropWeeks.map { $0 - first - settings.weeks })
            return returnStage(week, settings: settings, drops: drops, twoWeekHold: state.assessment.age >= 65)
        default:
            return nil
        }
    }

    /// AD-14b's phases: rest, reduced, then the ramp.
    static func recoveryStage(_ week: Int, settings: RecoveryPlanSettings) -> RecoveryStage {
        if week < settings.restWeeks { return .rest }
        if week < settings.restWeeks + settings.reducedWeeks { return .reduced(share: settings.reducedShare) }
        let position = week - settings.restWeeks - settings.reducedWeeks
        return .ramp(position: position, share: rampShare(position, from: settings.reducedShare, step: settings.rampStep, holds: Set(settings.repeatedRampWeeks)))
    }

    /// AD-14c's return weeks, then the ramp with AD-10's drop rule and its 65+ 2-week hold.
    static func returnStage(_ week: Int, settings: ReturnSettings, drops: Set<Int> = [], twoWeekHold: Bool = false) -> RecoveryStage {
        if week < settings.weeks { return .returnWeek(number: week, share: settings.share) }
        let position = week - settings.weeks
        let share = rampShare(position, from: settings.share, step: settings.rampStep, holds: Set(settings.repeatedRampWeeks), drops: drops, twoWeekHold: twoWeekHold)
        return .ramp(position: position, share: share)
    }

    /// The ramp's share in week `position`: a step a week from the phase before it, up to 100%. A repeated week holds
    /// the week after it; a week that met AD-10's drop rule drops the next one a step, never below the start; at 65+
    /// each step is held a week. No step means straight back to 100%.
    static func rampShare(_ position: Int, from start: Double, step: Double?, holds: Set<Int> = [], drops: Set<Int> = [], twoWeekHold: Bool = false) -> Double {
        guard let step, step > 0 else { return 1 }
        var share = start
        var raised = false
        for week in 0 ... max(0, position) {
            if drops.contains(week - 1) {
                share = max(start, share - step)
                raised = false
            } else if holds.contains(week - 1) || (twoWeekHold && raised) {
                raised = false
            } else {
                share = min(1, share + step)
                raised = true
            }
        }
        return (share * 1_000_000).rounded() / 1_000_000
    }

    /// AD-14c's jog/walk: 2 min jogging and 2 walking in the first return week, 3 and 1 after, then 1-min walks while
    /// the jogging doubles each ramp week (6, 12, then 24 min) until the runs are continuous again.
    static func jogWalkPattern(_ stage: RecoveryStage, form: ReturnForm?) -> (run: Double, walk: Double)? {
        guard form == .jogWalk else { return nil }
        switch stage {
        case .returnWeek(let number, _): return number == 0 ? (120, 120) : (180, 60)
        case .ramp(let position, _): return position < 3 ? (360 * pow(2, Double(position)), 60) : nil
        case .rest, .reduced: return nil
        }
    }

    /// A jog/walk return week: the share of the pre-injury running minutes plus the walks, in sessions of 20-30 min
    /// (AD-14c), with runs dropped one at a time to 2 while a session would fall under 20 min (AD-14b).
    static func jogWalkWeek(share: Double, base: Double, factor: Double, runs: Int, unit: VolumeUnit, pace: Double) -> (volume: Double, sessions: Int) {
        let minimum = Scheduler.amount(seconds: CoachLimits.minimumRunSeconds, unit: unit, pace: pace)
        let longest = Scheduler.amount(seconds: 30 * 60, unit: unit, pace: pace)
        let wanted = share * base * factor
        var sessions = max(1, runs)
        while sessions > 2, min(wanted, Double(sessions) * longest) / Double(sessions) < minimum - 0.000_1 { sessions -= 1 }
        return (min(wanted, Double(sessions) * longest), sessions)
    }

    // MARK: A recovery week

    /// The week a recovery or return stage gives, before the hard limits (AD-14b, AD-14c). Every week is easy, with no
    /// Q, strides, tests or new longest run. Runs drop one at a time to 2 while one would fall under 20 min.
    static func recoveryTargets(_ report: InjuryReport, stage: RecoveryStage, context: PlanningContext) -> WeekTargets {
        let state = context.state
        let unit = context.unit
        let pace = context.easyPace ?? Scheduler.fallbackEasyPace
        let base = report.baseline
        let returning = report.mode == .returning
        let kind: WeekKind = returning ? .injuryReturn : .recovery
        let runs = max(1, min(state.cycle.runsPerWeek, state.assessment.runsCap))
        let minimum = Scheduler.amount(seconds: CoachLimits.minimumRunSeconds, unit: unit, pace: pace)
        let percent = CoachFormat.percent(stage.share)

        if stage.isRest {
            // AD-14e: cross-training in phase 1, if pain-free.
            return WeekTargets(
                kind: kind,
                volume: 0,
                runs: 0,
                extras: Array(repeating: .crossTraining, count: min(3, runs)),
                notes: [CoachNote(.injury, "No running this week, because your recovery plan starts with a break from running. Cross-training is fine if it's pain-free.")]
            )
        }

        let settings = returning ? returnSettings(report, calendar: context.calendar) : nil
        let pattern = jogWalkPattern(stage, form: settings?.form)
        let factor = pattern.map { ($0.run + $0.walk) / $0.run } ?? 1
        let form: RunForm = pattern.map { .runWalk(runSeconds: $0.run, walkSeconds: $0.walk) } ?? .continuous
        let because = returning ? "you're coming back from your injury" : "you're following your recovery plan"

        if case .returnWeek = stage, pattern != nil {
            let week = jogWalkWeek(share: stage.share, base: base.weekVolume, factor: factor, runs: runs, unit: unit, pace: pace)
            let session = Load(week.volume / Double(week.sessions), in: unit, pace: pace)
            return WeekTargets(
                kind: kind,
                volume: week.volume,
                runs: week.sessions,
                form: form,
                sessionCap: session,
                notes: [CoachNote(.injury, "Easy jog-walk sessions this week, at \(percent) of your usual week, because \(because).")]
            )
        }

        let volume = stage.share * base.weekVolume * factor
        var longRun: Load? = base.longRun.scaled(by: stage.share)
        if returning, stage.isRamp, let settings {
            longRun = returnLongRun(report, share: stage.share, settings: settings, context: context)
        }
        if let long = longRun, long.amount(in: unit) <= 0 { longRun = nil }

        // HL-2 can hold the week below its share, so the runs are counted on the week it will be; the first week back
        // with nothing in W4max runs at its share (restartVolume).
        let expected = context.w4max > 0 && context.weekCap > 0 ? min(volume, context.weekCap) : volume
        var count = runs
        func easyShare(_ runs: Int) -> Double {
            guard let longRun else { return expected / Double(runs) }
            return runs > 1 ? (expected - min(longRun.amount(in: unit), expected)) / Double(runs - 1) : expected
        }
        while count > 2, easyShare(count) < minimum - 0.000_1 { count -= 1 }
        var sessionCap: Load?
        if expected < 2 * minimum {
            // Too little for a long run: two short runs of the same length.
            longRun = nil
            count = min(2, count)
            sessionCap = Load(expected / Double(count), in: unit, pace: pace)
        }

        let note: String
        if case .returnWeek = stage {
            note = "Easy jogging this week, at \(percent) of your usual week, because \(because)."
        } else {
            note = "Easy runs only this week, at \(percent) of your usual week, because \(because)."
        }
        return WeekTargets(
            kind: kind,
            volume: volume,
            longRun: longRun,
            isNewLongest: false,
            runs: count,
            form: form,
            sessionCap: sessionCap,
            notes: [CoachNote(.injury, note)]
        )
    }

    /// AD-14c: in the ramp the long run grows at most 10% a week from the return weeks' long run, counting only runs
    /// since the return, rounded down to 0.1 km or to the minute, and never past the week's share or the pre-injury
    /// long run.
    static func returnLongRun(_ report: InjuryReport, share: Double, settings: ReturnSettings, context: PlanningContext) -> Load {
        let base = report.baseline.longRun
        let target = base.scaled(by: share)
        guard let start = report.returnStart else { return target }
        let since = LoadMetrics.longest(before: context.weekStart, sessions: context.sessions, seed: nil, countFrom: start, ceiling: base, calendar: context.calendar)
        guard since.meters > 0 || since.seconds > 0 else { return target.capped(at: base.scaled(by: settings.share)) }
        let grown = Load(
            meters: (since.meters * CoachLimits.sessionGrowth).floored(toMultipleOf: 100),
            seconds: (since.seconds * CoachLimits.sessionGrowth).floored(toMultipleOf: 60)
        )
        return target.capped(at: grown).capped(at: base)
    }

    // MARK: Projections (AD-14b's plan screen)

    /// The recovery plan's weeks with HL-1 and HL-2 applied, assuming each week is done as planned. The 4 weeks
    /// before it hold the pre-injury week and long run, as W4max and P-L30 do for about 4 weeks after a report.
    static func recoveryProjection(_ settings: RecoveryPlanSettings, report: InjuryReport, state: CoachState) -> RecoveryProjection {
        let settings = settings.normalized
        if report.baseline.isLadder, ladderActive(state) {
            let restart = ladderRestartStep(report, stepsBack: settings.ladderStepsBack, state: state)
            return ladderProjection(report: report, state: state, restWeeks: settings.restWeeks, holdWeeks: 0, restart: restart)
        }
        let base = report.baseline
        let history = Array(repeating: ModelWeek(volume: base.weekVolume, longRun: base.longRun.amount(in: state.volumeUnit), sinceReturn: false), count: 4)
        let stage: (Int) -> RecoveryStage = { recoveryStage($0, settings: settings) }
        let weeks = simulate(report: report, state: state, history: history, form: nil, stage: stage, limits: true)
        let planned = simulate(report: report, state: state, history: history, form: nil, stage: stage, limits: false)
        return RecoveryProjection(weeks: weeks, plannedWeeks: planned.count)
    }

    /// The Severe return's weeks with every hard limit applied: W4max holds the weeks before the pause, then the
    /// pause's empty weeks, so HL-2 often sets the first ramp weeks; the long run counts only runs since the return.
    static func returnProjection(_ settings: ReturnSettings, report: InjuryReport, state: CoachState, pauseDays days: Int) -> RecoveryProjection {
        let settings = settings.normalized
        if report.baseline.isLadder, ladderActive(state) {
            let restart = ladderRestartStep(report, stepsBack: settings.ladderStepsBack ?? gapStepsBack(days: days), state: state)
            return ladderProjection(report: report, state: state, restWeeks: 0, holdWeeks: settings.weeks, restart: restart)
        }
        let base = report.baseline
        let pauseWeeks = Int((Double(days) / 7).rounded())
        let history = Array(repeating: ModelWeek(volume: base.weekVolume, longRun: base.longRun.amount(in: state.volumeUnit), sinceReturn: false), count: 4)
            + Array(repeating: ModelWeek(volume: 0, longRun: 0, sinceReturn: false), count: pauseWeeks)
        let stage: (Int) -> RecoveryStage = { returnStage($0, settings: settings, twoWeekHold: state.assessment.age >= 65) }
        let weeks = simulate(report: report, state: state, history: history, form: settings.form, stage: stage, limits: true)
        let planned = simulate(report: report, state: state, history: history, form: settings.form, stage: stage, limits: false)
        return RecoveryProjection(weeks: weeks, plannedWeeks: planned.count)
    }

    /// The projection for a report's recovery or return as it stands, with the plan week it counts from.
    static func projection(for report: InjuryReport, state: CoachState, now: Date, calendar: Calendar) -> (projection: RecoveryProjection, firstWeek: Int)? {
        guard let first = firstRecoveryWeek(report, state: state, calendar: calendar) else { return nil }
        switch report.mode {
        case .recoveryPlan:
            return (recoveryProjection(recoverySettings(report), report: report, state: state), first)
        case .returning:
            let days = pauseDays(report, now: now, calendar: calendar)
            return (returnProjection(returnSettings(report, calendar: calendar), report: report, state: state, pauseDays: days), first)
        default:
            return nil
        }
    }

    /// Runs the model week by week until a week reaches 100% with the pre-injury volume and long run back. With
    /// `limits` off it gives the plan's own length.
    private static func simulate(
        report: InjuryReport,
        state: CoachState,
        history start: [ModelWeek],
        form: ReturnForm?,
        stage: (Int) -> RecoveryStage,
        limits: Bool
    ) -> [RecoveryWeekPreview] {
        let unit = state.volumeUnit
        let pace = state.paces.easyPace ?? Scheduler.fallbackEasyPace
        let base = report.baseline.weekVolume
        let baseLong = report.baseline.longRun.amount(in: unit)
        let ceiling = CoachLimits.longRunCeiling.amount(in: unit)
        let runs = max(1, min(state.cycle.runsPerWeek, state.assessment.runsCap))
        let step: Double = unit == .distance ? 100 : 60
        var history = start
        var rows: [RecoveryWeekPreview] = []

        for week in 0 ..< projectionLimit {
            let current = stage(week)
            let share = current.share
            let recent = history.suffix(4)
            let w4max = recent.map(\.volume).max() ?? 0
            var weekCap = LoadMetrics.weekCap(w4max: w4max, unit: unit)
            if unit == .distance, w4max / 1_000 * pace < CoachLimits.smallWeekSeconds {
                weekCap = max(weekCap, w4max + CoachLimits.smallWeekAllowanceSeconds / pace * 1_000)
            }
            let longest = recent.map(\.longRun).max() ?? 0
            let pattern = jogWalkPattern(current, form: form)
            let factor = pattern.map { ($0.run + $0.walk) / $0.run } ?? 1
            var volume = 0.0
            var long = 0.0
            var capped = false
            var hasLongRun = false

            if !current.isRest {
                if case .returnWeek = current, pattern != nil {
                    let jogWalk = jogWalkWeek(share: share, base: base, factor: factor, runs: runs, unit: unit, pace: pace)
                    volume = jogWalk.volume
                    long = volume / Double(jogWalk.sessions)
                } else {
                    volume = share * base * factor
                    long = share * baseLong
                    hasLongRun = true
                    if form != nil, current.isRamp, limits {
                        // AD-14c: ≤10% a week from the return's own long runs, rounded down.
                        if let since = recent.filter(\.sinceReturn).map(\.longRun).max(), since > 0 {
                            let grown = (since * CoachLimits.sessionGrowth).floored(toMultipleOf: step)
                            if grown < long - 0.000_1 {
                                long = grown
                                capped = true
                            }
                        }
                    }
                }
                if limits {
                    // The first week back after a pause or a long rest has no W4max to compare with: it runs at the
                    // plan's share, as AD-10's first ramp week does (restartVolume).
                    if w4max > 0, weekCap > 0, volume > weekCap + 0.000_1 {
                        volume = weekCap
                        capped = true
                    }
                    if hasLongRun, longest > 0, long > longest * CoachLimits.sessionGrowth + 0.000_1 {
                        long = longest * CoachLimits.sessionGrowth
                        capped = true
                    }
                }
                long = min(long, ceiling)
            }

            let runningVolume = volume / factor
            history.append(ModelWeek(volume: unit == .time ? runningVolume : volume, longRun: long, sinceReturn: form != nil))
            let label = current.isRest ? "Week \(week + 1): no running" : "Week \(week + 1): \(CoachFormat.percent(share))"
            let shownVolume = pattern == nil ? volume : (unit == .time ? runningVolume : runningVolume / 1_000 * pace)
            rows.append(RecoveryWeekPreview(
                weekNumber: week + 1,
                share: share,
                volume: shownVolume,
                longRun: hasLongRun && long > 0 ? Load(long, in: unit, pace: pace) : nil,
                label: label,
                volumeUnit: pattern == nil ? unit : .time,
                capped: capped
            ))
            if share >= 1 - 0.000_1, pattern == nil, volume >= base * 0.999, long >= min(baseLong, ceiling) * 0.999 { break }
        }
        return rows
    }

    // MARK: Ladder and walk-stage runners (AD-13b, AD-18)

    /// The walk stage, short run-walk or ladder is still running.
    static func ladderActive(_ state: CoachState) -> Bool {
        state.ladder.map { $0.form != .done } ?? false
    }

    /// AD-18's gap rows as steps back: up to 7 days repeats the step, 8-14 days one step back, 15-28 two; nil for a
    /// longer gap, which restarts at the first step.
    static func gapStepsBack(days: Int) -> Int? {
        switch days {
        case ...7: 0
        case 8 ... 14: 1
        case 15 ... 28: 2
        default: nil
        }
    }

    /// The first walks of a walk-stage runner (TI-2a), 10 min when intake didn't set them.
    static func firstWalkMinutes(_ state: CoachState) -> Double {
        if case .walkStage(let minutes) = state.assessment.starterEntry { return minutes }
        return 10
    }

    /// Where a ladder runner restarts: `stepsBack` steps below the pre-injury step through the short run-walk and the
    /// ladder as one sequence, never below the first step; on the walk stage, 5 min shorter walks a step, never
    /// shorter than the first walks (AD-13b). Nil steps back restarts at the first step (AD-18's longer gap).
    static func ladderRestartStep(_ report: InjuryReport, stepsBack: Int?, state: CoachState) -> (stepIndex: Int, walkMinutes: Double?) {
        let ladder = state.ladder ?? LadderState(form: report.baseline.ladderForm ?? .runWalk)
        if report.baseline.ladderForm == .walkStage {
            let first = firstWalkMinutes(state)
            let pre = report.baseline.walkMinutes ?? ladder.walkMinutes
            let minutes = stepsBack.map { max(first, pre - 5 * Double($0)) } ?? first
            return (ladder.stepIndex, minutes)
        }
        let pre = report.baseline.ladderStep ?? ladder.stepIndex
        let index = stepsBack.map { max(ladder.firstStepIndex, pre - $0) } ?? ladder.firstStepIndex
        return (min(index, pre), nil)
    }

    /// A ladder runner's recovery by steps: the rest weeks, any return weeks held at the restart step, then a step a
    /// week (2 weeks a step at 65+ or a risk score of 2 or more; Gentle repeats after every 3rd step) back to the
    /// pre-injury step (BD-2c, AD-18).
    static func ladderProjection(report: InjuryReport, state: CoachState, restWeeks: Int, holdWeeks: Int, restart: (stepIndex: Int, walkMinutes: Double?)) -> RecoveryProjection {
        let walking = report.baseline.ladderForm == .walkStage
        let runs = min(3, max(2, state.cycle.runsPerWeek))
        let slow = state.assessment.age >= 65 || state.assessment.risk.isHigh
        let gentle = state.level == .gentle
        let baseVolume = report.baseline.weekVolume
        var rows: [RecoveryWeekPreview] = []

        func add(step: Int, walk: Double?) {
            let number = rows.count + 1
            let volume: Double
            let name: String
            if walking {
                volume = Double(runs) * (walk ?? 0) * 60
                name = stepName(form: .walkStage, stepIndex: step, walkMinutes: walk)
            } else {
                volume = Double(runs) * RunWalkStep.sequence[step.clamped(to: 0 ... RunWalkStep.lastIndex)].sessionSeconds
                name = stepName(form: .runWalk, stepIndex: step, walkMinutes: nil)
            }
            let share = baseVolume > 0 ? min(1, volume / baseVolume) : 1
            rows.append(RecoveryWeekPreview(weekNumber: number, share: share, volume: volume, label: "Week \(number): \(name)", volumeUnit: .time))
        }

        for week in 0 ..< restWeeks {
            rows.append(RecoveryWeekPreview(weekNumber: week + 1, share: 0, volume: 0, label: "Week \(week + 1): no running", volumeUnit: .time))
        }
        var step = restart.stepIndex
        var walk = restart.walkMinutes
        for _ in 0 ..< holdWeeks { add(step: step, walk: walk) }
        let preStep = report.baseline.ladderStep ?? step
        let preWalk = report.baseline.walkMinutes ?? walk ?? 0
        func back() -> Bool { walking ? (walk ?? 0) >= preWalk - 0.001 : step >= preStep }
        if holdWeeks > 0, back() {
            return RecoveryProjection(weeks: rows, plannedWeeks: rows.count)
        }
        var stepsTaken = 0
        while rows.count < projectionLimit {
            let weeksOnStep = slow ? 2 : 1
            for _ in 0 ..< weeksOnStep where rows.count < projectionLimit { add(step: step, walk: walk) }
            if back() { break }
            if walking {
                walk = min(preWalk, (walk ?? 0) + 5)
            } else {
                step += 1
            }
            stepsTaken += 1
            if gentle, !slow, stepsTaken % 3 == 0, !back() { add(step: step, walk: walk) }
        }
        return RecoveryProjection(weeks: rows, plannedWeeks: rows.count)
    }

    /// A ladder step in words: "20-minute walks", "30 seconds running, 30 walking", "4.5 minutes running at a time",
    /// "30 minutes non-stop".
    static func stepName(form: LadderForm, stepIndex: Int, walkMinutes: Double?) -> String {
        func number(_ value: Double) -> String {
            value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
        }
        switch form {
        case .walkStage:
            return "\(number(walkMinutes ?? 10))-minute walks"
        case .runWalk:
            let step = RunWalkStep.sequence[stepIndex.clamped(to: 0 ... RunWalkStep.lastIndex)]
            if step.isShortRunWalk {
                return "\(number(step.runSeconds)) seconds running, \(number(step.walkSeconds ?? 0)) walking"
            }
            let minutes = step.runSeconds / 60
            if minutes >= 30 { return "30 minutes non-stop" }
            return minutes == 1 ? "1 minute running at a time" : "\(number(minutes)) minutes running at a time"
        case .done:
            return "your usual runs"
        }
    }
}
