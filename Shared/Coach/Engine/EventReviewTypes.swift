//
//  EventReviewTypes.swift
//  Wind Run
//

import Foundation

/// How the race ended (EV-9).
enum RaceOutcome: String, Codable {
    /// 90% of the race distance or more.
    case finished
    /// A race-day run under 90% of the distance: FB-3's question first, then recovery by the distance run.
    case didNotFinish
    /// Including an EF-5 or HL-19 "don't start" and a cancelled race: no recovery, and the plan stops.
    case didNotStart
}

/// "Did you race?" when race day passes with no run matched to the race (EV-9). The prompt's choices carry the
/// case names; "Yes, recorded elsewhere" asks for the distance and time before it is sent.
enum DidYouRaceAnswer: Codable, Hashable {
    /// Recorded elsewhere. 90% of the race distance or more is a finish: with a time, the result becomes a race
    /// anchor (PZ-2: slower paces apply at once, faster ones step in through PZ-7), and EV-9's recovery for the
    /// race distance runs. Under 90% is a DNF: recovery follows the distance run. With no distance it counts as a
    /// finish with no result, and the recovery for the race distance stays.
    case recordedElsewhere(meters: Double?, seconds: Double?)
    /// Didn't start, an EF-5 or HL-19 "don't start", or a cancelled race: no recovery, the plan stops with that
    /// reason, and "What next?" offers a new date, Build Distance or Speed Work maintenance. With a Severe report
    /// open, the goal is also kept until the runner is ready (RC-1, AD-13c).
    case didNotStart
    /// The race moved: the goal check runs again for the new date (RC-10, RC-4) and the event's phases move with
    /// it. A date before today, or one the check refuses, changes nothing and says why.
    case raceMoved(to: Date)
}

/// "What next?" after a reached goal (BD-1g, SW-7c), after the race and its recovery (EV-9), and after a race
/// not started. The prompt's values map to these cases; "A new goal at this distance", "A new distance", "An
/// event" and "Another event" open the goal screens and come back as `newGoal`.
enum NextGoalAnswer: Codable, Hashable {
    /// Keep this distance or fitness at the current distance (`GoalChoice.maintain`): Speed Work maintenance
    /// after Speed Work or a time goal, Build Distance maintenance otherwise. The plan carries on, open-ended.
    case maintain
    /// Build Distance's next rung: a run-walk rung's non-stop version, else the next distance, with its gate
    /// and a new timeline (BD-1g, BD-1c). The marathon is the top rung.
    case nextRung
    /// Speed Work at this distance with no time goal yet; distance comes first until SW-2's entry holds (SW-1b).
    case speedWork
    /// A goal from the goal screens: a time at this distance, a new distance, an event, or the same race on a
    /// new date. RC-1 to RC-9 run again (RC-12a); a refused goal is kept with its earliest date while the
    /// current fitness is maintained.
    case newGoal(GoalChoice)
}

/// EF-5's illness tap at day −14 and on days −5 to −3.
enum RaceIllnessAnswer: String, Codable, CaseIterable {
    case illNow
    /// Ill at any time since day −14, and better now.
    case illSinceFortnight
    case neither

    var name: String {
        switch self {
        case .illNow: "Ill now"
        case .illSinceFortnight: "I've been ill in the last 2 weeks"
        case .neither: "Neither"
        }
    }
}

/// One EF-2 slip trigger, checked at each week end.
enum SlipTrigger: String, Codable, CaseIterable {
    /// Under 80% of planned volume over 4 weeks.
    case volumeShort
    /// 2 build weeks lost (under 50% done, illness or injury).
    case lostBuildWeeks
    /// The projected taper long run over 10% short of Green, or a long-run step 2 weeks late or more.
    case longRunBehind
    /// 2 of the last 3 long runs cut short or rated "too hard".
    case longRunsCut
    /// An injury or illness costing time within 10 weeks of the race.
    case injuryOrIllness
    /// 2 STEP BACKs or more in 6 weeks, or fatigue Level 1 (AD-6b).
    case fatigue
    /// Time goals: under 80% of key sessions in 3 weeks.
    case keySessions
    /// Time goals: 2 Failed or 3 Struggled Q or more in 4 weeks (FB-4g).
    case qualityOutcomes
    /// Time goals: 7 days missed or more in 4 weeks.
    case missedDays
    /// Time goals: the forecast is short of the goal by more than the realistic gain.
    case forecastShort
    /// Marathon: the planned peak is under 60% of the typical peak for the forecast band (at least Goal at risk).
    case lowPeak

    /// The "because" in EF-3's messages.
    var reason: String {
        switch self {
        case .volumeShort: "you've run under 80% of your planned distance over the last 4 weeks"
        case .lostBuildWeeks: "two build weeks were lost"
        case .longRunBehind: "your long runs are behind"
        case .longRunsCut: "two of your last three long runs were cut short or felt too hard"
        case .injuryOrIllness: "an injury or illness cost training time close to the race"
        case .fatigue: "you've needed lighter weeks lately"
        case .keySessions: "you've done under 80% of your key sessions in the last 3 weeks"
        case .qualityOutcomes: "your recent speed sessions have been a struggle"
        case .missedDays: "you've missed 7 or more days of running in the last 4 weeks"
        case .forecastShort: "your forecast is further from the goal than training usually closes"
        case .lowPeak: "your weekly distance is low for that marathon time"
        }
    }
}

/// What one week's re-projection found (EF-1), kept by plan week so a re-review after a late check-in replaces it.
struct EventWeekReport: Codable, Hashable {
    var status: EventStatus
    /// The distance status at taper start (RC-2), from the re-run of RC-4.
    var distanceStatus: DistanceStatus
    var triggers: [SlipTrigger]
    /// Projected P-L30 and 4-week loading volume at taper start, against RC-2's Green targets, in the plan's unit.
    var projectedLongRun: Double
    var targetLongRun: Double
    var projectedVolume: Double
    var targetVolume: Double
    /// Completed weeks (≥80% of planned minutes plus the long run) over the last 8 weeks, or all weeks so far.
    var completedWeeks: Int
    var countedWeeks: Int
    /// EF-1 (d): the forecast with the pro-rata realistic gain and the missed-week range points.
    var forecast: RaceForecast?
    /// The one "because" sentence the weekly card shows.
    var because: String?
}

/// The event forecast and its checks, re-run each week (EF-1 to EF-8), and what happened on race day (EV-9).
struct EventReviewState: Codable, Hashable {
    /// The forecast at the last weekly check.
    var forecast: RaceForecast?
    /// Slip triggers seen so far (EF-2), by plan week.
    var slipWeeks: [Int]
    /// The race was run (EV-9), with its run.
    var raceRunID: UUID?
    /// "Did you race?" was asked after race day passed with no run logged.
    var askedDidYouRace: Bool
    /// Each week's re-projection, by plan week.
    var reports: [Int: EventWeekReport] = [:]
    /// How the race ended (EV-9), and the result kept as the anchor.
    var outcome: RaceOutcome?
    var raceResultID: UUID?
    /// The race distance actually run, for EV-9's recovery row after a DNF.
    var distanceRun: Double?
    /// The plan week the long run was first projected to reach its target, for EF-2's "2 weeks late".
    var plannedLongRunWeek: Int?
    /// EF-3 Finish likely: the comfortable goal, central forecast + 5%, in seconds.
    var comfortableFinish: Double?
    /// The AD-16 race-heat answers (EF-6), by days before the race; the latest counts.
    var heatAnswers: [Int: HeatAnswer] = [:]
    /// EF-5's illness answers, by days before the race.
    var illnessAnswers: [Int: RaceIllnessAnswer] = [:]
    /// RC-9: when the alternatives were last offered to a runner who kept a Red goal.
    var alternativesOfferedAt: Date?
    /// RC-9's 3-weeks-out warning was given.
    var warnedThreeWeeksOut: Bool = false
    /// Weeks in a row with no fatigue signal, for EF-3's "clears after 3 clean weeks".
    var cleanWeeks: Int = 0
    /// The latest time-goal check (RC-6), recomputed after each test or race (SW-7a) and each week in events.
    var timeGoal: TimeGoalCheck?

    init() {
        slipWeeks = []
        askedDidYouRace = false
    }

    /// The newest week's report.
    var latestReport: EventWeekReport? {
        reports.max { $0.key < $1.key }?.value
    }
}
