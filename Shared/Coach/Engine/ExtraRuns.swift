//
//  ExtraRuns.swift
//  Wind Run
//

import Foundation

/// A planned session's place in the state, with its day.
struct SessionSlot: Hashable {
    /// Positions in `state.weeks` and in that week's sessions.
    var week: Int
    var session: Int
    var day: Date
}

/// AD-8: a run that matches no planned run is accepted, counted toward the week, W4max and spike detection, never
/// blamed, and checked in order: hard, spike, total, rest. Spikes count for any run. The changes are worked out from
/// the plan and the runs at each call and touch only planned runs from the day after the run and from today on, so
/// applying them again, after a second review or a re-plan, never changes anything twice.
enum ExtraRuns {
    /// Hard: RPE 6 or more, a race or all-out run, or 10 min or more at threshold pace or faster.
    static let hardRPE = 6
    static let thresholdSeconds: Double = 10 * 60
    /// At RPE 5 a Q due within 48 h becomes easy.
    static let steadyRPE = 5
    /// Spikes against P-L30: over 1.10 × (HL-1's cap), and over 1.30 × for next week's HOLD.
    static let spikeLine = CoachLimits.sessionGrowth
    static let largeSpikeLine = 1.30
    /// Total: the week ends at most 10% over plan, and inside HL-2's cap.
    static let overPlanLine = 1.10
    /// Trims round down to 100 m, or to the minute in time plans.
    static let distanceStep = 100.0
    static let timeStep = 60.0

    // MARK: Classifying

    /// AD-8's hard run. Time at threshold pace counts only when the data gate trusts the pace.
    static func isHard(_ run: LoggedRun, check: DataCheck, state: CoachState) -> Bool {
        if (run.rpe ?? 0) >= hardRPE || run.checkIn?.raceOrAllOut == true { return true }
        guard check.allowsPaceAnalysis, let threshold = state.paces.thresholdPace else { return false }
        return secondsAtOrFaster(threshold, in: run) >= thresholdSeconds
    }

    /// Seconds at `pace` or faster: from the work steps when the run has them, else from its km splits.
    static func secondsAtOrFaster(_ pace: Double, in run: LoggedRun) -> Double {
        let work = RunAnalysis.workSteps(run).filter { $0.meters > 0 && $0.seconds > 0 }
        if !work.isEmpty { return work.filter { $0.pace <= pace }.reduce(0) { $0 + $1.seconds } }
        return (run.track?.splits ?? [])
            .filter { $0.meters >= 500 && $0.seconds > 0 && $0.pace <= pace }
            .reduce(0) { $0 + $1.seconds }
    }

    /// The logged session holding the run: runs less than 15 minutes apart are one (Terms, FB-2).
    static func session(of run: LoggedRun, runs: [LoggedRun]) -> RunSessionLoad? {
        let all = runs.contains { $0.id == run.id } ? runs : runs + [run]
        return LoadMetrics.sessions(from: RunDataGate.usableRuns(all)).first { $0.runIDs.contains(run.id) }
    }

    /// What `apply` works out from the runs alone, done once when it goes over many runs on the same runs and state.
    struct RunLoads {
        var usable: [LoggedRun]
        var sessions: [RunSessionLoad]
        /// P-L30 in force at each session's start (`spike`'s line).
        var longest: [Date: Load]

        init(runs: [LoggedRun], state: CoachState, calendar: Calendar) {
            usable = RunDataGate.usableRuns(runs)
            sessions = LoadMetrics.sessions(from: usable)
            longest = LoadMetrics.longestBeforeEach(
                sessions: sessions,
                seed: WeekPlanner.seed(for: state),
                countFrom: state.gap?.startedAt,
                ceiling: state.gap?.referenceLongRun,
                capOnly: WeekPlanner.raceRunIDs(state),
                calendar: calendar
            )
        }
    }

    /// AD-8's spike: the session holding the run against the P-L30 in force before it, on distance and on time. In
    /// the intake seed's 30 days a run up to the reported longest counts in full (TI-5), so it is no spike. Distance
    /// from patchy GPS doesn't count, and runs on race day never spike (HL-1).
    static func spike(_ run: LoggedRun, state: CoachState, runs: [LoggedRun], calendar: Calendar) -> SpikeRecord? {
        let all = runs.contains { $0.id == run.id } ? runs : runs + [run]
        return spike(run, state: state, sessions: LoadMetrics.sessions(from: RunDataGate.usableRuns(all)), calendar: calendar)
    }

    /// The same, with the logged sessions of every usable run and, when known, the P-L30 at each one's start.
    static func spike(_ run: LoggedRun, state: CoachState, sessions: [RunSessionLoad], longestBefore: [Date: Load]? = nil, calendar: Calendar) -> SpikeRecord? {
        let races = WeekPlanner.raceRunIDs(state)
        guard let session = sessions.first(where: { $0.runIDs.contains(run.id) }), races.isDisjoint(with: session.runIDs) else { return nil }
        let seed = WeekPlanner.seed(for: state)
        var longest = longestBefore?[session.start] ?? LoadMetrics.longest(
            before: session.start,
            sessions: sessions,
            seed: seed,
            countFrom: state.gap?.startedAt,
            ceiling: state.gap?.referenceLongRun,
            capOnly: races,
            calendar: calendar
        )
        if LoadMetrics.seedActive(seed, at: session.start, calendar: calendar), let reported = seed.reportedLongest {
            longest = Load(meters: max(longest.meters, reported.meters), seconds: max(longest.seconds, reported.seconds))
        }
        // A run in a usable session is never a duplicate.
        let meters: Double = RunDataGate.check(run, duplicate: false).dataProblem ? 0 : session.meters
        var factor = 0.0
        if meters > 0, longest.meters > 0 { factor = meters / longest.meters }
        if session.seconds > 0, longest.seconds > 0 { factor = max(factor, session.seconds / longest.seconds) }
        guard factor > spikeLine + 1e-9 else { return nil }
        return SpikeRecord(runID: session.runIDs[0], date: session.start, load: session.load, longest: longest, large: factor > largeSpikeLine + 1e-9)
    }

    /// Keeps the spike list in step with the run: one record per logged session, removed when it no longer spikes.
    static func recordSpike(_ run: LoggedRun, state: inout CoachState, runs: [LoggedRun], loads: RunLoads? = nil, calendar: Calendar) -> SpikeRecord? {
        let all = runs.contains { $0.id == run.id } ? runs : runs + [run]
        let sessions = loads?.sessions ?? LoadMetrics.sessions(from: RunDataGate.usableRuns(all))
        let spike = self.spike(run, state: state, sessions: sessions, longestBefore: loads?.longest, calendar: calendar)
        if let session = sessions.first(where: { $0.runIDs.contains(run.id) }) {
            state.runReview.spikes.removeAll { $0.date == session.start || session.runIDs.contains($0.runID) }
        }
        if let spike { state.runReview.spikes.append(spike) }
        state.runReview.spikes.sort { $0.date < $1.date }
        return spike
    }

    // MARK: Applying (steps 1 to 4)

    /// AD-8's steps for one run on the plan as it stands. Spikes count for any run; the rest only for extra runs, and
    /// ladder weeks leave rest and totals to the ladder (AD-18). Returns one "because" sentence for each kind of
    /// change made now; a step with nothing left to change says nothing.
    /// `loads`, when given, must come from the same runs and the same state's seed, gap and races.
    static func apply(_ run: LoggedRun, extra: Bool, state: inout CoachState, runs: [LoggedRun], loads: RunLoads? = nil, now: Date, calendar: Calendar) -> [RunNoteRecord] {
        let all = runs.contains { $0.id == run.id } ? runs : runs + [run]
        let check = RunDataGate.check(run, runs: all)
        guard check.gate != .dropped else { return [] }
        let today = calendar.startOfDay(for: now)
        var records: [RunNoteRecord] = []
        func record(_ kind: RunChangeKind, _ text: String, greets: Bool = false) {
            records.append(RunNoteRecord(runID: run.id, kind: kind, note: CoachNote(.plan, text), greets: greets))
        }

        let hard = extra && isHard(run, check: check, state: state)
        let earlier = (loads?.usable ?? RunDataGate.usableRuns(all)).filter { $0.start < run.start }
        let gateOpen = QualityPlanner.gateBlocker(state: state, runs: earlier, now: run.start, calendar: calendar) == nil
        let spike = recordSpike(run, state: &state, runs: all, loads: loads, calendar: calendar)

        // 1. Hard: the run is the week's Q. A Q due within 48 h (72 h at 60+), and any later one that would break
        // HL-7's count in the run's 7 days, becomes an easy run of the same minutes. At RPE 5, only a Q due in 48 h.
        var eased: [String] = []
        var because = ""
        if hard, gateOpen {
            eased = easeQuality(after: run, spacing: state.assessment.age >= 60 ? 2 : 1, countHL7: true, state: &state, runs: all, today: today, calendar: calendar)
            because = "That run was hard, so it counts as this week's speed session"
        } else if extra, !hard, run.rpe == steadyRPE {
            eased = easeQuality(after: run, spacing: 1, countHL7: false, state: &state, runs: all, today: today, calendar: calendar)
            because = "That run took some effort, so"
        }
        // Before the Q gate or in the early window a hard run is a hard day; a spike is one too. No hard or long run
        // for 48 h either way.
        var longRunNote: String?
        if (hard && !gateOpen) || spike != nil {
            let more = easeQuality(after: run, spacing: 1, countHL7: false, state: &state, runs: all, today: today, calendar: calendar)
            if eased.isEmpty, !more.isEmpty { because = "Your legs need 48 hours after that run, so" }
            eased += more
            longRunNote = clearLongRun(after: run, state: &state, today: today, calendar: calendar)
        }
        if !eased.isEmpty {
            let joiner = because.hasSuffix(" so") ? " " : " and "
            let verb = eased.count == 1 ? "is an easy run" : "are easy runs"
            record(.quality, because + joiner + list(eased) + " " + verb + " instead.")
        }
        if let longRunNote { record(.longRun, longRunNote) }
        if hard, !gateOpen, !state.runReview.offers.contains(where: { $0.kind == .funRun }) {
            state.runReview.offers.append(RunOffer(
                kind: .funRun,
                runID: run.id,
                date: run.start,
                question: nil,
                text: funRunText(run, state: state, runs: earlier, calendar: calendar)
            ))
        }

        // 2. Spike: no new longest run for 7 days.
        if let spike { clearNewLongest(after: spike.date, state: &state, calendar: calendar) }

        guard extra, let week = weekPosition(of: run.start, in: state, calendar: calendar),
              state.weeks[week].plan.kind != .ladder else { return records }

        // 4. Rest, before the total so the dropped run counts: the next day is rest and the next run the shortest.
        let rest = self.rest(run, week: week, clearLongRun: !records.contains { $0.kind == .longRun }, state: &state, runs: all, today: today, calendar: calendar)
        if let longRun = rest.longRun { record(.longRun, longRun) }
        if let text = rest.text { record(.rest, text) }

        // 3. Total: trim the remaining easy runs, each kept at 20 min or more and the key session untouched, so the
        // week ends inside 1.10 × plan and HL-2's cap; if that isn't enough, next week holds.
        let total = self.total(run, week: week, state: &state, runs: all, now: now, today: today, calendar: calendar)
        if !total.trimmed.isEmpty {
            let days = list(total.trimmed)
            record(.total, total.over
                ? "I've shortened \(days) a little, but your week is still over its range, so next week holds at this level."
                : "I've shortened \(days) a little so your week stays in range.", greets: true)
        } else if total.over, !state.runReview.runNotes.contains(where: { $0.runID == run.id && $0.kind == .total }) {
            record(.total, "Your week is now over its range, so next week holds at this level.", greets: true)
        }
        return records
    }

    /// "Nice social run." for a run marked unplanned or with friends, else "Nice extra run." (AD-8's example).
    static func greeting(_ run: LoggedRun) -> String {
        run.checkIn?.unplannedOrWithFriends == true ? "Nice social run." : "Nice extra run."
    }

    // MARK: Step 1: Q

    /// Planned Q from the day after the run, up to `spacing` days on, and with `countHL7` any later one in the
    /// run's 7 days that would break HL-7's count, become easy runs of the same minutes. Races and tests stay.
    static func easeQuality(after run: LoggedRun, spacing: Int, countHL7: Bool, state: inout CoachState, runs: [LoggedRun], today: Date, calendar: Calendar) -> [String] {
        let cap = QualityPlanner.hardCap(runs: state.cycle.runsPerWeek, assessment: state.assessment)
        var names: [String] = []
        for slot in slots(state, from: 1, through: countHL7 ? 6 : spacing, after: run.start, calendar: calendar) {
            let session = state.weeks[slot.week].plan.sessions[slot.session]
            guard changeable(session, day: slot.day, today: today), session.isQuality else { continue }
            if days(from: run.start, to: slot.day, calendar: calendar) > spacing {
                guard let from = calendar.date(byAdding: .day, value: -6, to: slot.day),
                      hardDays(from: from, before: slot.day, state: state, runs: runs, today: today, calendar: calendar) + 1 > cap else { continue }
            }
            makeEasy(&state.weeks[slot.week].plan.sessions[slot.session], state: state)
            names.append(name(session, on: slot.day, calendar: calendar))
        }
        return names
    }

    /// Hard sessions from `from` up to `before`: Q done or still planned, and hard extra runs (HL-7's count).
    static func hardDays(from: Date, before: Date, state: CoachState, runs: [LoggedRun], today: Date, calendar: Calendar) -> Int {
        var count = 0
        for record in state.weeks {
            for session in record.plan.sessions where session.isQuality {
                let day = state.date(of: session, in: record.plan, calendar: calendar)
                guard day >= calendar.startOfDay(for: from), day < calendar.startOfDay(for: before) else { continue }
                switch session.status {
                case .done: count += 1
                case .planned where day >= today: count += 1
                default: break
                }
            }
        }
        let duplicates = RunDataGate.duplicateIDs(runs)
        for other in runs where other.start >= calendar.startOfDay(for: from) && other.start < calendar.startOfDay(for: before) {
            let check = RunDataGate.check(other, duplicate: duplicates.contains(other.id))
            guard check.gate != .dropped, RunReviewer.match(other, state: state, calendar: calendar) == .extra,
                  isHard(other, check: check, state: state) else { continue }
            count += 1
        }
        return count
    }

    /// An easy run of the same minutes (AD-8), as the planner turns a Q into one.
    static func makeEasy(_ session: inout PlannedSession, state: CoachState) {
        let pace = state.paces.easyPace ?? Scheduler.fallbackEasyPace
        session.madeEasy = .extraRun
        session.effort = .easy
        session.blocks = []
        session.paceBand = nil
        session.notes = []
        if session.target.seconds > 0 {
            session.target = Load(meters: session.target.seconds / pace * 1_000, seconds: session.target.seconds)
        }
    }

    // MARK: Long runs

    /// The long run due the day after the run waits 48 h: it swaps with the next easy run of its week, else moves to
    /// a free run day, with an easy or rest day on each side; with neither, it's dropped (AD-9).
    static func clearLongRun(after run: LoggedRun, state: inout CoachState, today: Date, calendar: Calendar) -> String? {
        guard let slot = slots(state, from: 1, through: 1, after: run.start, calendar: calendar).first(where: { slot in
            let session = state.weeks[slot.week].plan.sessions[slot.session]
            return session.kind == .long && changeable(session, day: slot.day, today: today)
        }) else { return nil }
        let day = Weekday(of: slot.day, calendar: calendar).name
        let because = "Your legs need 48 hours after that run, so"
        var week = state.weeks[slot.week].plan
        let long = week.sessions[slot.session]
        let easyRuns = week.sessions.indices.filter { index in
            let session = week.sessions[index]
            return session.dayOffset > long.dayOffset && session.kind == .easy && !session.isKey && session.status.isPlanned
                && fitsMove(on: session.dayOffset, in: week, ignoring: [long.id, session.id])
        }
        if let swap = easyRuns.min(by: { week.sessions[$0].dayOffset < week.sessions[$1].dayOffset }) {
            let other = week.sessions[swap]
            week.sessions[swap].movedFrom = other.movedFrom ?? other.dayOffset
            week.sessions[swap].dayOffset = long.dayOffset
            week.sessions[slot.session].movedFrom = long.movedFrom ?? long.dayOffset
            week.sessions[slot.session].dayOffset = other.dayOffset
            week.sessions.sort { $0.dayOffset < $1.dayOffset }
            state.weeks[slot.week].plan = week
            let otherDay = Weekday(of: state.date(of: other, in: week, calendar: calendar), calendar: calendar).name
            return "\(because) \(day)'s long run swaps places with \(otherDay)'s run."
        }
        let runDays = state.intake.runDays
        let later = long.dayOffset < 6 ? Array(long.dayOffset + 1 ... 6) : []
        let free = later.first { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: week.start) ?? week.start
            return (runDays.isEmpty || runDays.contains(Weekday(of: date, calendar: calendar)))
                && !week.sessions.contains { $0.dayOffset == offset && $0.kind.isRun && $0.status != .dropped && $0.status != .missed }
                && fitsMove(on: offset, in: week, ignoring: [long.id])
        }
        if let free {
            week.sessions[slot.session].movedFrom = long.movedFrom ?? long.dayOffset
            week.sessions[slot.session].dayOffset = free
            week.sessions.sort { $0.dayOffset < $1.dayOffset }
            state.weeks[slot.week].plan = week
            let newDay = Weekday(of: calendar.date(byAdding: .day, value: free, to: week.start) ?? week.start, calendar: calendar).name
            return "\(because) \(day)'s long run moves to \(newDay)."
        }
        state.weeks[slot.week].plan.sessions[slot.session].status = .dropped
        return "\(because) I've dropped \(day)'s long run this week."
    }

    /// AD-9: a key session moves only to a day with an easy or rest day on each side.
    static func fitsMove(on offset: Int, in week: PlannedWeek, ignoring ids: Set<UUID>) -> Bool {
        !week.sessions.contains { other in
            !ids.contains(other.id) && abs(other.dayOffset - offset) <= 1 && other.isHardDay
                && other.status != .dropped && other.status != .missed
        }
    }

    /// No new longest run for 7 days after a spike: planned long runs in those days lose the mark.
    static func clearNewLongest(after date: Date, state: inout CoachState, calendar: Calendar) {
        for slot in slots(state, from: 0, through: 7, after: date, calendar: calendar) {
            let session = state.weeks[slot.week].plan.sessions[slot.session]
            guard session.isNewLongest, session.status.isPlanned, slot.day > date,
                  slot.day.timeIntervalSince(date) < 7 * 86_400 else { continue }
            state.weeks[slot.week].plan.sessions[slot.session].isNewLongest = false
        }
    }

    // MARK: Step 4: rest

    /// A Starter or Novice running on back-to-back days, more runs than the runs-per-week cap, or a run on the week's
    /// last remaining rest day: the next day is rest and the next run is the week's shortest. A long run on the next
    /// day waits as after a hard day (`clearLongRun`), unless that already happened. Returns the "because" sentences.
    static func rest(_ run: LoggedRun, week position: Int, clearLongRun clearsLongRun: Bool, state: inout CoachState, runs: [LoggedRun], today: Date, calendar: Calendar) -> (text: String?, longRun: String?) {
        let plan = state.weeks[position].plan
        let runDay = calendar.startOfDay(for: run.start)
        guard let weekEnd = calendar.date(byAdding: .day, value: 7, to: plan.start),
              let dayBefore = calendar.date(byAdding: .day, value: -1, to: runDay) else { return (nil, nil) }
        let usable = RunDataGate.usableRuns(runs)
        let logged = LoadMetrics.sessions(from: usable).filter { $0.start >= plan.start && $0.start < weekEnd }
        let loggedDays = Set(logged.map { calendar.startOfDay(for: $0.start) })
        let runOffset = days(from: plan.start, to: runDay, calendar: calendar)
        let laterPlanned = plan.sessions.filter { session in
            let day = state.date(of: session, in: plan, calendar: calendar)
            return session.kind.isRun && session.status.isPlanned && day > runDay && day >= today
        }
        let nextDayRun = slots(state, from: 1, through: 1, after: run.start, calendar: calendar).contains { slot in
            let session = state.weeks[slot.week].plan.sessions[slot.session]
            guard session.kind.isRun else { return false }
            if case .done = session.status { return true }
            return session.status.isPlanned && slot.day >= today
        }
        let restDays = (0 ..< 7).filter { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: plan.start) else { return false }
            if loggedDays.contains(day) { return false }
            return !(day >= today && plan.sessions.contains { $0.dayOffset == offset && $0.kind.isRun && $0.status.isPlanned })
        }.count
        let onRestDay = !plan.sessions.contains { $0.dayOffset == runOffset && $0.kind.isRun && $0.status != .dropped }

        let reason: String
        if state.assessment.tier <= .novice,
           usable.contains(where: { $0.id != run.id && calendar.startOfDay(for: $0.start) == dayBefore }) || nextDayRun {
            reason = "Back-to-back running days are a lot for your legs right now"
        } else if logged.count + laterPlanned.count > runsCap(state) {
            reason = "That's more runs than your plan has room for this week"
        } else if onRestDay, restDays == 0 {
            reason = "That was your last rest day this week"
        } else {
            return (nil, nil)
        }

        // The next day is rest: its long run waits, any other run there is dropped, and a key Q stays.
        let longRun = clearsLongRun ? clearLongRun(after: run, state: &state, today: today, calendar: calendar) : nil
        var parts: [String] = []
        for slot in slots(state, from: 1, through: 1, after: run.start, calendar: calendar) {
            let session = state.weeks[slot.week].plan.sessions[slot.session]
            guard changeable(session, day: slot.day, today: today), !session.isKey, session.kind != .long else { continue }
            state.weeks[slot.week].plan.sessions[slot.session].status = .dropped
            parts.append("\(Weekday(of: slot.day, calendar: calendar).name) is a rest day")
        }
        // The next run of the week is its shortest.
        let unit = plan.volumeUnit
        let week = state.weeks[position].plan
        if let slot = slots(state, from: 2, through: 6, after: run.start, calendar: calendar).first(where: { slot in
            slot.week == position && state.weeks[slot.week].plan.sessions[slot.session].kind.isRun
                && changeable(state.weeks[slot.week].plan.sessions[slot.session], day: slot.day, today: today)
        }) {
            let session = week.sessions[slot.session]
            let others = week.sessions.filter { other in
                guard other.id != session.id, other.kind.isRun, other.target.amount(in: unit) > 0 else { return false }
                return other.status != .dropped && other.status != .missed
            }
            if isEasy(session), !session.isKey, let shortest = others.map({ $0.target.amount(in: unit) }).min() {
                let pace = sessionPace(session, state: state)
                let floor = Load(CoachLimits.minimumRunSeconds, in: .time, pace: pace).amount(in: unit)
                let amount = max(shortest, floor)
                if amount < session.target.amount(in: unit) - 1e-6 {
                    state.weeks[slot.week].plan.sessions[slot.session].target = Load(amount, in: unit, pace: pace)
                    parts.append("\(Weekday(of: slot.day, calendar: calendar).name)'s run is shorter")
                }
            }
        }
        return (parts.isEmpty ? nil : "\(reason), so \(parts.joined(separator: " and ")).", longRun)
    }

    // MARK: Step 3: total

    /// Trims the week's remaining easy runs in date order until the week's done volume plus what's still planned fits
    /// 1.10 × plan and HL-2's cap. Each stays at 20 min or more, rounded down to 100 m or 1 min; key sessions, races
    /// and tests are never touched. Returns the trimmed days and whether the week is still over.
    static func total(_ run: LoggedRun, week position: Int, state: inout CoachState, runs: [LoggedRun], now: Date, today: Date, calendar: Calendar) -> (trimmed: [String], over: Bool) {
        let plan = state.weeks[position].plan
        let unit = plan.volumeUnit
        let runDay = calendar.startOfDay(for: run.start)
        guard plan.plannedVolume > 0, let weekEnd = calendar.date(byAdding: .day, value: 7, to: plan.start) else { return ([], false) }
        let usable = RunDataGate.usableRuns(runs)
        let done = LoadMetrics.volume(from: plan.start, to: weekEnd, sessions: LoadMetrics.sessions(from: usable), unit: unit, pace: state.paces.easyPace)
        let remaining = plan.sessions.indices.filter { index in
            let session = plan.sessions[index]
            return session.kind.isRun && session.status.isPlanned && state.date(of: session, in: plan, calendar: calendar) >= today
        }
        let projected = done + remaining.reduce(0) { $0 + plan.sessions[$1].target.amount(in: unit) }
        let cap = WeekPlanner.makeContext(week: plan.index, state: state, runs: usable, now: now, calendar: calendar).weekCap
        let limit = cap > 0 ? min(overPlanLine * plan.plannedVolume, cap) : overPlanLine * plan.plannedVolume
        var excess = projected - limit
        guard excess > 1e-6 else { return ([], false) }

        var trimmed: [String] = []
        let step = unit == .distance ? distanceStep : timeStep
        for index in remaining {
            guard excess > 1e-6 else { break }
            let session = state.weeks[position].plan.sessions[index]
            let day = state.date(of: session, in: plan, calendar: calendar)
            guard day > runDay, isEasy(session), !session.isKey, session.kind != .race, session.kind != .test else { continue }
            let pace = sessionPace(session, state: state)
            let floor = Load(CoachLimits.minimumRunSeconds, in: .time, pace: pace).amount(in: unit)
            let current = session.target.amount(in: unit)
            guard current - floor > 1e-6 else { continue }
            var amount = ((current - min(excess, current - floor)) / step).rounded(.down) * step
            if amount < floor { amount = min(current, (floor / step).rounded(.up) * step) }
            guard amount < current - 1e-6 else { continue }
            excess -= current - amount
            state.weeks[position].plan.sessions[index].target = Load(amount, in: unit, pace: pace)
            trimmed.append(Weekday(of: day, calendar: calendar).name)
        }
        return (trimmed, excess > 1e-6)
    }

    // MARK: Step 5: habit

    /// Extra runs in 3 of the last 4 plan weeks offer a planned slot on the day they fall most (the same weekly
    /// volume over one more run, within the runs-per-week cap, never a 6th run, at most +1 run per 4 weeks). Over the
    /// runs-per-week cap 2 weeks running, a swap instead, never an added slot. An offer waits 4 weeks to come again.
    static func habitOffer(_ run: LoggedRun, state: CoachState, runs: [LoggedRun], calendar: Calendar) -> RunOffer? {
        let current = state.weekIndex(on: run.start, calendar: calendar)
        guard current >= 0 else { return nil }
        let usable = RunDataGate.usableRuns(runs.contains { $0.id == run.id } ? runs : runs + [run])
        let races = WeekPlanner.raceRunIDs(state)
        let extras = usable.filter { other in
            let week = state.weekIndex(on: other.start, calendar: calendar)
            return week >= current - 3 && week <= current && other.start <= run.start && !races.contains(other.id)
                && RunReviewer.match(other, state: state, calendar: calendar) == .extra
        }.sorted { $0.start < $1.start }
        let weeks = Set(extras.map { state.weekIndex(on: $0.start, calendar: calendar) })
        guard weeks.count >= 3, weeks.contains(current) else { return nil }
        // The weekday they fall on most; on a tie, the latest one's.
        var counts: [Weekday: Int] = [:]
        for other in extras { counts[Weekday(of: other.start, calendar: calendar), default: 0] += 1 }
        guard let most = counts.values.max(),
              let day = extras.reversed().map({ Weekday(of: $0.start, calendar: calendar) }).first(where: { counts[$0] == most }),
              !state.intake.runDays.contains(day) else { return nil }
        func offeredRecently(_ kind: RunOfferKind) -> Bool {
            state.runReview.offers.contains { $0.kind == kind && $0.runID != run.id && run.start.timeIntervalSince($0.date) < 28 * 86_400 }
        }
        let cap = runsCap(state)
        let sessions = LoadMetrics.sessions(from: usable)
        func overCap(_ week: Int) -> Bool {
            let start = state.weekStart(week, calendar: calendar)
            guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return false }
            return sessions.filter { $0.start >= start && $0.start < end && $0.start <= run.start }.count > cap
        }
        if overCap(current), overCap(current - 1) {
            guard !offeredRecently(.swapRunDay), let from = nearestRunDay(to: day, state: state) else { return nil }
            return RunOffer(
                kind: .swapRunDay,
                runID: run.id,
                date: run.start,
                question: .swapRunDay(from: from, to: day),
                text: "You've run more often than your plan has room for two weeks running. Want to move your \(from.name) run to \(day.name)? Your number of runs stays the same."
            )
        }
        guard !offeredRecently(.extraRunSlot), state.cycle.runsPerWeek + 1 <= min(cap, 5),
              state.cycle.lastRunAddedWeek.map({ current - $0 >= 4 }) ?? true else { return nil }
        let onDay = extras.filter { Weekday(of: $0.start, calendar: calendar) == day }
        let social = onDay.filter { $0.checkIn?.unplannedOrWithFriends == true }.count * 2 > onDay.count
        let habit = social ? "You've run with a friend most \(day.name)s." : "You've been adding a run most \(day.name)s."
        return RunOffer(
            kind: .extraRunSlot,
            runID: run.id,
            date: run.start,
            question: .extraRunSlot(day: day),
            text: habit + " Want me to make it a planned run? Your weekly total stays the same."
        )
    }

    /// The planned run day nearest `day`, never the long run's day; the earlier one on a tie.
    static func nearestRunDay(to day: Weekday, state: CoachState) -> Weekday? {
        let candidates = state.intake.runDays.filter { $0 != state.intake.longRunDay && $0 != day }
        func distance(_ other: Weekday) -> Int {
            let forward = (other.rawValue - day.rawValue + 7) % 7
            return min(forward, 7 - forward)
        }
        return candidates.min { lhs, rhs in
            distance(lhs) != distance(rhs) ? distance(lhs) < distance(rhs) : lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: "Fun run!"

    /// Said once for a hard extra run before the Q gate or in the early window, without blame. The unlock date shows
    /// when only HL-12's straight weeks are left to count.
    static func funRunText(_ run: LoggedRun, state: CoachState, runs: [LoggedRun], calendar: Calendar) -> String {
        if let unlock = unlockDate(run, state: state, runs: runs, calendar: calendar) {
            return "Fun run! Until \(CoachFormat.date(unlock, calendar: calendar)) I keep your plan easy so your legs adapt first."
        }
        return "Fun run! For now I keep your plan easy so your legs adapt first."
    }

    /// The first day of the week Q can start, when the straight weeks are all HL-12 still needs.
    static func unlockDate(_ run: LoggedRun, state: CoachState, runs: [LoggedRun], calendar: Calendar) -> Date? {
        let assessment = state.assessment
        guard state.openInjuries.isEmpty, !assessment.overlays.earlyWindow,
              assessment.runs30Minutes || QualityPlanner.ranThirtyMinutes(runs) else { return nil }
        let needed = assessment.age >= 50 ? 10 : 8
        let steady = QualityPlanner.steadyWeeks(state: state, runs: runs, now: run.start, calendar: calendar)
        guard steady < needed else { return nil }
        return state.weekStart(state.weekIndex(on: run.start, calendar: calendar) + needed - steady, calendar: calendar)
    }

    // MARK: Helpers

    /// HL-9's runs-a-week cap for the runner, before the run days offered: a run on a day the runner didn't offer is
    /// not beyond it, and a planned slot adds its day (AD-8). The same caps as the intake assessment.
    static func runsCap(_ state: CoachState) -> Int {
        let assessment = state.assessment
        let recent = state.intake.lastFourWeeks
        var cap = assessment.tier.runsCap
        if assessment.tier == .regular, (recent?.runsPerWeek ?? 0) >= 5, recent?.fiveRunsForThreeMonths == true, assessment.age < 50 { cap = 5 }
        if assessment.risk.isHigh || assessment.recovery.tier == .low { cap = min(cap, 3) }
        if state.goal.distance == .marathon, state.intake.finished != .yesRecently, (recent?.runsPerWeek ?? 0) < 4 { cap = min(cap, 3) }
        return max(cap, assessment.runsCap)
    }

    /// A planned run AD-8 may change: still planned, from today on. Races, tests and benchmark runs never change.
    static func changeable(_ session: PlannedSession, day: Date, today: Date) -> Bool {
        session.status.isPlanned && session.kind.isRun && session.kind != .race && session.kind != .test && !session.isBenchmark && day >= today
    }

    /// An easy run, or a Q already made easy. A benchmark run is kept as it is (BD-5c).
    static func isEasy(_ session: PlannedSession) -> Bool {
        (session.kind == .easy || (session.madeEasy != nil && session.kind != .long)) && !session.isBenchmark
    }

    /// The session's own pace, else the easy pace.
    static func sessionPace(_ session: PlannedSession, state: CoachState) -> Double {
        if session.target.meters > 0, session.target.seconds > 0 { return session.target.seconds / session.target.meters * 1_000 }
        return state.paces.easyPace ?? Scheduler.fallbackEasyPace
    }

    /// Planned sessions dated `first` to `last` days after `date`, in date order.
    static func slots(_ state: CoachState, from first: Int, through last: Int, after date: Date, calendar: Calendar) -> [SessionSlot] {
        var slots: [SessionSlot] = []
        for (week, record) in state.weeks.enumerated() {
            for (index, session) in record.plan.sessions.enumerated() {
                let day = state.date(of: session, in: record.plan, calendar: calendar)
                let offset = days(from: date, to: day, calendar: calendar)
                if offset >= first, offset <= last { slots.append(SessionSlot(week: week, session: index, day: day)) }
            }
        }
        return slots.sorted { ($0.day, $0.week, $0.session) < ($1.day, $1.week, $1.session) }
    }

    /// The position in `state.weeks` of the plan week holding `date`.
    static func weekPosition(of date: Date, in state: CoachState, calendar: Calendar) -> Int? {
        let index = state.weekIndex(on: date, calendar: calendar)
        return state.weeks.firstIndex { $0.plan.index == index }
    }

    static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }

    /// "Thursday's tempo run".
    static func name(_ session: PlannedSession, on day: Date, calendar: Calendar) -> String {
        let kind: String
        switch session.kind {
        case .threshold: kind = "tempo run"
        case .intervals: kind = "intervals"
        case .shortReps: kind = "short reps"
        case .hills: kind = "hill session"
        case .racePace: kind = "race-pace run"
        case .long: kind = "long run"
        default: kind = "run"
        }
        return "\(Weekday(of: day, calendar: calendar).name)'s \(kind)"
    }

    /// "A", "A and B", "A, B and C".
    static func list(_ items: [String]) -> String {
        guard let last = items.last else { return "" }
        return items.count == 1 ? last : items.dropLast().joined(separator: ", ") + " and " + last
    }
}
