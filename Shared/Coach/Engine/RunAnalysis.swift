//
//  RunAnalysis.swift
//  Wind Run
//

import Foundation

/// What set off FB-3's "That run got tough. What happened?" check.
enum ToughTrigger: Hashable {
    /// A slowdown of 25% or more: the last quarter against the second, or a marathon after 20 km against its
    /// 5-20 km pace. The fraction slower.
    case slowdown(Double)
    /// The runner marked the run cut short (AD-1).
    case cutShort
    /// A race that ended under 90% of its distance (EV-9).
    case raceShort
}

/// FB-4a's rows; the first match wins.
enum FadeRow: String, Hashable {
    case moreInReserve
    case even
    /// Marathons: under 10% slower.
    case held
    /// Mild or typical: a neutral note, no advice.
    case mild
    case marked
}

/// FB-5's causes for a fade or a big slowdown, checked in this order; the first match sets the message.
enum FadeCause: String, Hashable {
    case data
    case hills
    case heatFastStart
    case heat
    case fuel
    case pacing
    /// No heat answer and no weather source: heat can't be ruled out, so only the neutral note shows.
    case heatUnknown
}

/// FB-4a and FB-4b for one run or paced segment.
struct FadeResult: Hashable {
    /// Second-half pace against the first: 0.07 is 7% slower, −0.06 is 6% faster.
    var change: Double
    var row: FadeRow?
    /// FB-4b: how much faster than target (or the run's mean) the start was, when it counts as a fast start.
    var fastStart: Double?
    /// The fast start was judged against a target pace.
    var againstTarget: Bool
    /// The fast-start window was the first kilometre (10% of the distance was 1 km or less), for FB-6's wording.
    var firstKilometre: Bool
    /// The analysis covered a paced segment of the session rather than the whole run.
    var segment: Bool
    /// The first half's pace, for FB-5's heat test.
    var firstHalfPace: Double
}

/// FB-4d's flags for a rep session.
struct RepFlags: Hashable {
    /// The first rep was this much faster than target (over 3%).
    var firstFast: Double?
    /// The last rep was this much slower than the first (over 5%).
    var lastSlow: Double?
    /// Reps outside ±3% of target.
    var outside: Int
    /// Reps more than 5% slower than target, for FB-4g's Failed row.
    var overFiveSlow: Int

    var any: Bool { firstFast != nil || lastSlow != nil || outside >= 2 }
}

/// What FB-2 to FB-5 found in one run, before FB-1 picks what to say.
struct RunAnalysisResult: Hashable {
    var check: DataCheck
    var tough: ToughTrigger?
    var fade: FadeResult?
    /// FB-4b against a target with no marked fade after it.
    var fastStartWithTarget: Double?
    var reps: RepFlags?
    var fastRecoveries: Bool
    /// FB-4f: the last third of a continuous tempo against its first third, when over 3% slower.
    var tempoFade: Double?
    /// FB-4h: the last third's drop when durability fails.
    var durabilityDrop: Double?
    /// FB-4i: how much slower after 20 km, when it's the wall.
    var wall: Double?
    /// FB-5's cause for a marked fade or a big slowdown.
    var cause: FadeCause?
    /// Over 90 min with no fuel logged (FB-5).
    var unfuelled: Bool
    /// A "conditions" run: hills, heat, altitude or within 48 h after leg strength (PZ-7).
    var conditions: Bool
}

/// FB-3 to FB-5: the checks and analyses on one run (Coaching from run data).
enum RunAnalysis {
    /// FB-3: a slowdown of 25% or more.
    static let toughSlowdown = 0.25
    /// FB-4b: a start more than 2% faster than target, or 5% faster than the run's mean.
    static let fastStartTarget = 0.02
    static let fastStartMean = 0.05
    /// FB-4d, FB-4g: the ±3% rep line and the 5% rep fade.
    static let repBand = 0.03
    static let repFade = 0.05
    /// FB-4f: a tempo's last third more than 3% slower than its first.
    static let tempoFadeLine = 0.03
    /// FB-4h: durability fails at 10% or more.
    static let durabilityLine = 0.10
    /// FB-5: runs over 90 minutes need fuel.
    static let fuelSeconds: Double = 90 * 60

    // MARK: Classifying runs

    /// The heat tier for this run: the runner's AD-16 answer (cool T0 to very hot T3), else the air temperature
    /// against the cool answer's 18.1 °C line, or nil when neither exists (heat can't be ruled out, FB-5).
    static func heatTier(_ run: LoggedRun, state: CoachState) -> Int? {
        if let heat = run.checkIn?.heat { return heat.tier }
        if let session = RunReviewer.matchedSession(run, in: state),
           let record = state.readiness.last(where: { $0.sessionID == session.id && $0.heat != nil }) {
            return record.heat?.tier
        }
        if let temperature = run.temperature { return temperature < coolTemperature ? 0 : 1 }
        return nil
    }

    /// The top of the "cool" heat answer (AD-16's new numbers), used when only the air temperature is known.
    static let coolTemperature = 18.1

    /// PZ-7's "conditions" run: hills, heat above "cool", altitude ≥800 m, or ≤48 h after leg strength.
    static func isConditionsRun(_ run: LoggedRun, state: CoachState, calendar: Calendar) -> Bool {
        if RunReviewer.matchedSession(run, in: state)?.kind == .hills || RunDataGate.isHilly(run) { return true }
        if (heatTier(run, state: state) ?? 0) >= 1 { return true }
        if (run.track?.startAltitude ?? 0) >= 800 { return true }
        return WeeklyReviewer.afterLegWork(run, state: state, calendar: calendar)
    }

    /// An easy run: a planned easy or long run (or a Q made easy), or an extra run rated 3 or less (PZ-1a).
    static func isEasyRun(_ run: LoggedRun, state: CoachState) -> Bool {
        if let session = RunReviewer.matchedSession(run, in: state) {
            return session.effort == .easy && [.easy, .long, .threshold, .intervals, .shortReps, .hills, .racePace].contains(session.kind)
        }
        guard !RunDataGate.isRunWalk(run), run.checkIn?.raceOrAllOut != true, let rpe = run.rpe else { return false }
        return rpe <= 3
    }

    /// A run with one continuous effort: an easy, long or race run, a test, or an extra run with no work steps.
    static func isContinuous(_ run: LoggedRun, session: PlannedSession?) -> Bool {
        if RunDataGate.isRunWalk(run) { return false }
        if let session {
            return [.easy, .long, .race, .test].contains(session.kind) || session.madeEasy != nil
        }
        return !(run.steps ?? []).contains(where: \.isWork)
    }

    static func isMarathon(_ run: LoggedRun, session: PlannedSession?, state: CoachState) -> Bool {
        if session?.kind == .race { return state.goal.distance == .marathon }
        return run.checkIn?.raceOrAllOut == true && run.meters >= 40_000
    }

    /// FB-4a's column: training runs, 5K and 10K races, half races, marathons.
    enum Column { case training, half, marathon }

    static func column(_ run: LoggedRun, session: PlannedSession?, state: CoachState) -> Column {
        if isMarathon(run, session: session, state: state) { return .marathon }
        if session?.kind == .race, state.goal.distance == .halfMarathon { return .half }
        return .training
    }

    /// The pace a continuous run or segment aims at: a paced Q's band middle, or the race's plan pace.
    static func targetPace(_ session: PlannedSession?, state: CoachState) -> Double? {
        guard let session, session.madeEasy == nil else { return nil }
        switch session.kind {
        case .race:
            guard state.goal.targetSeconds != nil, session.target.meters > 0, session.target.seconds > 0 else { return nil }
            return session.target.seconds / session.target.meters * 1_000
        case .threshold, .racePace, .intervals:
            return session.paceBand?.middle
        default:
            return nil
        }
    }

    static func workSteps(_ run: LoggedRun) -> [LoggedStep] {
        (run.steps ?? []).filter(\.isWork)
    }

    /// A continuous paced Q (one work step) and the step as run.
    static func continuousWork(_ run: LoggedRun, session: PlannedSession?) -> LoggedStep? {
        guard let session, session.madeEasy == nil, let dose = session.dose, dose.continuous || dose.reps == 1 else { return nil }
        let work = workSteps(run)
        return work.count == 1 ? work[0] : nil
    }

    // MARK: FB-3

    static func toughTrigger(_ run: LoggedRun, session: PlannedSession?, check: DataCheck, state: CoachState) -> ToughTrigger? {
        if run.checkIn?.cutShort != nil { return .cutShort }
        if session?.kind == .race, let planned = session?.target.meters, planned > 0, run.meters > 0, run.meters < 0.9 * planned {
            return .raceShort
        }
        guard !check.dataProblem, !check.reasons.contains(.manual), isContinuous(run, session: session),
              let profile = run.track.flatMap({ PaceProfile(splits: $0.splits) }), profile.totalMeters >= 2_000 else { return nil }
        if isMarathon(run, session: session, state: state) {
            return wallSlowdown(profile).flatMap { $0 >= toughSlowdown ? .slowdown($0) : nil }
        }
        let total = profile.totalMeters
        guard let second = profile.pace(from: 0.25 * total, to: 0.5 * total),
              let last = profile.pace(from: 0.75 * total, to: total) else { return nil }
        let change = (last - second) / second
        return change >= toughSlowdown ? .slowdown(change) : nil
    }

    /// The largest slowdown of any 5 km after 20 km against the 5-20 km pace (FB-3, FB-4i).
    static func wallSlowdown(_ profile: PaceProfile) -> Double? {
        guard profile.totalMeters >= 25_000, let base = profile.pace(from: 5_000, to: 20_000) else { return nil }
        var worst = 0.0
        var start = 20_000.0
        while start + 5_000 <= profile.totalMeters + 1 {
            if let pace = profile.pace(from: start, to: start + 5_000) { worst = max(worst, (pace - base) / base) }
            start += 1_000
        }
        return worst
    }

    // MARK: FB-4a and FB-4b

    /// The second-half fade of a continuous run of 20 min or more, or of a paced segment of 20 min or more on its
    /// own halves. Whole runs skip the first km (5 km in a marathon). A continuous tempo is FB-4f's instead.
    static func fade(_ run: LoggedRun, session: PlannedSession?, state: CoachState) -> FadeResult? {
        let column = RunAnalysis.column(run, session: session, state: state)
        if let work = continuousWork(run, session: session) {
            guard session?.kind == .racePace, work.seconds >= 20 * 60, let profile = work.splits.flatMap(PaceProfile.init) else { return nil }
            return fade(profile, skip: 0, column: column, target: targetPace(session, state: state), segment: true)
        }
        guard isContinuous(run, session: session), run.movingSeconds >= 20 * 60,
              let profile = run.track.flatMap({ PaceProfile(splits: $0.splits) }) else { return nil }
        let skip = column == .marathon ? 5_000.0 : 1_000.0
        return fade(profile, skip: skip, column: column, target: targetPace(session, state: state), segment: false)
    }

    static func fade(_ profile: PaceProfile, skip: Double, column: Column, target: Double?, segment: Bool) -> FadeResult? {
        let total = profile.totalMeters
        guard total - skip >= 1_000 else { return nil }
        let middle = skip + (total - skip) / 2
        guard let first = profile.pace(from: skip, to: middle), let second = profile.pace(from: middle, to: total) else { return nil }
        let change = (second - first) / first
        let row = self.row(change, column: column)

        // FB-4b. With a target: the first 10% (at least 1 km) more than 2% fast. Without one: the first 10% or 20%
        // more than 5% faster than the run's mean, and only before a marked fade.
        var fastStart: Double?
        if let target {
            if let start = profile.pace(from: 0, to: max(1_000, 0.1 * total)) {
                let faster = (target - start) / target
                if faster > fastStartTarget { fastStart = faster }
            }
        } else if row == .marked {
            let mean = profile.pace
            let faster = [0.1, 0.2].compactMap { profile.pace(from: 0, to: $0 * total) }.map { (mean - $0) / mean }.max() ?? 0
            if faster > fastStartMean { fastStart = faster }
        }
        return FadeResult(
            change: change,
            row: row,
            fastStart: fastStart,
            againstTarget: target != nil,
            firstKilometre: target != nil && 0.1 * total <= 1_000,
            segment: segment,
            firstHalfPace: first
        )
    }

    static func row(_ change: Double, column: Column) -> FadeRow? {
        if change < -0.05 { return .moreInReserve }
        if abs(change) <= 0.02 { return .even }
        if change < 0 { return nil }
        switch column {
        case .training: return change <= 0.05 ? .mild : .marked
        case .half: return change <= 0.185 ? .mild : .marked
        case .marathon: return change < 0.10 ? .held : (change < 0.30 ? .mild : .marked)
        }
    }

    // MARK: FB-4d, FB-4e, FB-4f

    /// Rep consistency for intervals, short reps, and threshold or race-pace reps.
    static func reps(_ run: LoggedRun, session: PlannedSession?) -> RepFlags? {
        guard let session, session.madeEasy == nil, let dose = session.dose, dose.type != .hills, !dose.continuous, dose.reps > 1 else { return nil }
        let reps = workSteps(run).filter { $0.meters > 0 && $0.seconds > 0 }
        guard reps.count >= 2 else { return nil }
        let target = session.paceBand?.middle
        var flags = RepFlags(firstFast: nil, lastSlow: nil, outside: 0, overFiveSlow: 0)
        let first = reps[0].pace
        let last = reps[reps.count - 1].pace
        if (last - first) / first > repFade { flags.lastSlow = (last - first) / first }
        if let target {
            let faster = (target - first) / target
            if faster > repBand { flags.firstFast = faster }
            flags.outside = reps.filter { abs($0.pace - target) / target > repBand }.count
            flags.overFiveSlow = reps.filter { ($0.pace - target) / target > repFade }.count
        }
        return flags
    }

    /// A recovery jog between reps at threshold pace or faster.
    static func fastRecoveries(_ run: LoggedRun, state: CoachState) -> Bool {
        guard let threshold = state.paces.thresholdPace, let steps = run.steps,
              let first = steps.firstIndex(where: \.isWork), let last = steps.lastIndex(where: \.isWork), first < last else { return false }
        return steps[first ... last].contains { !$0.isWork && $0.meters > 0 && $0.seconds > 0 && $0.pace <= threshold }
    }

    /// FB-4f: a continuous tempo's last third against its first third, when more than 3% slower.
    static func tempoFade(_ run: LoggedRun, session: PlannedSession?) -> Double? {
        guard session?.kind == .threshold, let work = continuousWork(run, session: session),
              let profile = work.splits.flatMap(PaceProfile.init), profile.totalMeters >= 1_500 else { return nil }
        let third = profile.totalMeters / 3
        guard let first = profile.pace(from: 0, to: third), let last = profile.pace(from: 2 * third, to: profile.totalMeters) else { return nil }
        let change = (last - first) / first
        return change > tempoFadeLine ? change : nil
    }

    // MARK: FB-4h, FB-4i

    /// PZ-4's durability test on a long run of 90 min or more: the last third 10% or more slower than the pace
    /// from minute 10 to the 30% mark, or the run ended at RPE 7 or more when planned easy. The drop when it fails.
    static func durabilityDrop(_ run: LoggedRun, session: PlannedSession?) -> Double? {
        guard run.movingSeconds >= fuelSeconds, isContinuous(run, session: session), session?.kind != .race,
              let profile = run.track.flatMap({ PaceProfile(splits: $0.splits) }) else { return nil }
        let total = profile.totalSeconds
        guard let base = profile.pace(fromTime: 600, toTime: 0.3 * total),
              let last = profile.pace(fromTime: 2 * total / 3, toTime: total) else { return nil }
        let drop = (last - base) / base
        if drop >= durabilityLine { return drop }
        if let rpe = run.rpe, rpe >= 7, (session?.effort ?? .easy) == .easy { return max(drop, 0) }
        return nil
    }

    // MARK: FB-5

    /// The cause of a marked fade or a big slowdown: data, hills, heat with a fast start, heat, fuel, else pacing.
    static func cause(_ run: LoggedRun, session: PlannedSession?, check: DataCheck, fade: FadeResult?, state: CoachState) -> FadeCause {
        if check.dataProblem { return .data }
        if check.hilly { return .hills }
        guard let tier = heatTier(run, state: state) else { return .heatUnknown }
        if tier >= 1 {
            // A heat answer gives no WBGT: the first half is too fast only if it beat the unadjusted target.
            let target = targetPace(session, state: state) ?? state.paces.easy?.fast
            if let target, let first = fade?.firstHalfPace, first < target { return .heatFastStart }
            return .heat
        }
        if isUnfuelled(run) { return .fuel }
        return .pacing
    }

    static func isUnfuelled(_ run: LoggedRun) -> Bool {
        run.movingSeconds > fuelSeconds && (run.checkIn?.fuelGramsPerHour ?? 0) <= 0
    }

    // MARK: All of it

    static func analyse(_ run: LoggedRun, session: PlannedSession?, check: DataCheck, state: CoachState, calendar: Calendar) -> RunAnalysisResult {
        let tough = toughTrigger(run, session: session, check: check, state: state)
        let conditions = isConditionsRun(run, state: state, calendar: calendar)
        var result = RunAnalysisResult(
            check: check,
            tough: tough,
            fade: nil,
            fastStartWithTarget: nil,
            reps: nil,
            fastRecoveries: false,
            tempoFade: nil,
            durabilityDrop: nil,
            wall: nil,
            cause: nil,
            unfuelled: isUnfuelled(run),
            conditions: conditions
        )
        // Hilly runs get no pace analysis, but a fade on one gets the hill explanation (FB-5).
        if check.hilly, !check.dataProblem, !check.reasons.contains(.manual) {
            if RunAnalysis.fade(run, session: session, state: state)?.row == .marked { result.cause = .hills }
            if case .slowdown = tough { result.cause = .hills }
            return result
        }
        guard check.allowsPaceAnalysis else {
            if check.dataProblem { result.cause = .data }
            return result
        }
        let fadeResult = RunAnalysis.fade(run, session: session, state: state)
        result.fade = fadeResult
        if let fadeResult, fadeResult.againstTarget, let fast = fadeResult.fastStart, fadeResult.row != .marked { result.fastStartWithTarget = fast }
        // Pace tips on reps and tempos skip "conditions" sessions, which go by effort (FB-4g, PZ-7).
        if !conditions {
            result.reps = reps(run, session: session)
            result.fastRecoveries = fastRecoveries(run, state: state)
            result.tempoFade = tempoFade(run, session: session)
        }
        result.durabilityDrop = durabilityDrop(run, session: session)
        if isMarathon(run, session: session, state: state), session?.kind == .race,
           let profile = run.track.flatMap({ PaceProfile(splits: $0.splits) }), let wall = wallSlowdown(profile), wall >= toughSlowdown {
            result.wall = wall
        }
        var bigSlowdown = false
        if case .slowdown = tough { bigSlowdown = true }
        if fadeResult?.row == .marked || bigSlowdown || result.tempoFade != nil {
            result.cause = cause(run, session: session, check: check, fade: fadeResult, state: state)
        }
        return result
    }
}
