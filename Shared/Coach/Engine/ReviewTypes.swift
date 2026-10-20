//
//  ReviewTypes.swift
//  Wind Run
//

import Foundation

/// What a coach message is about, so the app can place it.
enum NoteTopic: String, Codable {
    /// The plan and its weeks.
    case plan
    /// A hard limit that shaped the plan (HL-1, HL-2, HL-14).
    case limit
    /// The weekly outcome (AD-5).
    case outcome
    case injury
    case illness
    case milestone
    /// Static safety text (AD-19, AD-19b).
    case safety
    /// A run insight (FB-1).
    case insight
    case pace
    case level
    case event
}

/// One sentence from the coach. Every change shows one "because" sentence naming its input.
struct CoachNote: Codable, Hashable {
    var topic: NoteTopic
    var text: String

    init(_ topic: NoteTopic, _ text: String) {
        self.topic = topic
        self.text = text
    }
}

/// A signal family (AD-4). A family is negative only when its rule fires on real answers.
enum SignalFamily: String, Codable, CaseIterable {
    case effort
    case wellness
    case user
    case injury
    case heartRate
}

/// The weekly outcome (AD-5), first matching row wins.
enum WeekOutcome: String, Codable {
    case pause
    case recoveryPlan
    case stepBack
    case ease
    case hold
    case progress
    /// Completion under 40% or ≥8 days without a qualifying run: the AD-10 ramp instead of the table.
    case returnRamp
}

/// The input behind an outcome, for the "because" sentence.
enum OutcomeReason: String, Codable {
    case severeInjury
    case intenseNotCleared
    case intenseCleared
    case mildInjury
    case mildCleared
    case illness
    case headCold
    case heatIllness
    case fatigueLevel1
    case fatigueLevel2
    case twoFamilies
    case tooHardAfterEase
    case effortTwoWeeks
    case effort
    case tooHard
    case heartRate
    case wellness
    case lowCompletion
    case hardButOK
    case lifeStress
    case loadJump
    case busy
    case fewRatedRuns
    case missedCheckIns
    case calibration
    case weekCut
    case overWeeklyCap
    case spike
    case extraRuns
    case gap
    case progress

    /// The {because} part: "because {phrase}".
    var phrase: String {
        switch self {
        case .severeInjury: "you need a break from running for your injury"
        case .intenseNotCleared: "you're not cleared to train yet"
        case .intenseCleared: "you're following your recovery plan"
        case .mildInjury: "of your injury"
        case .mildCleared: "your injury just cleared"
        case .illness: "you're ill"
        case .headCold: "of your cold"
        case .heatIllness: "the heat got to you"
        case .fatigueLevel1: "you've needed two lighter weeks and still feel worn down"
        case .fatigueLevel2: "you've been worn down for three weeks"
        case .twoFamilies: "several signs say you need a lighter week"
        case .tooHardAfterEase: "last week still felt too hard"
        case .effortTwoWeeks: "your runs have felt harder than planned two weeks running"
        case .effort: "your runs felt harder than planned"
        case .tooHard: "you rated last week too hard"
        case .heartRate: "your heart rate has been higher than usual"
        case .wellness: "you've felt more worn down than usual"
        case .lowCompletion: "you did less than planned last week"
        case .hardButOK: "last week was hard"
        case .lifeStress: "your week was stressful"
        case .loadJump: "you added a lot of training outside running"
        case .busy: "you're busy"
        case .fewRatedRuns: "I need two rated runs to move you forward"
        case .missedCheckIns: "I haven't had a weekly check-in for two weeks"
        case .calibration: "I'm still checking your starting point"
        case .weekCut: "heat, travel or illness cut last week short"
        case .overWeeklyCap: "your last 7 days went over your weekly limit"
        case .spike: "one run went well past your usual longest"
        case .extraRuns: "extra runs took your week over its limit"
        case .gap: "you've had a break"
        case .progress: "it felt about right"
        }
    }
}

/// The review of a finished plan week (AD-4, AD-5).
struct WeekReview: Codable, Hashable {
    var weekIndex: Int
    /// Done ÷ planned, in the plan's unit; extra runs count up to the plan.
    var completion: Double
    var doneVolume: Double
    var ratedRuns: Int
    var negativeFamilies: [SignalFamily]
    var outcome: WeekOutcome
    var reason: OutcomeReason
    var note: CoachNote
}

/// Session outcome for a Q (FB-4g). Internal labels are never shown.
enum SessionOutcome: String, Codable {
    case failed
    case struggled
    case evenAndOnTarget
    case completed
}

/// How a run relates to the plan (AD-8).
enum RunMatch: Codable, Hashable {
    /// It completed this planned session.
    case planned(sessionID: UUID)
    /// Not matched: counted toward the week, W4max and spike detection, never blamed.
    case extra
}

/// The data gate's verdict (FB-2).
enum DataGate: String, Codable {
    case passes
    /// Counts as volume only: poor GPS, a bad-data mark, a hilly run, run-walk without step data.
    case volumeOnly
    /// Under 500 m or over 100 km: dropped.
    case dropped
}

/// A one-time milestone (BD-1e).
enum Milestone: Codable, Hashable {
    case nonStopMinutes(Int)
    case firstDistance(RaceDistance)
    case longestRun(meters: Double)
}

/// A question the coach asks, shown as a card. Each has an answer call on the engine.
enum CoachQuestion: Codable, Hashable {
    /// AD-1, about 30 min after a run.
    case runCheckIn(runID: UUID)
    /// FB-3: "That run got tough. What happened?"
    case whatHappened(runID: UUID)
    /// AD-2, optional, the morning after a long run, a new longest, a Q or a spike.
    case morningCheck(runID: UUID)
    /// AD-3 at each plan week's end.
    case weeklyCheckIn(weekIndex: Int)
    /// RB-8 before a Q, long run, test or race.
    case readiness(sessionID: UUID)
    /// AD-13b: "Are you medically cleared to keep training?"
    case medicalClearance(reportID: UUID)
    /// AD-13b: the recovery plan screen, with its default.
    case recoveryPlan(reportID: UUID)
    /// The weekly injury check (Mild AD-13a, Intense AD-13b, Severe return AD-14c).
    case injuryCheck(reportID: UUID)
    /// AD-13c: "Ready to run again?"
    case readyToRun(reportID: UUID)
    /// AD-14a: "Your {area} has been clear for a week. Still clear?"
    case mildFollowUp(reportID: UUID)
    /// AD-13a: "Sounds like it isn't settling. Want to switch to Intense?"
    case suggestIntense(reportID: UUID)
    /// AD-13b: Worse: "Want to repeat this week, or pause your plan until you're ready?"
    case suggestRepeatOrPause(reportID: UUID)
    /// AD-13b: Same twice in the ramp: "Want to repeat this week before we build further?"
    case suggestRepeat(reportID: UUID)
    /// AD-12's question.
    case illnessKind(episodeID: UUID)
    /// AD-12 head cold, every 3 days: "Has it gone?"
    case illnessGone(episodeID: UUID)
    /// AD-12 stage 2's next-day check.
    case stillNormal(episodeID: UUID)
    /// AD-9: two planned runs missed, or 7 days without a qualifying run.
    case missedRuns
    /// AD-9: "Your running dipped this week. Everything OK?"
    case dipCheck
    /// AD-10: two ramp drops in a row.
    case rampDrops
    /// AD-9: "Move Sunday's long run to Tuesday?"
    case moveKeySession(sessionID: UUID, toDay: Int)
    /// CL-4: after 4 "too easy" weeks, the next allowed level, once.
    case levelUp(CommitmentLevel)
    /// RB-7: life stress worse 2 weeks running: a quarter lighter next week, never forced.
    case lighterWeek
    /// EV-9: race day passed with no run logged.
    case didYouRace
    /// BD-1g, SW-7c, EV-9: what next.
    case nextGoal
    /// "Something hurt": open Report injury, with where it came from (AD-1, FB-3).
    case reportInjury(origin: InjuryOrigin, runID: UUID?)
    /// AD-18: idle 2 weeks on the walk stage or the ladder: "Ready to go again? Tap to restart one step back."
    /// Answered with `CoachAnswer.ladderEasierRestart`.
    case ladderIdleRestart
    /// AD-18: back after more than 28 days: "Where would you like to restart?", from `LadderCoach.restartOptions`.
    case ladderRestartWhere
    /// AD-18: two ladder sessions missed in a row, or idle 2 weeks: "Want to pick up one step easier?"
    case ladderEasierRestart
}

/// What the coach makes of one saved run.
struct RunReview: Codable, Hashable {
    var runID: UUID
    var match: RunMatch
    var gate: DataGate
    /// At most 2, the first positive (FB-1).
    var insights: [CoachNote]
    var milestones: [Milestone]
    var outcome: SessionOutcome?
    var questions: [CoachQuestion]
    /// Plan changes the run caused (AD-8 trims, a Q made easy), each with its "because".
    var notes: [CoachNote]
    /// Shown once after any FB-3 trigger (AD-19).
    var showsSafetyLine: Bool

    init(runID: UUID, match: RunMatch, gate: DataGate = .passes, insights: [CoachNote] = [], milestones: [Milestone] = [], outcome: SessionOutcome? = nil, questions: [CoachQuestion] = [], notes: [CoachNote] = [], showsSafetyLine: Bool = false) {
        self.runID = runID
        self.match = match
        self.gate = gate
        self.insights = insights
        self.milestones = milestones
        self.outcome = outcome
        self.questions = questions
        self.notes = notes
        self.showsSafetyLine = showsSafetyLine
    }
}

/// Static safety text (AD-19, AD-19b). Never a question, a gate or a pause.
enum SafetyText {
    static let safetyLine = "Wind Run is a training app, not a medical device. Stop and get medical help if you have chest pain or pressure, faint, or feel unusually short of breath or unwell. In an emergency, call your local emergency number."
    static let stopLine = "Stop if you feel chest pain or pressure, faint, dizzy or very short of breath. If pain builds or makes you limp, stop and walk home, then tap Report injury."
    static let heatLines = "Feeling dizzy, sick or chilly in the heat? Stop, get into shade, cool your skin and sip only if thirsty. Not better in 30 minutes, or confused: call emergency services. Bloated or swollen hands after drinking a lot? Stop drinking and get help."
    static let postRace = "In the next few days, if you feel confused or very unwell, or your urine turns dark like cola, get medical help."
    static let painkillers = "Skip ibuprofen and similar painkillers around the race; they can strain your kidneys when you're working hard. If you need pain relief, ask a pharmacist."
    static let weatherCheck = "Thunder, smoky or very polluted air, or bitter wind chill? Run indoors or at another time."
}
