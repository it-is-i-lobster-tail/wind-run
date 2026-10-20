//
//  PaceAnchors.swift
//  Wind Run
//

import Foundation

/// New race and test results and the pace steps they bring: PZ-2's anchor, PZ-3's tests, PZ-7's 1% steps under
/// HL-27 and SW-7a's retest messages. Races (EV-7, EV-9) go through `recordResult` too.
extension PaceCalculator {
    /// HL-27: at most one 1% raise per 2 weeks.
    static let raiseDays = 14
    /// PZ-3a: off a track, a measured course or the same saved route, a change under 5% is "no clear change".
    static let gpsNoise = 0.05

    /// Records a race or test result (PZ-2). When it becomes the anchor in force, a slower anchor moves the paces
    /// at once; a faster one moves forecasts at once and quality paces 1% at a time from the paces in use (PZ-7,
    /// PZ-7a). Recording the same result again changes nothing.
    static func recordResult(_ result: RaceResult, state: CoachState, now: Date, calendar: Calendar) -> (CoachState, AnchorChange) {
        var state = state
        guard !allResults(state.paces).contains(where: { $0.id == result.id }) else { return (state, .notUsed) }
        let previous = anchorInForce(state.paces, now: now, calendar: calendar)
        state.paces.results.append(result)
        state.paces.results.sort { $0.date < $1.date }
        guard let anchor = anchorInForce(state.paces, now: now, calendar: calendar), anchor.id == result.id else {
            return (state, .notUsed)
        }
        state.paces.anchor = anchor
        state.paces = withEasyBand(state.paces, anchor: anchor)
        let target = qualityPaces(from: anchor)
        guard let previous, let current = state.paces.thresholdPace else {
            state.paces = withAnchorPaces(state.paces, target)
            return (state, .first)
        }
        if target.threshold >= current {
            // A slower anchor applies at once (PZ-2).
            state.paces = withAnchorPaces(state.paces, target)
        } else {
            // A faster one starts from the paces in use, with PZ-7's factor and PZ-2's volume adjustment folded
            // in, and steps toward its own (HL-27).
            state.paces.interval = state.paces.intervalPace
            state.paces.threshold = current
            state.paces.qualityFactor = 1
            state.paces.volumeAdjusted = false
            state.paces.anchorRaisePending = true
            state.paces = stepTowardAnchor(state.paces, now: now, calendar: calendar)
        }
        let gain = fiveKGain(from: previous, to: anchor)
        if abs(gain) < 0.01 { return (state, .noClearChange) }
        return (state, gain > 0 ? .faster(gain) : .slower(-gain))
    }

    /// The anchor's quality paces, with no PZ-7 factor and no pending raise.
    static func withAnchorPaces(_ paces: TrainingPaces, _ target: (threshold: Double, interval: Double?)) -> TrainingPaces {
        var paces = paces
        paces.threshold = target.threshold
        paces.interval = target.interval
        paces.qualityFactor = 1
        paces.volumeAdjusted = false
        paces.anchorRaisePending = false
        return paces
    }

    /// How much faster `result` is than `earlier`, as a fraction of the earlier 5K equivalent (k 1.07). Negative
    /// when slower.
    static func fiveKGain(from earlier: RaceResult, to result: RaceResult) -> Double {
        let before = equivalent(seconds: earlier.seconds, meters: earlier.meters, to: 5_000)
        let after = equivalent(seconds: result.seconds, meters: result.meters, to: 5_000)
        return before > 0 ? (before - after) / before : 0
    }

    /// One PZ-7 step toward the anchor's quality paces: at most 1% quicker, at most once per 2 weeks (HL-27). The
    /// step moves the base paces; PZ-7's factor from run reviews stays on top and shares the 2-week clock.
    static func stepTowardAnchor(_ paces: TrainingPaces, now: Date, calendar: Calendar) -> TrainingPaces {
        guard paces.anchorRaisePending, let anchor = paces.anchor else { return paces }
        if let last = paces.lastRaise, (calendar.dateComponents([.day], from: last, to: now).day ?? 0) < raiseDays {
            return paces
        }
        func step(_ value: Double?, toward target: Double) -> Double {
            guard let value, value > target else { return value ?? target }
            return max(target, value * 0.99)
        }
        var paces = paces
        let target = qualityPaces(from: anchor)
        let threshold = step(paces.threshold, toward: target.threshold)
        let interval = target.interval.map { step(paces.interval, toward: $0) }
        let moved = threshold != paces.threshold || interval != paces.interval
        var intervalPending = false
        if let interval, let goal = target.interval { intervalPending = interval > goal }
        paces.threshold = threshold
        paces.interval = interval
        paces.anchorRaisePending = threshold > target.threshold || intervalPending
        if moved { paces.lastRaise = now }
        return paces
    }

    /// PZ-5's easy band after a new anchor. A band from an anchor or from nothing follows it when slower; a
    /// reported band gives way to a slower anchor band; a band from logged runs stays (PZ-8). Never faster at once.
    static func withEasyBand(_ paces: TrainingPaces, anchor: RaceResult) -> TrainingPaces {
        var paces = paces
        let band = easyBand(from: anchor)
        switch paces.easySource {
        case .effortOnly:
            paces.easy = band
            paces.easySource = .anchor
        case .anchor, .reported:
            if let current = paces.easy, band.fast <= current.fast { break }
            paces.easy = band
            paces.easySource = .anchor
        case .logged:
            break
        }
        return paces
    }

    /// A PZ-3 test from a logged run. A 12-minute test (`testSeconds` 720) counts as a race of the distance
    /// covered in 12:00, a distance test (`testMeters`) as a race of that distance in the time taken; exactly one
    /// is set. The run's longest work step is the test when it has steps, else the whole run. A controlled test
    /// counts and is marked low precision. Off a track, a measured course or the same saved route (`measured`
    /// false), a change under 5% is kept but moves nothing (PZ-3a). Otherwise the result becomes the anchor in
    /// force (PZ-2), paces move per PZ-7a, and R, the verdict and the plan pace are recomputed at once (SW-7a), with
    /// SW-7a's message. `runs` gives the month before the test for PZ-2's volume rule and the forecast. Recording
    /// the same run again changes nothing. The caller says it's a test; this never reads the session type.
    static func recordTest(
        _ run: LoggedRun,
        testMeters: Double?,
        testSeconds: Double?,
        controlled: Bool,
        measured: Bool = true,
        state: CoachState,
        runs: [LoggedRun] = [],
        now: Date,
        calendar: Calendar
    ) -> (CoachState, [CoachNote]) {
        guard (testMeters == nil) != (testSeconds == nil) else { return (state, []) }
        let work = run.steps?.filter(\.isWork).max { $0.seconds < $1.seconds }
        let meters = testMeters ?? work?.meters ?? run.meters
        let seconds = testSeconds ?? work?.seconds ?? run.movingSeconds
        guard meters > 0, seconds > 0 else { return (state, []) }
        let monthStart = calendar.date(byAdding: .day, value: -28, to: run.start) ?? run.start
        let monthBefore = runs
            .filter { $0.id != run.id && $0.start >= monthStart && $0.start < run.start }
            .reduce(0) { $0 + $1.meters } / 4
        var result = RaceResult(
            id: StableID.make("test-\(run.id.uuidString)"),
            date: run.start,
            meters: meters,
            seconds: seconds,
            source: controlled ? .controlledTest : .appTest,
            official: false,
            course: .flat,
            treadmill: run.source == .treadmill,
            weeklyMetersBefore: monthBefore > 0 ? monthBefore : nil,
            runID: run.id
        )
        guard !allResults(state.paces).contains(where: { $0.id == result.id }) else { return (state, []) }
        let previous = anchorInForce(state.paces, now: now, calendar: calendar)
        if !measured, let previous, abs(fiveKGain(from: previous, to: result)) < gpsNoise {
            result.noClearChange = true
        }
        var (updated, change) = recordResult(result, state: state, now: now, calendar: calendar)
        if result.noClearChange { change = .noClearChange }
        if change == .notUsed { return (updated, []) }
        updated = recheckTimeGoal(updated, runs: runs, now: now, calendar: calendar)
        guard let message = testMessage(result, change: change, previous: previous, state: updated, runs: runs, now: now, calendar: calendar) else {
            return (updated, [])
        }
        return (updated, [CoachNote(.pace, message)])
    }

    /// SW-7a, EV-7, EV-10: R, the verdict and the plan pace from the new forecast set. Only training paces phase in.
    static func recheckTimeGoal(_ state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachState {
        guard state.goal.hasTimeGoal || state.goal.strongFirstTime else { return state }
        var state = state
        let check = GoalChecker.recheck(state.goal, state: state, runs: runs, now: now, calendar: calendar)
        state.eventReview.timeGoal = check.timeGoal
        state.paces.racePace = check.racePace
        return state
    }

    /// SW-7a's message after a test, by how it moved the anchor. The equivalent is PZ-4's at the goal distance,
    /// with the k its switches pick.
    static func testMessage(
        _ result: RaceResult,
        change: AnchorChange,
        previous: RaceResult?,
        state: CoachState,
        runs: [LoggedRun],
        now: Date,
        calendar: Calendar
    ) -> String? {
        let distance = state.goal.distance
        let context = forecastContext(for: distance, state: state, runs: runs, now: now, calendar: calendar)
        let k = personalK(state.paces, now: now, calendar: calendar)
        let time = CoachFormat.roughClock(forecast(distance, from: result, context: context, personalK: k, now: now, calendar: calendar).central)
        let equals = "Your test equals \(CoachFormat.article(for: time)) \(time) \(distance.sentenceName)"
        switch change {
        case .notUsed:
            return nil
        case .first:
            return "\(equals). Your session paces now come from it."
        case .noClearChange:
            return "No clear change this block. That's common, and the next block will look at why."
        case .slower:
            return "Your test came in slower, so your paces move down to match and sessions feel right again. If something got in the way, like illness or a busy stretch, tap 'Life happens' to tell me."
        case .faster(let gain):
            let from = previous.map { calendar.startOfDay(for: $0.date) } ?? calendar.startOfDay(for: result.date)
            let days = calendar.dateComponents([.day], from: from, to: calendar.startOfDay(for: result.date)).day ?? 0
            return "\(equals), \(CoachFormat.percent(gain)) faster than \(CoachFormat.weeks(max(1, days / 7))) ago. Your session paces will move up over the next few weeks."
        }
    }

    /// The week-end pace upkeep (PZ-2, PZ-7): a break of more than 28 days expires every result before it; with no
    /// anchor in force, quality sessions go back to effort; PZ-2's volume rule makes quality paces 5% slower while
    /// weekly distance is under 60% of the month before the anchor, and phases them back through PZ-7's steps; and
    /// a pending raise steps 1% when HL-27 allows. Safe to run again for the same week.
    static func weekEnded(_ index: Int, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> CoachUpdate {
        var state = state
        var notes: [CoachNote] = []
        if let gap = state.gap, gap.daysOff > 28, state.paces.expiredBefore.map({ $0 < gap.startedAt }) ?? true {
            state.paces.expiredBefore = gap.startedAt
        }
        let anchor = anchorInForce(state.paces, now: now, calendar: calendar)
        if anchor == nil, state.paces.anchor != nil {
            state.paces.anchor = nil
            state.paces.threshold = nil
            state.paces.interval = nil
            state.paces.racePace = nil
            state.paces.anchorRaisePending = false
            state.paces.volumeAdjusted = false
            state.paces.qualityFactor = 1
            notes.append(CoachNote(.pace, "Your last race or test is too old to set paces now, so quality sessions run by effort until your next test."))
        }
        if let anchor, let before = anchor.weeklyMetersBefore, before > 0, state.paces.threshold != nil {
            let since = calendar.date(byAdding: .day, value: -28, to: now) ?? now
            let weekly = runs.filter { $0.start >= since && $0.start <= now }.reduce(0) { $0 + $1.meters } / 4
            let low = weekly < 0.6 * before
            if low, !state.paces.volumeAdjusted {
                state.paces.volumeAdjusted = true
                notes.append(CoachNote(.pace, "You're running less than in the month before your last race or test, so your quality paces are 5% easier until your weekly distance is back."))
            } else if !low, state.paces.volumeAdjusted {
                // Back to the anchor's paces through PZ-7's 1% steps, never all at once (HL-27).
                state.paces.threshold = state.paces.threshold.map { $0 * TrainingPaces.volumeSlowdown }
                state.paces.interval = state.paces.interval.map { $0 * TrainingPaces.volumeSlowdown }
                state.paces.volumeAdjusted = false
                state.paces.anchorRaisePending = true
            }
        }
        state.paces = stepTowardAnchor(state.paces, now: now, calendar: calendar)
        return CoachUpdate(state: state, notes: notes)
    }
}
