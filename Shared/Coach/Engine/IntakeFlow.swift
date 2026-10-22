//
//  IntakeFlow.swift
//  Wind Run
//

import Foundation

/// One intake question: the terms (IN-20), then the questions in the order Intake lists them (goal, running so far,
/// running now, schedule and extras). Setup groups them into `SetupScreen`s; follow-ups appear once the answer that
/// opens them is given.
///
/// Age, "Why do you run?", the 30-minute question, other training, the level and race details are no longer asked at
/// setup (Brendon, 2026-10-22): age isn't used, the coach words things for health, the 30-minute answer comes from
/// the running answers, other training from Apple Health's workouts, the level is picked on the goal check, and race
/// details are asked 2 weeks out (EV-9). Their cases stay so saved answers still decode.
enum IntakeStep: String, Codable, CaseIterable, CodingKeyRepresentable {
    /// IN-20: shown only when no acceptance of the terms is stored.
    case terms
    /// IN-1.
    case goal
    case finished
    /// HL-26's question for a first marathon.
    case finishedHalf
    /// IN-2, IN-16 (optional), IN-19 (optional).
    case age
    case body
    case reasons
    /// IN-4.
    case runs30
    case nonStop
    case dailyFunction
    case briskWalk
    /// IN-5, IN-6, IN-7.
    case history
    case lastFourWeeks
    case beforeBreak
    case easyPace
    /// IN-10.
    case otherTraining
    /// IN-12, IN-13, IN-17 (optional), IN-18 (optional; events only).
    case schedule
    case level
    case heartRate
    case eventDetails

    /// The question the coach shows.
    var title: String {
        switch self {
        case .terms: "Wind Run's terms"
        case .goal: "What do you want to work toward?"
        case .finished: "Have you finished this distance?"
        case .finishedHalf: "Have you finished a half marathon, or run 16 km (10 mi) or more in one go?"
        case .age: "How old are you?"
        case .runs30: "Can you run for 30 minutes without stopping?"
        case .nonStop: "Longest you can run without stopping?"
        case .dailyFunction: "Day to day, how easily do you walk and climb stairs?"
        case .briskWalk: "Can you walk briskly for 30 minutes?"
        case .history: "How long have you run at least twice a week?"
        case .lastFourWeeks: "In the last 4 weeks:"
        case .beforeBreak: "Before your break:"
        case .easyPace: "What's your usual easy pace?"
        case .otherTraining: "What other training do you do?"
        case .schedule: "Which days can you run?"
        case .level: "How fast do you want to build?"
        case .body: "Height and weight? (optional)"
        case .heartRate: "Want to use heart rate?"
        case .eventDetails: "Race details? (optional)"
        case .reasons: "Why do you run? (optional)"
        }
    }

    /// Required steps must be answered or skipped with their cautious default (IN-21); a follow-up is required
    /// whenever it is shown. Optional ones can wait.
    var isRequired: Bool {
        switch self {
        case .body, .heartRate, .eventDetails, .reasons: false
        default: true
        }
    }

    /// The terms, goal and run days have no safe default, so they can't be skipped (IN-20, IN-21). The level
    /// is preset, so one tap answers it.
    var canSkip: Bool {
        switch self {
        case .terms, .goal, .age, .schedule, .level: false
        default: true
        }
    }

    /// What the screen says when the runner skips a required step (IN-21).
    var skipText: String? {
        switch self {
        case .nonStop, .briskWalk:
            "If you skip this, I'll assume you can't run a minute non-stop yet, so you'll start with brisk walks. You can answer it any time."
        case .dailyFunction:
            "If you skip this, I'll assume walking and stairs aren't easy for you, so you'll start with brisk walks. You can answer it any time."
        case .history:
            "If you skip this, I'll assume you're new to running, so your plan starts gently. You can answer it any time."
        case .lastFourWeeks, .beforeBreak:
            "If you skip this, I'll assume you haven't run lately, so you'll ease back in from the start. You can answer it any time."
        case .finished:
            "If you skip this, I'll assume it's your first time at this distance, so your plan is a little more cautious. You can answer it any time."
        case .finishedHalf:
            "If you skip this, I'll assume you haven't, so your marathon waits until you've run a half or 16 km (10 mi). You can answer it any time."
        case .easyPace:
            "If you skip this, your runs go by effort until I've seen 3 easy runs. You can answer it any time."
        case .otherTraining:
            "If you skip this, I'll assume your other training already uses part of your recovery, so your plan builds a bit slower. You can answer it any time."
        default:
            nil
        }
    }
}

extension CoachIntake {
    /// The steps that apply to these answers, in order. Follow-ups appear only once their answer opens them.
    var steps: [IntakeStep] {
        var steps: [IntakeStep] = []
        if termsAcceptedAt == nil { steps.append(.terms) }
        steps += [.goal, .history, .finished]
        if goal.distance == .marathon, finished == .no { steps.append(.finishedHalf) }
        steps.append(.lastFourWeeks)
        if let weeks = breakBeganWeeksAgo, weeks >= 4 { steps.append(.beforeBreak) }
        // IN-4 without its first question: the 30-minute answer comes from the running answers. Only a runner whose
        // answers don't show it is asked how long they can run, and how easily they walk.
        if !canRun30Minutes {
            if inferredNonStop == nil { steps.append(.nonStop) }
            steps.append(.dailyFunction)
            if (longestNonStop ?? inferredNonStop) == .underOneMinute { steps.append(.briskWalk) }
        }
        steps += [.easyPace, .schedule, .body]
        return steps
    }

    /// Whether a step has an answer. Steps whose answer isn't kept here (heart rate stays on the device) count
    /// once the app marks them answered.
    func isAnswered(_ step: IntakeStep) -> Bool {
        switch step {
        case .terms: termsAcceptedAt != nil
        case .goal: true
        case .finished: finished != nil
        case .finishedHalf: finishedHalf != nil
        case .age: birthYear != nil
        case .runs30: runs30Minutes != nil
        case .nonStop: longestNonStop != nil
        case .dailyFunction: dailyFunction != nil
        case .briskWalk: walksBriskly30 != nil
        case .history: history != nil
        case .lastFourWeeks: lastFourWeeks != nil
        case .beforeBreak: beforeBreak != nil
        case .easyPace: easyPace != nil || race != nil
        case .otherTraining: otherTraining != nil
        case .schedule: !runDays.isEmpty
        case .level: level != nil
        case .body: heightCentimeters != nil && weightKilograms != nil
        case .eventDetails: eventDetails != nil
        case .heartRate: answerDates[step] != nil
        case .reasons: !reasons.isEmpty || answerDates[step] != nil
        }
    }

    /// Answered, or skipped with its cautious default (IN-21).
    func isDone(_ step: IntakeStep) -> Bool {
        isAnswered(step) || (step.canSkip && skippedSteps.contains(step))
    }

    /// The next screen to show, or nil when every step is done.
    var nextStep: IntakeStep? {
        steps.first { !isDone($0) }
    }

    /// The first required step that is neither answered nor skipped, or nil when intake can build a plan.
    var nextRequiredStep: IntakeStep? {
        steps.first { $0.isRequired && !isDone($0) }
    }

    /// IN-20: no plan without the terms, and every required step answered or skipped.
    var canBuildPlan: Bool {
        termsAcceptedAt != nil && nextRequiredStep == nil
    }

    /// Records an answer's date (IN-22 re-asks from it) and clears a skip.
    mutating func markAnswered(_ step: IntakeStep, at date: Date) {
        answerDates[step] = date
        skippedSteps.remove(step)
    }

    /// Records a skip; steps with no safe default can't be skipped (IN-21).
    mutating func markSkipped(_ step: IntakeStep, at date: Date) {
        guard step.canSkip else { return }
        skippedSteps.insert(step)
        answerDates[step] = date
    }

    /// When a step was last answered or skipped: intake's own date when the app recorded none.
    func answerDate(_ step: IntakeStep) -> Date {
        answerDates[step] ?? answeredAt
    }
}

extension IntakeStep {
    /// How long a saved answer holds for the next plan, in days; nil holds until the runner changes it. Recent running
    /// and pace change from month to month (IN-6, IN-7), and run days are asked again every 12 weeks (IN-22).
    var keepsForDays: Int? {
        switch self {
        case .lastFourWeeks, .beforeBreak, .runs30, .nonStop, .dailyFunction, .briskWalk, .easyPace: 28
        case .schedule: 84
        default: nil
        }
    }
}

/// One setup screen: related questions asked together. Brendon's rules for every coach mode: setup asks at most 7
/// questions (5 ship), never asks again what a saved answer, Apple Health or logged runs already say, and keeps every
/// answer for the next plan. Heart rate isn't asked: it's on until the runner turns it off in Plan settings.
enum SetupScreen: String, CaseIterable, Hashable {
    case terms
    case goal
    case runningSoFar
    case runningLately
    case schedule
    case body

    /// Setup never shows more questions than this (Brendon, 2026-10-22). The terms screen isn't a question: it's
    /// normally accepted at first install.
    static let maxQuestions = 5

    var title: String {
        switch self {
        case .terms: IntakeStep.terms.title
        case .goal: IntakeStep.goal.title
        case .runningSoFar: "Your running so far"
        case .runningLately: "Your running lately"
        case .schedule: IntakeStep.schedule.title
        case .body: IntakeStep.body.title
        }
    }

    /// The screen a step is asked on. Steps setup no longer asks have none.
    init?(_ step: IntakeStep) {
        switch step {
        case .terms: self = .terms
        case .goal: self = .goal
        case .history, .finished, .finishedHalf: self = .runningSoFar
        case .lastFourWeeks, .beforeBreak, .runs30, .nonStop, .dailyFunction, .briskWalk, .easyPace: self = .runningLately
        case .schedule: self = .schedule
        case .body: self = .body
        case .age, .reasons, .otherTraining, .level, .heartRate, .eventDetails: return nil
        }
    }

    /// The steps this screen asks for these answers, follow-ups included once they're opened.
    func steps(for intake: CoachIntake) -> [IntakeStep] {
        intake.steps.filter { SetupScreen($0) == self }
    }
}

extension CoachIntake {
    /// Whether an answer still holds, so setup doesn't ask it again: answered or skipped on a recorded date and, for
    /// answers that change, recently enough.
    func holds(_ step: IntakeStep, now: Date, calendar: Calendar) -> Bool {
        guard isDone(step), let date = answerDates[step] else { return false }
        guard let days = step.keepsForDays else { return true }
        return IntakeFlow.days(from: date, to: now, calendar: calendar) < days
    }

    /// The screens setup has to show for these answers: the goal always, and every screen with a step whose answer
    /// doesn't hold.
    func pendingScreens(now: Date, calendar: Calendar) -> Set<SetupScreen> {
        var screens: Set<SetupScreen> = [.goal]
        for step in steps where !holds(step, now: now, calendar: calendar) {
            if let screen = SetupScreen(step) { screens.insert(screen) }
        }
        return screens
    }
}

/// IN-22: what intake asks again during a plan.
enum IntakeFlow {
    /// Run days and times every 12 weeks, and the whole intake after a gap over 56 days. Event details 14 days out are
    /// asked by the event review (EV-9, IN-18). Other training isn't asked any more: it comes from Apple Health.
    static func reasks(_ state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> [CoachQuestion] {
        guard state.status.isActive || state.status.isPaused else { return [] }
        let intake = state.intake
        if let gap = state.gap, gap.daysOff > 56,
           intake.answeredAt < (calendar.date(byAdding: .day, value: -gap.daysOff, to: gap.startedAt) ?? gap.startedAt) {
            return [.redoIntake]
        }
        var questions: [CoachQuestion] = []
        if days(from: intake.answerDate(.schedule), to: now, calendar: calendar) >= 84 {
            questions.append(.reask(.schedule))
        }
        return questions
    }

    static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}
