//
//  RunInsights.swift
//  Wind Run
//

import Foundation

/// A candidate for FB-1's second slot. Safety comes first, then consistency, pacing and technique; within a level
/// the larger deviation wins.
struct Insight: Hashable {
    enum Level: Int, Comparable {
        case safety
        case consistency
        case pacing
        case technique

        static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var level: Level
    var text: String
    /// The deviation behind it, as a fraction, for the order within a level.
    var size: Double

    init(_ level: Level, _ text: String, size: Double = 0) {
        self.level = level
        self.text = text
        self.size = size
    }
}

/// FB-1 and FB-7: what the coach says after a run. At most two insights, the first positive; one number each, in
/// the runner's unit; "usually", never a promise. Internal labels (Struggled, Failed, marked, family E) never show.
enum RunInsights {
    /// "7%": one whole number per insight (FB-7).
    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// FB-1: slot 1 takes the first positive item, else the plain fact; slot 2 the first candidate in level order,
    /// the larger deviation first. Nothing in slot 2 repeats slot 1.
    static func choose(positives: [CoachNote], plainFact: CoachNote, candidates: [Insight]) -> [CoachNote] {
        let first = positives.first ?? plainFact
        let second = candidates.enumerated()
            .filter { $0.element.text != first.text }
            .min { lhs, rhs in
                if lhs.element.level != rhs.element.level { return lhs.element.level < rhs.element.level }
                if lhs.element.size != rhs.element.size { return lhs.element.size > rhs.element.size }
                return lhs.offset < rhs.offset
            }
        return [first] + (second.map { [CoachNote(.insight, $0.element.text)] } ?? [])
    }

    // MARK: Slot 1

    /// FB-4g's lines for a session done well.
    static func positiveOutcome(_ outcome: SessionOutcome) -> String? {
        switch outcome {
        case .evenAndOnTarget: "Even pacing, right on target. Nice work."
        case .completed: "Session done as planned. Nice work."
        case .struggled, .failed: nil
        }
    }

    /// FB-4a's "more in reserve", even and held rows.
    static func positiveFade(_ row: FadeRow?) -> String? {
        switch row {
        case .moreInReserve?: "You finished faster than you started: well judged, with more in reserve."
        case .even?: "Nicely even: your two halves were within 2%."
        case .held?: "You held your pace well; most marathoners slow more than this."
        default: nil
        }
    }

    /// The planned run done: "You ran all 20 minutes at race pace, as planned." Races have their own review.
    static func plannedDone(_ session: PlannedSession) -> String? {
        if session.madeEasy != nil { return "Easy run done, as planned." }
        if let dose = session.dose {
            if dose.continuous || dose.reps == 1 {
                return "You ran all \(Int((dose.workSeconds / 60).rounded())) minutes at \(pacePhrase(session.kind)), as planned."
            }
            return "You ran all \(dose.reps) reps, as planned."
        }
        return session.kind == .race ? nil : "\(session.kind.name) done, as planned."
    }

    static func pacePhrase(_ kind: SessionKind) -> String {
        switch kind {
        case .threshold: "tempo pace"
        case .intervals: "interval pace"
        case .shortReps: "short-rep pace"
        case .hills: "hill effort"
        case .racePace: "race pace"
        default: "the planned effort"
        }
    }

    /// "8.2 km in 52:29, run 3 this week." A run without a distance gives its running minutes.
    static func plainFact(_ run: LoggedRun, number: Int, unit: DistanceUnit) -> String {
        if run.meters > 0 {
            return "\(CoachFormat.distance(run.meters, unit: unit)) in \(CoachFormat.clock(run.movingSeconds)), run \(number) this week."
        }
        return "\(CoachFormat.minutes(run.runningSeconds)) of running, run \(number) this week."
    }

    /// FB-4m's faster trend.
    static func fasterTrend(_ fraction: Double) -> String {
        "Same effort, faster pace: your easy runs are \(percent(fraction)) quicker than a month ago. Want to try a benchmark sooner?"
    }

    /// FB-4l both ways. Heart-rate lines are training guidance, never a health claim (FB-7).
    static let lowerHeartRate = "Same pace, lower heart rate: your easy runs are getting easier. Want to try a benchmark sooner?"
    static let higherHeartRate = "Your heart rate is higher than usual for this pace; an easy day may help."

    // MARK: Slot 2

    /// FB-4g's lines for a hard session, when no pacing message explains it.
    static func hardOutcome(_ outcome: SessionOutcome) -> String? {
        switch outcome {
        case .failed: "That session asked too much today. The next one is shorter and a little slower."
        case .struggled: "That one was tough, so we'll repeat it before moving on."
        case .evenAndOnTarget, .completed: nil
        }
    }

    /// FB-5's messages, at their place in FB-1's order: heat is safety, the rest explains the pace. Pacing itself
    /// has no message here (the FB-4 message speaks), and an unknown heat tier allows only the neutral note.
    static func causeInsight(_ cause: FadeCause) -> Insight? {
        switch cause {
        case .data: Insight(.pacing, "GPS was patchy, so I've counted the distance but skipped pace feedback.", size: 1)
        case .hills: Insight(.pacing, "Your second half had more climbing, so a slower pace there is expected.", size: 1)
        case .heatFastStart: Insight(.safety, "It was warm and you started quicker than the heat allows. Next time start slower, or run earlier.", size: 1)
        case .heat: Insight(.safety, "Mostly heat: pace slows when it's hot, and your effort was right.", size: 1)
        case .fuel: Insight(.pacing, fuelText, size: 1)
        case .pacing, .heatUnknown: nil
        }
    }

    static let fuelText = "On runs over 90 minutes, try 30 g of carbohydrate per hour."

    /// FB-4a's neutral note for a mild fade, and for any fade when heat can't be ruled out (FB-5).
    static func neutralFade(_ change: Double) -> String {
        "Your second half was \(percent(change)) slower than your first, which is common."
    }

    /// The run a pacing message names: "your next race-pace run".
    static func runName(_ kind: SessionKind?) -> String {
        switch kind {
        case .racePace?: "race-pace run"
        case .threshold?: "tempo run"
        case .race?: "race"
        case .long?: "long run"
        case .easy?: "easy run"
        default: "paced run"
        }
    }

    /// FB-4a after a fast start (FB-4b). A hard outcome adds the next session's change in place of its own line
    /// (FB-1, FB-6). In Build Distance the band is only a ceiling at the easy band's fast edge.
    static func fastStartFade(
        change: Double,
        firstKilometre: Bool,
        segment: Bool,
        next: String,
        outcome: SessionOutcome?,
        buildDistance: Bool,
        ceiling: Double?,
        unit: DistanceUnit
    ) -> String {
        let start = "Your pace dropped \(percent(change)) in the second half after a \(firstKilometre ? "fast first kilometre" : "fast start")."
        if buildDistance {
            guard let ceiling else { return start + " On your next run I'll remind you to ease back if you start too quickly." }
            return start + " On your next run I'll remind you to ease back if you start quicker than \(CoachFormat.pace(ceiling, unit: unit))."
        }
        let practise = segment ? "Let's practise an even tempo:" : "Let's practise an even pace:"
        switch outcome {
        case .struggled?: return start + " \(practise) your next \(next) repeats this one, with a pace band to hold from the start."
        case .failed?: return start + " \(practise) your next \(next) is shorter and a little slower, with a pace band to hold from the start."
        default: return start + " \(practise) your next \(next) has a pace band to hold from the start."
        }
    }

    /// FB-4a without a fast start, on runs that aren't easy or long: the advice points to volume, never pace work.
    static func plainFade(change: Double, next: String, outcome: SessionOutcome?) -> String {
        let text = "Your pace dropped \(percent(change)) in the second half without a fast start. That usually means endurance is still building; steady weeks and gradual long runs build it."
        switch outcome {
        case .struggled?: return text + " Your next \(next) repeats this one, with a pace band to hold from the start."
        case .failed?: return text + " Your next \(next) is shorter and a little slower."
        default: return text
        }
    }

    /// FB-4b with a target and no marked fade after it.
    static func fastStart(_ fraction: Double) -> String {
        "You started \(percent(fraction)) faster than target. Start at target pace; an even pace usually finishes stronger."
    }

    /// FB-4d, the largest flag first.
    static func reps(_ flags: RepFlags) -> Insight? {
        if let first = flags.firstFast, first >= (flags.lastSlow ?? 0) {
            return Insight(.pacing, "Even reps: start at target. Your first rep was \(percent(first)) quicker than planned.", size: first)
        }
        if let last = flags.lastSlow {
            return Insight(.pacing, "Even reps: start at target. Your last rep was \(percent(last)) slower than your first.", size: last)
        }
        if flags.outside >= 2 {
            return Insight(.pacing, "Even reps: start at target. Several reps were more than 3% off it.", size: RunAnalysis.repBand)
        }
        return nil
    }

    /// FB-4e.
    static let recoveries = "Jog or walk the recoveries; they let you hold pace on the next rep."

    /// FB-4f once. A hard outcome adds the next session's change.
    static func tempoFade(outcome: SessionOutcome?) -> String {
        let text = "Aim for the same pace start to finish; the first minutes should feel controlled."
        switch outcome {
        case .struggled?: return text + " Your next tempo run repeats this one, with a pace band to hold from the start."
        case .failed?: return text + " Your next tempo run is shorter and a little slower."
        default: return text
        }
    }

    /// FB-4h, with FB-5's fuel line when nothing was logged. A drop under 10% means the RPE test failed.
    static func durability(_ drop: Double, unfuelled: Bool) -> String {
        let text = drop >= RunAnalysis.durabilityLine
            ? "Your pace dropped \(percent(drop)) over the last third. That's common while endurance builds."
            : "That long run finished harder than planned. That's common while endurance builds."
        return unfuelled ? text + " " + fuelText : text
    }

    /// FB-4i: the only message that says "the wall" is about the marathon, and it never uses the word for others.
    static func wall(_ slowdown: Double, unit: DistanceUnit) -> String {
        "After \(CoachFormat.distance(20_000, unit: unit)) your pace dropped \(percent(slowdown)). Starting at plan pace and fuelling steadily from early on usually help."
    }

    /// FB-4k.
    static let decoupling = "Your heart rate drifted up for the same pace late in the run. That's common on longer runs, especially in warm weather or if you didn't drink, and it usually shrinks as endurance builds."

    /// PZ-12's threshold and VO2max signals, as notes on the run only.
    static let overThresholdBand = "Your heart rate was above your tempo range for most of the work. Next time, ease off a little when it climbs."
    static let belowThresholdBand = "Your heart rate stayed below your tempo range at this effort, a sign the pace is getting easier."
    static let underNinetyPercent = "Your heart rate stayed under 90% of your max on these reps, a sign the pace is getting easier."

    /// PZ-13.
    static let heartRatePatchy = "Your heart-rate readings have been patchy, so I'm coaching by pace and effort. A chest strap gives steadier readings if you want heart-rate guidance."
    static let heartRateSettling = "After a break, heart rate often runs higher at the same pace. I'll coach by effort for two weeks while it settles."

    /// FB-4n.
    static func cadence(target: Int, baseline: Int) -> String {
        "Try slightly shorter, quicker steps: about \(target) steps per minute instead of your usual \(baseline)."
    }

    // MARK: Repeated patterns

    /// The "because" for a repeated fade's plan changes (FB-4a, FB-6): "Because your pace faded in 2 of your last 3
    /// race-pace runs, your next one is split into 5-minute repeats and Sunday's long run starts at easy pace."
    static func repeatedFade(runs: String, split: Bool, sameKind: Bool, longRunStart: Bool, holdLongRun: Bool, longRunDay: Weekday?) -> String? {
        var parts: [String] = []
        if split {
            parts.append(sameKind ? "your next one is split into 5-minute repeats" : "your next tempo or race-pace run is split into 5-minute repeats")
        }
        let longRun = longRunDay.map { "\($0.name)'s long run" } ?? "your next long run"
        if longRunStart { parts.append("\(longRun) starts at easy pace") }
        if holdLongRun { parts.append("\(longRun) stays at its current length") }
        guard let last = parts.last else { return nil }
        let joined = parts.count == 1 ? last : parts.dropLast().joined(separator: ", ") + " and " + last
        return "Because your pace faded in 2 of your last 3 \(runs), \(joined)."
    }

    /// FB-4f repeated: the next tempo becomes reps, or 3% easier when it's already reps.
    static func repeatedTempoFade(alreadyReps: Bool) -> String {
        alreadyReps
            ? "Because your pace faded in 2 of your last 3 tempo runs, your next tempo run is 3% easier."
            : "Because your pace faded in 2 of your last 3 tempo runs, your next tempo run is split into repeats."
    }
}
