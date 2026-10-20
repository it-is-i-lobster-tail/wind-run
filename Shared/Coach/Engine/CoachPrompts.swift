//
//  CoachPrompts.swift
//  Wind Run
//

import Foundation

/// The words on a question card: what the coach asks, a line under it where one helps, and the answers to tap.
struct CoachPrompt: Codable, Hashable {
    /// One answer: its words, an optional line under them, and the answer it stands for.
    struct Choice: Codable, Hashable {
        var label: String
        var detail: String?
        /// The name of the answer's case (`MissedRunsReason.wornOut` is "wornOut"), or "yes" / "no" for a
        /// yes-or-no answer.
        var value: String

        init(_ label: String, detail: String? = nil, value: String) {
            self.label = label
            self.detail = detail
            self.value = value
        }
    }

    var text: String
    var detail: String?
    /// Empty when the card opens a screen of its own (the check-ins, the recovery plan).
    var choices: [Choice]
    /// More questions on the same card, each optional: the heat question under the pre-session check (AD-16).
    var also: [CoachPrompt]

    init(_ text: String, detail: String? = nil, choices: [Choice] = [], also: [CoachPrompt] = []) {
        self.text = text
        self.detail = detail
        self.choices = choices
        self.also = also
    }
}

/// The coach's wording for each question, from the rules (Check-ins AD-1 to AD-3 and RB-8, AD-9, AD-10, AD-12,
/// AD-18, RB-7, CL-4, Reporting an injury, FB-3, EV-9, BD-1g, SW-7c, EF-5, IN-22, RC-9).
enum CoachPrompts {
    static func prompt(for question: CoachQuestion, state: CoachState, calendar: Calendar) -> CoachPrompt {
        switch question {
        case .runCheckIn:
            return CoachPrompt("How did that run feel?", detail: "A few taps help me set your next runs. Skip anything you like.")
        case .whatHappened:
            return CoachPrompt("That run got tough. What happened?", choices: WhatHappened.allCases.map { choice($0.name, $0) })
        case .morningCheck:
            return CoachPrompt("How are you feeling this morning?", detail: "Rate your tiredness and soreness from 1 to 7, where 4 is normal. It's optional.")
        case .weeklyCheckIn:
            return CoachPrompt("How was your week?", detail: "About 30 seconds. Skip anything you like.")
        case .readiness(let sessionID):
            let name = session(sessionID, in: state).map { sessionName($0.kind) } ?? "session"
            return CoachPrompt("Ready for today's \(name)?", choices: ReadinessAnswer.allCases.map { choice($0.name, $0) }, also: [heat])

        case .medicalClearance:
            return CoachPrompt(
                "Are you medically cleared to keep training?",
                detail: "Your plan is paused until you answer.",
                choices: ClearanceAnswer.allCases.map { choice($0.name, $0) }
            )
        case .recoveryPlan:
            return recoveryPlanOffer(state)
        case .injuryCheck(let reportID):
            let report = injury(reportID, in: state)
            let area = report?.areaName ?? "your injury"
            if report?.level == .mild {
                return CoachPrompt("How's \(area)?", choices: MildCheckAnswer.allCases.map { choice($0.name, $0) })
            }
            return CoachPrompt("How's \(area) now?", choices: RecoveryCheckAnswer.allCases.map { choice($0.name, $0) })
        case .readyToRun:
            return CoachPrompt(
                "Ready to run again?",
                detail: "A good sign: everyday walking has felt normal for about 5 days.",
                choices: [CoachPrompt.Choice("Yes", value: "yes"), CoachPrompt.Choice("Not yet", value: "no")]
            )
        case .mildFollowUp(let reportID):
            let area = injury(reportID, in: state)?.areaName ?? "your injury"
            return CoachPrompt(
                "\(area.firstUppercased) has been clear for a week. Still clear?",
                choices: [choice("Yes", FollowUpAnswer.stillClear), choice("It's back", FollowUpAnswer.itsBack)]
            )
        case .suggestIntense:
            return CoachPrompt(
                "Sounds like it isn't settling. Want to switch to Intense?",
                detail: "That gives it a short break and a gentle rebuild.",
                choices: [choice("Switch to Intense", InjurySuggestionChoice.switchToIntense), choice("Keep going", InjurySuggestionChoice.keepGoing)]
            )
        case .suggestRepeatOrPause:
            return CoachPrompt(
                "Sorry it's worse. Want to repeat this week, or pause your plan until you're ready?",
                choices: [
                    choice("Repeat this week", InjurySuggestionChoice.repeatWeek),
                    choice("Pause my plan", InjurySuggestionChoice.pausePlan),
                    choice("Keep going", InjurySuggestionChoice.keepGoing),
                ]
            )
        case .suggestRepeat:
            return CoachPrompt(
                "No change for two weeks. Want to repeat this week before we build further?",
                choices: [choice("Repeat this week", InjurySuggestionChoice.repeatWeek), choice("Keep going", InjurySuggestionChoice.keepGoing)]
            )
        case .reportInjury:
            return CoachPrompt(
                "How bad is it?",
                detail: "Muscle soreness that starts hours after a new, longer, faster or downhill run and fades over 1-3 days is normal, not an injury.",
                choices: InjuryLevel.allCases.map { CoachPrompt.Choice($0.name, detail: $0.detail, value: "\($0)") }
            )

        case .illnessKind:
            return CoachPrompt(
                "Just a head cold (above the neck, no fever), or a fever or anything below the neck (chest, stomach, aches all over)?",
                choices: IllnessKind.allCases.map { choice($0.name, $0) }
            )
        case .illnessGone:
            return CoachPrompt("Has your head cold gone?", choices: HeadColdCheck.allCases.map { choice($0.name, $0) })
        case .stillNormal:
            return CoachPrompt("Still feeling normal after yesterday's run?", choices: yesNo)

        case .missedRuns:
            return CoachPrompt(
                "A couple of your runs didn't happen. What's going on?",
                detail: "No need to make them up.",
                choices: reasons([(.busy, "Busy"), (.travel, "Travel"), (.sick, "Sick"), (.injured, "Injured"), (.wornOut, "Worn out"), (.other, "Other")])
            )
        case .dipCheck:
            return CoachPrompt(
                "Your running dipped this week. Everything OK?",
                choices: reasons([(.busy, "Busy"), (.sick, "Ill"), (.injured, "Injured"), (.wornOut, "Tired"), (.fine, "Fine")])
            )
        case .rampDrops:
            return CoachPrompt(
                "That's two weeks in a row I've eased your plan back. What's going on?",
                choices: reasons([(.sick, "Ill"), (.injured, "Injured"), (.wornOut, "Worn out"), (.busy, "Busy")])
            )
        case .moveKeySession(let sessionID, let toDay):
            guard let (week, session) = located(sessionID, in: state) else {
                return CoachPrompt("Move your missed session to another day?", choices: moveChoices)
            }
            let from = Weekday(of: week.start, calendar: calendar).adding(session.movedFrom ?? session.dayOffset)
            let to = Weekday(of: week.start, calendar: calendar).adding(toDay)
            return CoachPrompt("Move \(from.name)'s \(sessionName(session.kind)) to \(to.name)?", choices: moveChoices)
        case .levelUp(let level):
            return CoachPrompt(
                "You've rated 4 weeks as too easy. Want to move up to \(level.name) from your next cycle?",
                detail: "Your safety limits stay the same.",
                choices: [CoachPrompt.Choice("Move up", value: "yes"), CoachPrompt.Choice("Stay at \(state.level.name)", value: "no")]
            )
        case .lighterWeek:
            return CoachPrompt(
                "Sounds like a heavy stretch. Want next week a quarter lighter, or keep it as planned? Your call.",
                choices: [CoachPrompt.Choice("A quarter lighter", value: "yes"), CoachPrompt.Choice("Keep it as planned", value: "no")]
            )
        case .ladderEasierRestart:
            return CoachPrompt(
                "Missed a couple? No problem. Want to pick up one step easier?",
                choices: [CoachPrompt.Choice("One step easier", value: "yes"), CoachPrompt.Choice("Keep my step", value: "no")]
            )
        case .ladderIdleRestart:
            return CoachPrompt(
                "Ready to go again? Tap to restart one step back.",
                choices: [CoachPrompt.Choice("Restart one step back", value: "yes"), CoachPrompt.Choice("Not now", value: "no")]
            )
        case .ladderRestartWhere:
            return CoachPrompt(
                "Welcome back. Where would you like to restart?",
                detail: "Pick a step that feels comfortable. Nothing to catch up.",
                choices: LadderCoach.restartOptions(state).enumerated().map { CoachPrompt.Choice($1.name, value: "\($0)") }
            )

        case .didYouRace:
            return CoachPrompt(
                "Did you race?",
                detail: "I don't see a run on race day.",
                choices: [
                    CoachPrompt.Choice("Yes, recorded elsewhere", value: "recordedElsewhere"),
                    CoachPrompt.Choice("Didn't start", value: "didNotStart"),
                    CoachPrompt.Choice("Race moved", value: "raceMoved"),
                ]
            )
        case .nextGoal:
            return nextGoal(state)
        case .raceIllness:
            return CoachPrompt(
                "Your race is coming up. Have you been ill?",
                choices: [
                    CoachPrompt.Choice("Ill now", value: "now"),
                    CoachPrompt.Choice("Ill in the last 2 weeks", value: "recently"),
                    CoachPrompt.Choice("No", value: "no"),
                ]
            )
        case .raceHeat(let daysOut):
            let when = daysOut == 1 ? "tomorrow" : "on race day"
            return CoachPrompt("How hot will it be \(when)?", choices: heat.choices)
        case .eventDetails:
            return CoachPrompt("Your race is 2 weeks away. Are its details still right?", detail: "The date, the course and any cut-off time.")
        case .reask(let step):
            return CoachPrompt("Has anything changed? \(step.title)", detail: "Your answer keeps your plan fitting your life.")
        case .redoIntake:
            return CoachPrompt("Welcome back. A few questions so your plan starts from where you are now.")
        case .goalAlternatives:
            return CoachPrompt(
                "Your goal is still a big stretch. Want to look at other options?",
                choices: [CoachPrompt.Choice("Show options", value: "yes"), CoachPrompt.Choice("Keep my goal", value: "no")]
            )

        case .extraRunSlot, .swapRunDay, .walkBreaks, .benchmarkSooner, .cadenceCue:
            let review = RunReviewer.prompt(for: question, state: state, calendar: calendar)
            return CoachPrompt(
                review?.text ?? "",
                detail: review?.detail,
                choices: [CoachPrompt.Choice(review?.yes ?? "Yes", value: "yes"), CoachPrompt.Choice(review?.no ?? "No", value: "no")]
            )
        }
    }

    /// AD-12: "Ready" during an illness pause.
    static let illnessReady = CoachPrompt(
        "Have you felt back to normal for 2 full days?",
        choices: [CoachPrompt.Choice("Yes", value: "yes"), CoachPrompt.Choice("Not yet", value: "no")]
    )

    /// AD-16 with no weather source: asked with the pre-session check and when an outdoor easy run is opened.
    /// Values are `HeatAnswer` case names; a skipped answer leaves the heat unknown.
    static let heat = CoachPrompt(
        "How hot will it be when you run?",
        choices: HeatAnswer.allCases.map { answer in
            CoachPrompt.Choice(
                answer.name,
                detail: answer == .veryHot ? "About 32 °C (90 °F) or more, or 28 °C (82 °F) or more and humid" : nil,
                value: answer.rawValue
            )
        }
    )

    // MARK: Pieces

    static let yesNo = [CoachPrompt.Choice("Yes", value: "yes"), CoachPrompt.Choice("No", value: "no")]
    static let moveChoices = [CoachPrompt.Choice("Move it", value: "yes"), CoachPrompt.Choice("Skip it this week", value: "no")]

    static func choice<Answer>(_ label: String, _ answer: Answer) -> CoachPrompt.Choice {
        CoachPrompt.Choice(label, value: "\(answer)")
    }

    static func reasons(_ items: [(MissedRunsReason, String)]) -> [CoachPrompt.Choice] {
        items.map { CoachPrompt.Choice($0.1, value: $0.0.rawValue) }
    }

    /// "long run", "tempo run", "test": a session's name inside a sentence.
    static func sessionName(_ kind: SessionKind) -> String {
        kind == .race ? "race" : kind.name.lowercased()
    }

    static func session(_ id: UUID, in state: CoachState) -> PlannedSession? {
        located(id, in: state)?.1
    }

    static func located(_ id: UUID, in state: CoachState) -> (PlannedWeek, PlannedSession)? {
        for record in state.weeks {
            if let session = record.plan.sessions.first(where: { $0.id == id }) { return (record.plan, session) }
        }
        return nil
    }

    static func injury(_ id: UUID, in state: CoachState) -> InjuryReport? {
        state.injuries.first { $0.id == id }
    }

    static func weeks(_ count: Int) -> String {
        count == 1 ? "1 week" : "\(count) weeks"
    }

    /// AD-13b's offer, worded from the report's plan or the default; ladder and walk-stage runners restart
    /// two steps back.
    static func recoveryPlanOffer(_ state: CoachState) -> CoachPrompt {
        let detail = "Change anything that doesn't suit you, and make it faster or slower whenever you like."
        if let ladder = state.ladder, ladder.form != .done {
            return CoachPrompt("Here's a recovery plan: 1 week off running, then we restart two steps back.", detail: detail)
        }
        let plan = RecoveryPlanSettings.standard
        let share = plan.reducedShare == 0.5 ? "half" : "\(Int((plan.reducedShare * 100).rounded()))% of"
        var text = "Here's a recovery plan: \(weeks(plan.restWeeks)) off running, \(weeks(plan.reducedWeeks)) at \(share) your usual distance"
        if let step = plan.rampStep, step > 0 {
            let ramp = Int((((1 - plan.reducedShare) / step) - 0.000_1).rounded(.up))
            text += ", then \(weeks(ramp)) building back."
        } else {
            text += ", then back to your usual weeks."
        }
        return CoachPrompt(text, detail: detail)
    }

    /// What next, by flavor (BD-1g, SW-7c, EV-9).
    static func nextGoal(_ state: CoachState) -> CoachPrompt {
        switch state.goal.flavor {
        case .buildDistance:
            return CoachPrompt(
                "That's your \(state.goal.distance.name). What next?",
                choices: [
                    CoachPrompt.Choice("Keep this distance", value: "maintain"),
                    CoachPrompt.Choice("The next distance", value: "nextRung"),
                    CoachPrompt.Choice("Get faster", detail: "Speed Work", value: "speedWork"),
                ]
            )
        case .speedWork:
            return CoachPrompt(
                "You did it. What next?",
                choices: [
                    CoachPrompt.Choice("A new goal at this distance", value: "newGoal"),
                    CoachPrompt.Choice("A new distance", value: "newDistance"),
                    CoachPrompt.Choice("An event", value: "event"),
                    CoachPrompt.Choice("Keep this fitness", detail: "One quality session a week", value: "maintain"),
                ]
            )
        case .event:
            return CoachPrompt(
                "What's next?",
                choices: [
                    CoachPrompt.Choice("Keep my fitness", value: "maintain"),
                    CoachPrompt.Choice("Another event", value: "event"),
                    CoachPrompt.Choice("Get faster", detail: "Speed Work", value: "speedWork"),
                ]
            )
        }
    }
}

private extension String {
    var firstUppercased: String { prefix(1).uppercased() + dropFirst() }
}
