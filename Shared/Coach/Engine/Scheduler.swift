//
//  Scheduler.swift
//  Wind Run
//

import Foundation

/// Lays a week's targets out on days and builds each session (RB-5, HL-6, HL-7, HL-10, the weekly templates).
enum Scheduler {
    struct Layout: Hashable {
        var sessions: [PlannedSession]
        var notes: [CoachNote]
        /// Runs the offered days couldn't hold.
        var droppedRuns: Int
        /// The planned running volume after every cap, in the plan's unit.
        var plannedVolume: Double
        /// The long run as placed, after HL-6 and the day limits.
        var longRun: Load?
    }

    /// The pace used when nothing better is known: 7:00/km, a slow easy pace.
    static let fallbackEasyPace: Double = 420

    /// Warm-up before a Q: 15 min, never below 10 (Building blocks).
    static let warmUpSeconds: Double = 15 * 60
    static let shortestWarmUpSeconds: Double = 10 * 60
    static let coolDownSeconds: Double = 10 * 60

    // MARK: Layout

    static func layout(_ targets: WeekTargets, context: PlanningContext) -> Layout {
        let calendar = context.calendar
        let intake = context.state.intake
        let assessment = context.state.assessment
        let firstWeekday = Weekday(of: context.weekStart, calendar: calendar)
        let days = WeekDays(first: firstWeekday)
        let pace = context.easyPace ?? fallbackEasyPace
        let unit = context.unit
        var notes: [CoachNote] = []

        let runDays = intake.runDays.isEmpty ? Set(Weekday.allCases) : intake.runDays
        var available = (0 ..< 7).filter { runDays.contains(days.weekday($0)) }
        if let race = targets.race, !available.contains(race.dayOffset) {
            available.append(race.dayOffset)
            available.sort()
        }

        // Fixed sessions the runner entered never move (RB-5).
        var fixedHard = Set<Int>()
        var legDays = Set<Int>()
        var newLifting = false
        for activity in intake.otherTraining ?? [] {
            for day in activity.days {
                let offset = days.offset(of: day)
                if activity.activityClass == .hard { fixedHard.insert(offset) }
                if activity.isLegSession {
                    legDays.insert(offset)
                    newLifting = newLifting || activity.newOrDoubled
                }
            }
        }
        let legGap = newLifting ? 2 : 1

        var sessions: [PlannedSession] = []

        // Extras that aren't runs go on days without runs, or any day when every day runs.
        func placeExtras(runDays chosen: Set<Int>) {
            var free = (0 ..< 7).filter { !chosen.contains($0) }
            if free.isEmpty { free = Array(0 ..< 7) }
            for (index, kind) in targets.extras.enumerated() {
                let day = free[(index * max(1, free.count / max(1, targets.extras.count))) % free.count]
                let minutes: Double = kind == .walk ? 30 : 20
                sessions.append(PlannedSession(
                    dayOffset: day,
                    kind: kind,
                    effort: .easy,
                    target: Load(meters: 0, seconds: minutes * 60),
                    leadsWith: .time
                ))
            }
        }

        guard targets.runs > 0, targets.volume > 0 || targets.race != nil else {
            placeExtras(runDays: [])
            return Layout(sessions: sessions.sorted { $0.dayOffset < $1.dayOffset }, notes: notes, droppedRuns: 0, plannedVolume: 0, longRun: nil)
        }

        let tier = assessment.tier
        let age = assessment.age
        let noBackToBack = tier <= .novice || (age >= 50 && tier < .experienced)
        let tenB = targets.runs == 4 && (tier == .novice || (age >= 50 && tier == .regular))
        let minimumRest = max(targets.minimumRestDays ?? 0, tier <= .novice ? 2 : 1)
        let qGap = age >= 60 ? 3 : 2

        // The long run (or the race) day.
        var longDay: Int?
        if let race = targets.race {
            longDay = race.dayOffset
        } else if targets.longRun != nil {
            longDay = chooseLongDay(available: available, preferred: intake.longRunDay.map(days.offset(of:)), legDays: legDays, legGap: legGap)
        }

        // The other run days.
        let wanted = max(0, targets.runs - (longDay == nil ? 0 : 1))
        var chosen: [Int] = []
        var placed = wanted
        while placed > 0 {
            if let set = chooseDays(
                count: placed,
                from: available.filter { $0 != longDay },
                longDay: longDay,
                totalRuns: placed + (longDay == nil ? 0 : 1),
                noBackToBack: noBackToBack,
                tenB: tenB,
                minimumRest: minimumRest
            ) {
                chosen = set
                break
            }
            placed -= 1
        }
        let dropped = wanted - placed
        if dropped > 0 {
            notes.append(CoachNote(.plan, "Your run days fit \(placed + (longDay == nil ? 0 : 1)) runs this week, so the others carry the week's running as far as the safety limits allow."))
        }

        var runDaysChosen = Set(chosen)
        if let longDay { runDaysChosen.insert(longDay) }

        // Hard days so far: the race, a long run over 90 min, fixed hard sessions.
        let longIsHard = targets.race != nil || (targets.longRun.map { longRunSeconds($0, pace: pace) > CoachLimits.hardLongRunSeconds } ?? false)
        var hardDays = fixedHard
        if let longDay, longIsHard { hardDays.insert(longDay) }

        // Q days: template slots first, then any day that keeps the gaps (HL-7, RB-5).
        var qDays: [Int: QualityDose] = [:]
        var madeEasy: [Int: EasyReason] = [:]
        let slots = qualitySlotOrder(chosen: chosen, longDay: longDay)
        for dose in targets.quality {
            let pick = slots.first { day in
                qDays[day] == nil
                    && !days.adjacent(day, toAny: hardDays.subtracting([day]))
                    && qDays.keys.allSatisfy { days.distance($0, day) >= qGap }
                    && !(1 ... legGap).contains { legDays.contains(days.wrap(day - $0)) }
                    && !fixedHard.contains(day)
            }
            if let pick {
                qDays[pick] = dose
                hardDays.insert(pick)
            } else if let fallback = slots.first(where: { qDays[$0] == nil && madeEasy[$0] == nil }) {
                madeEasy[fallback] = .spacing
                notes.append(CoachNote(.limit, "\(days.weekday(fallback).name)'s session is an easy run this week, so hard days don't touch."))
            }
        }

        // HL-10b: the second of a pair of neighbouring run days is the week's shortest easy run.
        var shortestDay: Int?
        if tenB {
            let all = Array(runDaysChosen).sorted()
            shortestDay = all.first { day in all.contains(days.wrap(day - 1)) && day != longDay && qDays[day] == nil }
        }

        // Volumes. The long run first, then Q, then the easy runs share the rest (HL-6).
        let easyDays = chosen.filter { qDays[$0] == nil }.sorted()
        let minimumRun = amount(seconds: CoachLimits.minimumRunSeconds, unit: unit, pace: pace)
        var longRun = targets.longRun
        if let cap = targets.sessionCap, let current = longRun { longRun = current.capped(at: cap) }
        if let current = longRun, let longDay, let dayMax = intake.maxSeconds(on: days.weekday(longDay)), dayMax > 0 {
            longRun = current.capped(at: Load(dayMax, in: .time, pace: pace))
        }

        let qSessions: [Int: PlannedSession] = qDays.reduce(into: [:]) { result, item in
            result[item.key] = qualitySession(item.value, day: item.key, context: context, unit: unit)
        }
        let qVolume = qSessions.values.reduce(0) { $0 + $1.target.amount(in: unit) }
        let longVolume = longRun?.amount(in: unit) ?? 0

        let easyCount = easyDays.count
        var easyShare = 0.0
        if easyCount > 0 {
            let shortWeight = shortestDay == nil ? 0.0 : 0.2
            easyShare = max(0, targets.volume - longVolume - qVolume) / (Double(easyCount) - shortWeight)
            if easyShare < minimumRun, longRun != nil {
                // HL-6: the other runs stay ≥20 min, so the long run gives way (it is held, or shrinks to fit).
                let room = targets.volume - qVolume - minimumRun * (Double(easyCount) - shortWeight)
                let newLong = max(minimumRun, room)
                if newLong < longVolume {
                    longRun = Load(newLong, in: unit, pace: pace)
                    notes.append(CoachNote(.limit, "Your other runs stay at 20 minutes or more, so the long run holds this week."))
                }
                easyShare = minimumRun
            }
            easyShare = max(easyShare, minimumRun)
            if let longRun {
                let ceiling = max(longRun.amount(in: unit) * CoachLimits.otherRunShare, context.state.assessment.start.sustainedRunLength ?? 0)
                if easyShare > ceiling, ceiling >= minimumRun { easyShare = ceiling }
            }
        }

        // Build the sessions.
        if let longDay {
            if let race = targets.race {
                sessions.append(raceSession(race, context: context))
            } else if let longRun {
                let session = PlannedSession(
                    dayOffset: longDay,
                    kind: .long,
                    effort: .easy,
                    target: Load(longRun.amount(in: unit), in: unit, pace: pace),
                    leadsWith: unit,
                    paceBand: context.state.paces.easy,
                    blocks: runWalkBlocks(targets.form, seconds: longRunSeconds(longRun, pace: pace)),
                    isKey: context.state.goal.flavor != .speedWork,
                    isNewLongest: targets.isNewLongest && longRun.amount(in: unit) > context.longest.amount(in: unit) + 0.000_1
                )
                sessions.append(session)
            }
        }
        for (day, session) in qSessions {
            var session = session
            session.isKey = context.state.goal.flavor == .speedWork && session.dose == targets.quality.first
            sessions.append(session)
            _ = day
        }
        var stridesLeft = targets.strides
        for day in easyDays {
            var share = easyShare
            if day == shortestDay { share *= 0.8 }
            var load = Load(share, in: unit, pace: pace)
            if let cap = targets.sessionCap { load = load.capped(at: cap) }
            if let dayMax = intake.maxSeconds(on: days.weekday(day)), dayMax > 0 {
                load = load.capped(at: Load(dayMax, in: .time, pace: pace))
            }
            var session = PlannedSession(
                dayOffset: day,
                kind: targets.form == .continuous ? .easy : (targets.form == .walk ? .walk : .runWalk),
                effort: .easy,
                target: load,
                leadsWith: targets.form == .continuous ? unit : .time,
                paceBand: targets.form == .continuous ? context.state.paces.easy : nil,
                blocks: runWalkBlocks(targets.form, seconds: load.seconds > 0 ? load.seconds : share),
                madeEasy: madeEasy[day]
            )
            if stridesLeft > 0, targets.form == .continuous, day != shortestDay, !days.adjacent(day, toAny: Set(qDays.keys)) {
                session.strides = 4
                stridesLeft -= 1
            }
            sessions.append(session)
        }

        placeExtras(runDays: runDaysChosen)

        let planned = sessions.filter { $0.kind.isRun }.reduce(0) { $0 + $1.target.amount(in: unit) }
        return Layout(
            sessions: sessions.sorted { $0.dayOffset < $1.dayOffset },
            notes: notes,
            droppedRuns: dropped,
            plannedVolume: planned,
            longRun: targets.race == nil ? longRun.map { Load($0.amount(in: unit), in: unit, pace: pace) } : nil
        )
    }

    // MARK: Days

    /// Offsets 0-6 in a plan week and their weekdays. Spacing checks treat the week as a repeating rhythm.
    struct WeekDays {
        var first: Weekday

        func weekday(_ offset: Int) -> Weekday { first.adding(offset) }

        func offset(of day: Weekday) -> Int { ((day.rawValue - first.rawValue) % 7 + 7) % 7 }

        func wrap(_ offset: Int) -> Int { (offset % 7 + 7) % 7 }

        /// Days between two offsets around the week, 0-3.
        func distance(_ a: Int, _ b: Int) -> Int {
            let d = abs(a - b) % 7
            return min(d, 7 - d)
        }

        func adjacent(_ day: Int, toAny others: Set<Int>) -> Bool {
            others.contains { distance($0, day) == 1 }
        }
    }

    /// The long run goes on the runner's long-run day, unless leg work sits within its gap before it (RB-5).
    static func chooseLongDay(available: [Int], preferred: Int?, legDays: Set<Int>, legGap: Int) -> Int? {
        guard !available.isEmpty else { return preferred }
        let clear: (Int) -> Bool = { day in !(1 ... legGap).contains { legDays.contains(((day - $0) % 7 + 7) % 7) } }
        if let preferred, available.contains(preferred) {
            if clear(preferred) { return preferred }
            if let other = available.reversed().first(where: clear) { return other }
            return preferred
        }
        return available.reversed().first(where: clear) ?? available.last
    }

    /// The template's other run days relative to the long-run day L (Weekly templates).
    static func template(runs: Int, tenB: Bool) -> [Int] {
        switch runs {
        case ...1: []
        case 2: [-4]
        case 3: [-5, -3]
        case 4: tenB ? [-5, -3, -2] : [-5, -3, -1]
        default: [-5, -4, -3, -1]
        }
    }

    /// Picks `count` run days besides the long run: rest days and back-to-back rules first (HL-10), then the
    /// template, then the widest spread.
    static func chooseDays(
        count: Int,
        from candidates: [Int],
        longDay: Int?,
        totalRuns: Int,
        noBackToBack: Bool,
        tenB: Bool,
        minimumRest: Int
    ) -> [Int]? {
        guard count > 0 else { return [] }
        guard candidates.count >= count, 7 - totalRuns >= minimumRest else { return nil }
        let anchor = longDay ?? 6
        let preferred = Set(template(runs: totalRuns, tenB: tenB).map { ((anchor + $0) % 7 + 7) % 7 })
        var best: (days: [Int], score: Double)?
        for combo in combinations(candidates, count) {
            var all = combo
            if let longDay { all.append(longDay) }
            let set = Set(all)
            let pairs = all.filter { set.contains(($0 + 1) % 7) }
            if noBackToBack {
                if !tenB, !pairs.isEmpty { continue }
                if tenB {
                    // One pair at most, its second run isn't the long run, and the day after it is a rest day.
                    if pairs.count > 1 { continue }
                    if let first = pairs.first {
                        let second = (first + 1) % 7
                        if second == longDay || set.contains((second + 1) % 7) { continue }
                    }
                }
            }
            let misses = Double(combo.filter { !preferred.contains($0) }.count)
            let spread = Double(pairs.count) * 0.5
            let score = misses + spread
            if best == nil || score < best!.score { best = (combo.sorted(), score) }
        }
        return best?.days
    }

    static func combinations(_ items: [Int], _ k: Int) -> [[Int]] {
        guard k > 0 else { return [[]] }
        guard items.count >= k else { return [] }
        if k == items.count { return [items] }
        var result: [[Int]] = []
        for (index, item) in items.enumerated() {
            for rest in combinations(Array(items[(index + 1)...]), k - 1) {
                result.append([item] + rest)
            }
        }
        return result
    }

    /// Q slots in template order: L−5 first (the week's main Q), then L−3, then the others farthest from L.
    static func qualitySlotOrder(chosen: [Int], longDay: Int?) -> [Int] {
        guard let longDay else { return chosen }
        let rank: (Int) -> Int = { day in
            let before = ((longDay - day) % 7 + 7) % 7
            switch before {
            case 5: return 0
            case 3: return 1
            case 4: return 2
            case 6: return 3
            case 2: return 4
            default: return 5
            }
        }
        return chosen.sorted { rank($0) < rank($1) }
    }

    // MARK: Sessions

    static func amount(seconds: Double, unit: VolumeUnit, pace: Double) -> Double {
        unit == .time ? seconds : seconds / pace * 1_000
    }

    static func longRunSeconds(_ load: Load, pace: Double) -> Double {
        load.seconds > 0 ? load.seconds : load.meters / 1_000 * pace
    }

    /// Run-walk steps that fill a session of `seconds`.
    static func runWalkBlocks(_ form: RunForm, seconds: Double) -> [SessionBlock] {
        guard case let .runWalk(run, walk) = form, run > 0 else { return [] }
        let cycle = run + (walk ?? 90)
        let repeats = max(1, Int((seconds / cycle).rounded(.down)))
        return [SessionBlock(repeats: repeats, steps: [
            SessionStep(kind: .work, goal: .time(seconds: run), effort: .easy),
            SessionStep(kind: .recovery, goal: walk.map { .time(seconds: $0) } ?? .open, effort: .easy, walk: true),
        ])]
    }

    /// A Q session: warm-up, the dose and a cool-down. The whole session fits HL-1: the cool-down shortens
    /// first, then the warm-up (not below 10 min), then reps drop (Building blocks).
    static func qualitySession(_ dose: QualityDose, day: Int, context: PlanningContext, unit: VolumeUnit) -> PlannedSession {
        let paces = context.state.paces
        let easyPace = paces.easyPace ?? fallbackEasyPace
        let workPace: Double?
        switch dose.type {
        case .threshold: workPace = paces.thresholdPace
        case .vo2max: workPace = paces.intervalPace
        case .racePace: workPace = paces.racePace
        case .shortReps, .hills: workPace = nil
        }
        var dose = dose
        var warmUp = warmUpSeconds
        var coolDown = coolDownSeconds
        let cap = context.longest.seconds > 0 ? context.longest.seconds * CoachLimits.sessionGrowth : .infinity
        func total() -> Double {
            warmUp + coolDown + Double(dose.reps) * dose.repSeconds + Double(max(0, dose.reps - 1)) * dose.recoverySeconds
        }
        while total() > cap {
            if coolDown > 0 {
                coolDown = max(0, coolDown - 60)
            } else if warmUp > shortestWarmUpSeconds {
                warmUp = max(shortestWarmUpSeconds, warmUp - 60)
            } else if dose.reps > 1 {
                dose.reps -= 1
            } else {
                break
            }
        }

        let workEffort = dose.type.effort
        let band = workPace.map { PaceBand(fast: $0 * 0.98, slow: $0 * 1.02) }
        var steps: [SessionStep] = []
        steps.append(SessionStep(kind: .work, goal: .time(seconds: dose.repSeconds), effort: workEffort, pace: band))
        if dose.reps > 1, dose.recoverySeconds > 0 {
            steps.append(SessionStep(kind: .recovery, goal: .time(seconds: dose.recoverySeconds), effort: .easy, walk: dose.type == .hills))
        }
        var blocks = [SessionBlock(steps: [SessionStep(kind: .warmup, goal: .time(seconds: warmUp), effort: .easy, pace: paces.easy)])]
        blocks.append(SessionBlock(repeats: dose.continuous ? 1 : dose.reps, steps: steps))
        if coolDown > 0 {
            blocks.append(SessionBlock(steps: [SessionStep(kind: .cooldown, goal: .time(seconds: coolDown), effort: .easy, pace: paces.easy)]))
        }

        let seconds = total()
        let workMeters = workPace.map { dose.workSeconds / $0 * 1_000 } ?? dose.workSeconds / (easyPace * 0.85) * 1_000
        let easyMeters = (warmUp + coolDown + Double(max(0, dose.reps - 1)) * dose.recoverySeconds) / (easyPace * 1.1) * 1_000
        var notes: [String] = []
        if dose.type == .vo2max { notes.append("Finish the warm-up with 4 relaxed strides.") }
        return PlannedSession(
            dayOffset: day,
            kind: dose.type.sessionKind,
            effort: workEffort,
            target: Load(meters: workMeters + easyMeters, seconds: seconds),
            leadsWith: .time,
            paceBand: band,
            blocks: blocks,
            dose: dose,
            notes: notes
        )
    }

    /// The race itself (EV-8) or a Speed Work attempt (SW-8).
    static func raceSession(_ race: RaceDay, context: PlanningContext) -> PlannedSession {
        let seconds = race.targetSeconds ?? race.distance.meters / 1_000 * (context.easyPace ?? fallbackEasyPace)
        return PlannedSession(
            dayOffset: race.dayOffset,
            kind: .race,
            effort: .race,
            target: Load(meters: race.distance.meters, seconds: seconds),
            leadsWith: .distance,
            isKey: true
        )
    }
}
