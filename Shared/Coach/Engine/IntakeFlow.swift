//
//  IntakeFlow.swift
//  Wind Run
//

import Foundation

/// One intake screen: the terms (IN-20), then the questions in the order Intake lists them (goal, about you,
/// running now, recovery, schedule, level and extras). The app asks the steps `CoachIntake.steps` returns, in
/// order; follow-ups appear once the answer that opens them is given.
enum IntakeStep: String, Codable, CaseIterable, CodingKeyRepresentable {
    /// IN-20: shown only when no acceptance of the terms is stored.
    case terms
    /// IN-1.
    case goal
    case finished
    /// HL-26's question for a first marathon. No longer asked; kept so saved answers still decode.
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

    /// Whether the screen says "Optional." under the question. A yes/no question already says it.
    var showsOptionalNote: Bool { !isRequired && self != .heartRate }

    /// The terms, age, goal and run days have no safe default, so they can't be skipped (IN-20, IN-21). The level
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
        case .runs30, .nonStop, .briskWalk:
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
        steps += [.goal, .finished]
        // HL-26's "finished a half?" is no longer asked: a first marathon needs no half first.
        steps += [.age, .body, .reasons, .runs30]
        if runs30Minutes == false {
            steps.append(.nonStop)
            steps.append(.dailyFunction)
            if longestNonStop == .underOneMinute { steps.append(.briskWalk) }
        }
        steps.append(.history)
        steps.append(.lastFourWeeks)
        if let weeks = breakBeganWeeksAgo, weeks >= 4 { steps.append(.beforeBreak) }
        steps += [.easyPace, .otherTraining, .schedule, .level, .heartRate]
        if goal.flavor == .event { steps.append(.eventDetails) }
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

/// IN-22: what intake asks again during a plan.
enum IntakeFlow {
    /// Other training and the job question every 4 weeks, run days and times every 12 weeks, and the whole intake
    /// after a gap over 56 days. Event details 14 days out are asked by the event review (EV-9, IN-18).
    static func reasks(_ state: CoachState, runs: [LoggedRun], now: Date, calendar: Calendar) -> [CoachQuestion] {
        guard state.status.isActive || state.status.isPaused else { return [] }
        let intake = state.intake
        if let gap = state.gap, gap.daysOff > 56,
           intake.answeredAt < (calendar.date(byAdding: .day, value: -gap.daysOff, to: gap.startedAt) ?? gap.startedAt) {
            return [.redoIntake]
        }
        var questions: [CoachQuestion] = []
        if days(from: intake.answerDate(.otherTraining), to: now, calendar: calendar) >= 28 {
            questions.append(.reask(.otherTraining))
        }
        if days(from: intake.answerDate(.schedule), to: now, calendar: calendar) >= 84 {
            questions.append(.reask(.schedule))
        }
        return questions
    }

    static func days(from start: Date, to end: Date, calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}
