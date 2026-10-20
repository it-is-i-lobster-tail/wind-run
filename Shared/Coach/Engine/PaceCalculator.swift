//
//  PaceCalculator.swift
//  Wind Run
//

import Foundation

/// Training paces and race forecasts from current ability, never from the goal (PZ-2 to PZ-8, PZ-11).
enum PaceCalculator {
    /// Anchors expire after 26 weeks (PZ-2).
    static let anchorWeeks = 26
    /// Results dated within 8 weeks before the anchor join its forecast set (PZ-2).
    static let forecastSetWeeks = 8

    /// t2 = t1 × (d2 ÷ d1)^k (PZ-4).
    static func equivalent(seconds: Double, meters: Double, to distance: Double, k: Double = 1.07) -> Double {
        guard meters > 0 else { return 0 }
        return seconds * pow(distance / meters, k)
    }

    // MARK: Anchors (PZ-2)

    /// A result that can anchor paces and forecasts: a time and a distance on a usable course, and not a
    /// benchmark that showed no clear change (PZ-2, PZ-3a).
    static func isValid(_ result: RaceResult) -> Bool {
        result.meters > 0 && result.seconds > 0 && result.course != .veryHilly && !result.noClearChange
    }

    /// The anchor in force: the newest valid result up to 26 weeks old that no break of more than 28 days has
    /// expired (PZ-2).
    static func anchor(_ results: [RaceResult], now: Date, calendar: Calendar, expiredBefore: Date? = nil) -> RaceResult? {
        let oldest = calendar.date(byAdding: .day, value: -7 * anchorWeeks, to: now) ?? now
        return results
            .filter { isValid($0) && $0.date >= oldest && $0.date <= now && !isExpired($0, before: expiredBefore) }
            .max { $0.date < $1.date }
    }

    static func isExpired(_ result: RaceResult, before date: Date?) -> Bool {
        date.map { result.date < $0 } ?? false
    }

    /// Every result the paces keep, the anchor included.
    static func allResults(_ paces: TrainingPaces) -> [RaceResult] {
        var results = paces.results
        if let anchor = paces.anchor, !results.contains(where: { $0.id == anchor.id }) { results.append(anchor) }
        return results
    }

    static func anchorInForce(_ paces: TrainingPaces, now: Date, calendar: Calendar) -> RaceResult? {
        anchor(allResults(paces), now: now, calendar: calendar, expiredBefore: paces.expiredBefore)
    }

    /// PZ-2's forecast set: the anchor in force first, then every other valid result dated within 8 weeks before it.
    static func forecastSet(_ paces: TrainingPaces, now: Date, calendar: Calendar) -> [RaceResult] {
        guard let anchor = anchorInForce(paces, now: now, calendar: calendar) else { return [] }
        let earliest = calendar.date(byAdding: .day, value: -7 * forecastSetWeeks, to: anchor.date) ?? anchor.date
        let others = allResults(paces).filter { result in
            result.id != anchor.id && isValid(result) && result.date >= earliest && result.date <= anchor.date
                && !isExpired(result, before: paces.expiredBefore)
        }
        return [anchor] + others.sorted { $0.date > $1.date }
    }

    /// PZ-4's personal k, from the two newest all-out efforts up to 26 weeks old at clearly different distances;
    /// nil without two, or when it falls outside 1.04-1.20 (a retest is due instead).
    static func personalK(_ paces: TrainingPaces, now: Date, calendar: Calendar) -> Double? {
        let oldest = calendar.date(byAdding: .day, value: -7 * anchorWeeks, to: now) ?? now
        let efforts = allResults(paces)
            .filter { isValid($0) && $0.allOut && !$0.treadmill && $0.date >= oldest && $0.date <= now && !isExpired($0, before: paces.expiredBefore) }
            .sorted { $0.date > $1.date }
        guard let first = efforts.first,
              let second = efforts.dropFirst().first(where: { max($0.meters, first.meters) / min($0.meters, first.meters) >= 1.5 })
        else { return nil }
        let (short, long) = first.meters < second.meters ? (first, second) : (second, first)
        let k = log(long.seconds / short.seconds) / log(long.meters / short.meters)
        return (1.04 ... 1.20).contains(k) ? k : nil
    }

    // MARK: Paces (PZ-5)

    /// The first paces from intake (PZ-5): the easy band from the reported pace or the anchor (the band
    /// whose fast edge is slower when both exist), threshold and interval paces from the anchor. A race from
    /// before a break of 4 weeks or more has expired (PZ-2).
    static func initialPaces(_ intake: CoachIntake, now: Date, calendar: Calendar) -> TrainingPaces {
        var paces = TrainingPaces()
        if let weeks = intake.breakBeganWeeksAgo, weeks >= 4 {
            paces.expiredBefore = calendar.date(byAdding: .day, value: -Int((weeks * 7).rounded()), to: calendar.startOfDay(for: now))
        }
        if let race = intake.race, isValid(race) {
            paces.results = [race]
        }
        let anchor = anchorInForce(paces, now: now, calendar: calendar)
        paces.anchor = anchor
        var bands: [(PaceBand, EasyPaceSource)] = []
        if let easy = intake.easyPace, easy > 0 {
            bands.append((PaceBand(fast: easy, slow: easy * 1.10), .reported))
        }
        if let anchor {
            bands.append((easyBand(from: anchor), .anchor))
            paces = withQualityPaces(paces, anchor: anchor)
        }
        if let slowest = bands.max(by: { $0.0.fast < $1.0.fast }) {
            paces.easy = slowest.0
            paces.easySource = slowest.1
        }
        return paces
    }

    /// PZ-5's easy band from an anchor: 5K pace × 1.28 to × 1.40.
    static func easyBand(from anchor: RaceResult) -> PaceBand {
        let fiveK = equivalent(seconds: anchor.seconds, meters: anchor.meters, to: 5_000) / 5
        return PaceBand(fast: fiveK * 1.28, slow: fiveK * 1.40)
    }

    /// Threshold (60-min race pace + 3%, never faster than 10K pace) and interval (5K pace, nil over 30:00) paces.
    static func withQualityPaces(_ paces: TrainingPaces, anchor: RaceResult) -> TrainingPaces {
        var paces = paces
        let quality = qualityPaces(from: anchor)
        paces.threshold = quality.threshold
        paces.interval = quality.interval
        return paces
    }

    /// PZ-5's threshold and interval paces for an anchor, before any PZ-7 factor.
    static func qualityPaces(from anchor: RaceResult) -> (threshold: Double, interval: Double?) {
        let d60 = anchor.meters * pow(3_600 / anchor.seconds, 1 / 1.07)
        let sixtyMinutePace = 3_600 / d60 * 1_000
        let tenKPace = equivalent(seconds: anchor.seconds, meters: anchor.meters, to: 10_000) / 10
        let fiveK = equivalent(seconds: anchor.seconds, meters: anchor.meters, to: 5_000)
        return (max(sixtyMinutePace * 1.03, tenKPace), fiveK <= 30 * 60 ? fiveK / 5 : nil)
    }

    // MARK: Forecasts (PZ-4)

    /// The race forecast from the anchor in force (PZ-4), or nil with effort only. Without logged runs the
    /// durability check has no run, which counts as a fail.
    static func forecast(
        _ distance: RaceDistance,
        paces: TrainingPaces,
        firstTime: Bool,
        weeklyMeters: Double,
        age: Int,
        now: Date,
        calendar: Calendar
    ) -> RaceForecast? {
        forecast(distance, paces: paces, context: ForecastContext(firstTime: firstTime, weeklyMeters: weeklyMeters, age: age), now: now, calendar: calendar)
    }

    /// The race forecast at a distance (PZ-4): every result in PZ-2's forecast set converted with the k its
    /// switches pick, the slowest winning, with the range PZ-4 and PZ-2 set. Nil without an anchor (PZ-6).
    static func forecast(_ distance: RaceDistance, paces: TrainingPaces, context: ForecastContext, now: Date, calendar: Calendar) -> RaceForecast? {
        let set = forecastSet(paces, now: now, calendar: calendar)
        let personal = personalK(paces, now: now, calendar: calendar)
        return set
            .map { forecast(distance, from: $0, context: context, personalK: personal, now: now, calendar: calendar) }
            .max { $0.central < $1.central }
    }

    /// The forecast for a plan, from its logs: weekly distance, durability and missed weeks (PZ-4, EF-1).
    static func forecast(_ distance: RaceDistance, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> RaceForecast? {
        forecast(distance, paces: state.paces, context: forecastContext(for: distance, state: state, runs: runs, now: now, calendar: calendar), now: now, calendar: calendar)
    }

    /// One result's forecast. The half takes k 1.10 and the marathon 1.15 when any of PZ-4's switches applies;
    /// otherwise a personal k is averaged with the default, never below 1.06 (half and shorter) or 1.12 (marathon).
    static func forecast(_ distance: RaceDistance, from result: RaceResult, context: ForecastContext, personalK: Double?, now: Date, calendar: Calendar) -> RaceForecast {
        let defaultK = distance == .marathon ? 1.12 : 1.07
        let atDefault = equivalent(seconds: result.seconds, meters: result.meters, to: distance.meters, k: defaultK)
        let durabilityFailed = atDefault > 2 * 3_600 && context.durable != true
        var conservative = false
        switch distance {
        case .halfMarathon:
            conservative = context.firstTime || atDefault > 2 * 3_600 || result.meters <= 5_000 || context.weeklyMeters < 25_000 || durabilityFailed
        case .marathon:
            conservative = context.firstTime || context.weeklyMeters < 40_000 || context.age >= 50 || result.meters <= 10_000 || durabilityFailed
        case .mile, .fiveK, .tenK:
            break
        }
        var k = defaultK
        if conservative {
            k = distance == .marathon ? 1.15 : 1.10
        } else if let personalK {
            k = max((defaultK + personalK) / 2, distance == .marathon ? defaultK : 1.06)
        }
        let central = equivalent(seconds: result.seconds, meters: result.meters, to: distance.meters, k: k)

        // ±3% at the anchor's distance, ±5% for a half or shorter from another distance, ±8% for a marathon;
        // then the slow-runner, missed-week and PZ-2 additions.
        var points: Double
        if abs(result.meters - distance.meters) <= 0.01 * distance.meters {
            points = 3
        } else {
            points = distance == .marathon ? 8 : 5
        }
        if distance == .marathon {
            if central > 4.5 * 3_600 { points += 4 }
        } else if equivalent(seconds: result.seconds, meters: result.meters, to: 5_000) > 30 * 60 {
            points += 2
        }
        points += Double(min(4, max(0, context.missedWeeks)))
        let ageDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: result.date), to: calendar.startOfDay(for: now)).day ?? 0
        if ageDays >= 13 * 7 { points += 3 }
        if let before = result.weeklyMetersBefore, before > 0, context.weeklyMeters < 0.6 * before { points += 3 }
        if result.course == .hilly { points += 2 }
        let range = points / 100
        let confidence: ForecastConfidence = distance.meters > 4.5 * result.meters || result.treadmill ? .low : .normal
        return RaceForecast(
            distance: distance,
            central: central,
            low: central * (1 - range),
            high: central * (1 + range),
            k: k,
            confidence: confidence,
            rangeFraction: range,
            anchorID: result.id,
            lowPrecision: result.lowPrecision,
            durabilityFailed: durabilityFailed
        )
    }

    /// What a forecast needs from a plan's logs (PZ-4, EF-1): first-timer status, weekly distance over the last
    /// 4 weeks, durability, and fully missed plan weeks since the anchor.
    static func forecastContext(for distance: RaceDistance, state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> ForecastContext {
        let since = calendar.date(byAdding: .day, value: -28, to: now) ?? now
        let weekly = runs.filter { $0.start >= since && $0.start <= now }.reduce(0) { $0 + $1.meters } / 4
        let raced = racedDistances(state.paces, now: now, calendar: calendar)
        var firstTime = !raced.contains { $0 >= distance }
        if firstTime, distance <= state.intake.goal.distance, state.intake.finished == .yesRecently { firstTime = false }
        return ForecastContext(
            firstTime: firstTime,
            weeklyMeters: weekly,
            age: state.assessment.age,
            durable: durability(runs, now: now, calendar: calendar),
            missedWeeks: missedWeeks(state: state, runs: runs, now: now, calendar: calendar)
        )
    }

    /// Distances finished in a race in about the last 18 months (TI-3's first-timer window).
    static func racedDistances(_ paces: TrainingPaces, now: Date, calendar: Calendar) -> Set<RaceDistance> {
        let since = calendar.date(byAdding: .month, value: -18, to: now) ?? now
        let races = allResults(paces).filter { $0.source == .race && $0.date >= since && $0.date <= now }
        return Set(RaceDistance.allCases.filter { distance in races.contains { $0.meters >= distance.meters * 0.98 } })
    }

    /// PZ-4's durability check, for forecasts over 2 hours: a run of 90 minutes or more in the last 4 weeks whose
    /// final third is less than 10% slower than its pace from minute 10 to the 30% mark, and that didn't end at
    /// RPE 7 or more as an easy run. Nil when no run qualifies, which counts as a fail.
    static func durability(_ runs: [LoggedRun], now: Date, calendar: Calendar) -> Bool? {
        let since = calendar.date(byAdding: .day, value: -28, to: now) ?? now
        let candidates = runs.filter { run in
            run.start >= since && run.start <= now && run.movingSeconds >= 90 * 60 && !(run.track?.splits.isEmpty ?? true)
        }
        guard !candidates.isEmpty else { return nil }
        return candidates.contains { run in
            let splits = run.track?.splits ?? []
            let total = splits.reduce(0) { $0 + $1.seconds }
            var elapsed = 0.0
            var early = (meters: 0.0, seconds: 0.0)
            var late = (meters: 0.0, seconds: 0.0)
            for split in splits {
                let middle = elapsed + split.seconds / 2
                if middle >= 10 * 60, middle <= 0.3 * total {
                    early.meters += split.meters
                    early.seconds += split.seconds
                }
                if middle >= total * 2 / 3 {
                    late.meters += split.meters
                    late.seconds += split.seconds
                }
                elapsed += split.seconds
            }
            guard early.meters > 0, late.meters > 0 else { return false }
            if late.seconds / late.meters >= early.seconds / early.meters * 1.10 { return false }
            if let rpe = run.rpe, rpe >= 7, run.checkIn?.raceOrAllOut != true { return false }
            return true
        }
    }

    /// Plan weeks since the anchor with running planned and none logged (PZ-4: +1 range point each, at most 4).
    static func missedWeeks(state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> Int {
        let anchorDate = anchorInForce(state.paces, now: now, calendar: calendar)?.date ?? state.startDate
        let current = state.weekIndex(on: now, calendar: calendar)
        return state.weeks.filter { record in
            let week = record.plan
            guard week.index < current, week.start >= anchorDate, week.plannedVolume > 0 else { return false }
            let end = calendar.date(byAdding: .day, value: 7, to: week.start) ?? week.start
            return !runs.contains { $0.start >= week.start && $0.start < end }
        }.count
    }

    // MARK: Heart rate (PZ-11)

    /// PZ-11: max heart rate 208 − 0.7 × age, a lab value only if lower, raised by an observed max.
    static func heartRateZones(age: Int, settings: HeartRateSettings, observedMax: Double? = nil, threshold: Double? = nil) -> HeartRateZones {
        var zones = HeartRateZones.estimated(age: age, labMax: settings.labMax)
        if let observedMax, observedMax > zones.max {
            zones.max = observedMax
            zones.maxObserved = true
        }
        zones.threshold = threshold
        return zones
    }
}
