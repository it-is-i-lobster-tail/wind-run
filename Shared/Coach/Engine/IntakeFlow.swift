//
//  IntakeFlow.swift
//  Wind Run
//

import Foundation

/// One intake screen (IN-1 to IN-19). The app asks the steps `CoachIntake.steps` returns, in order;
/// follow-ups appear once the answer that opens them is given.
enum IntakeStep: String, Codable, CaseIterable {
    case goal
    case finished
    case age
    case runs30
    case nonStop
    case dailyFunction
    case briskWalk
    case history
    case lastFourWeeks
    case beforeBreak
    case easyPace
    case otherTraining
    case schedule
    case level
    case body
    case heartRate
    case reasons

    /// The question the coach shows.
    var title: String {
        switch self {
        case .goal: "What do you want to work toward?"
        case .finished: "Have you finished this distance?"
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
        case .reasons: "Why do you run? (optional)"
        }
    }

    /// Required steps must be answered or skipped with their cautious default (IN-21); optional ones can wait.
    var isRequired: Bool {
        switch self {
        case .body, .heartRate, .reasons: false
        default: true
        }
    }

    /// Age, goal and run days have no safe default, so they can't be skipped (IN-21).
    var canSkip: Bool {
        switch self {
        case .goal, .age, .schedule, .level: false
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
        var steps: [IntakeStep] = [.goal, .finished, .age, .runs30]
        if runs30Minutes == false {
            steps.append(.nonStop)
            steps.append(.dailyFunction)
            if longestNonStop == .underOneMinute { steps.append(.briskWalk) }
        }
        steps.append(.history)
        steps.append(.lastFourWeeks)
        if let weeks = breakBeganWeeksAgo, weeks >= 4 { steps.append(.beforeBreak) }
        steps += [.easyPace, .otherTraining, .schedule, .level, .body, .heartRate, .reasons]
        return steps
    }

    /// Whether a step has an answer. Optional steps count as answered once the runner moved past them.
    func isAnswered(_ step: IntakeStep) -> Bool {
        switch step {
        case .goal: true
        case .finished: finished != nil
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
        case .heartRate, .reasons: false
        }
    }

    /// The first required step without an answer, or nil when intake can build a plan.
    var nextRequiredStep: IntakeStep? {
        steps.first { $0.isRequired && !$0.canSkip && !isAnswered($0) }
    }
}
