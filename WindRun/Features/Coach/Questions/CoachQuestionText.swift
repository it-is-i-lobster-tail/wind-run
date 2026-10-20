//
//  CoachQuestionText.swift
//  Wind Run
//

import Foundation

/// How each of the coach's questions reads.
///
/// TODO: the engine will word its own questions; switch to it when it does. Until then this
/// follows the rules document's wording.
enum CoachQuestionText {
    static func prompt(for question: CoachQuestion, state: CoachState?, calendar: Calendar = .current) -> String {
        switch question {
        case .runCheckIn: "How did your run feel?"
        case .whatHappened: "That run got tough. What happened?"
        case .morningCheck: "How do you feel this morning?"
        case .weeklyCheckIn: "How was your week?"
        case .readiness(let sessionID):
            "Ready for today's \(sessionName(sessionID, in: state).lowercased())?"
        case .medicalClearance: "Are you medically cleared to keep training?"
        case .recoveryPlan: "Set up your recovery plan."
        case .injuryCheck(let reportID):
            report(reportID, in: state)?.level == .mild
                ? "How's \(areaName(reportID, in: state))?"
                : "How's \(areaName(reportID, in: state)) now?"
        case .readyToRun: "Ready to run again?"
        case .mildFollowUp(let reportID): "It's been a week since \(areaName(reportID, in: state)) cleared. Still clear?"
        case .suggestIntense(let reportID): "\(areaName(reportID, in: state).capitalizedFirst) isn't settling. Move it to Intense, so the plan eases off more?"
        case .suggestRepeatOrPause: "Your recovery isn't moving forward. Repeat this week, or pause the plan?"
        case .suggestRepeat: "Repeat this recovery week before moving on?"
        case .illnessKind: IllnessKind.question
        case .illnessGone: "Has your cold gone?"
        case .stillNormal: "Still feeling normal after yesterday's run?"
        case .missedRuns: "You missed a few runs. What got in the way?"
        case .dipCheck: "Your running has dipped. Everything OK?"
        case .rampDrops: "The last two easing-back weeks came up short. What's going on?"
        case .moveKeySession(let sessionID, let day):
            "Move your \(sessionName(sessionID, in: state).lowercased()) to \(dayName(day, sessionID: sessionID, in: state, calendar: calendar))?"
        case .levelUp(let level): "Your runs have felt easy. Move up to \(level.name)?"
        case .lighterWeek: "Your weeks have been stressful. Want next week a quarter lighter?"
        case .ladderEasierRestart: "Want to pick up one step easier?"
        case .didYouRace: "Race day has passed. Did you race?"
        case .nextGoal: "What's next?"
        case .reportInjury: "Something hurt? Report it so the plan can work around it."
        }
    }

    private static func report(_ id: UUID, in state: CoachState?) -> InjuryReport? {
        state?.injuries.first { $0.id == id }
    }

    private static func areaName(_ id: UUID, in state: CoachState?) -> String {
        report(id, in: state)?.areaName ?? "your injury"
    }

    private static func session(_ id: UUID, in state: CoachState?) -> (PlannedSession, PlannedWeek)? {
        guard let state else { return nil }
        for record in state.weeks.reversed() {
            if let session = record.plan.sessions.first(where: { $0.id == id }) {
                return (session, record.plan)
            }
        }
        return nil
    }

    private static func sessionName(_ id: UUID, in state: CoachState?) -> String {
        session(id, in: state)?.0.kind.name ?? "session"
    }

    private static func dayName(_ day: Int, sessionID: UUID, in state: CoachState?, calendar: Calendar) -> String {
        guard let week = session(sessionID, in: state)?.1,
              let date = calendar.date(byAdding: .day, value: day, to: week.start)
        else { return "another day" }
        return date.formatted(.dateTime.weekday(.wide))
    }
}

extension String {
    /// The string with its first letter capitalized.
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }
}
