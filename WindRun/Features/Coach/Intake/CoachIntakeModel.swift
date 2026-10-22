//
//  CoachIntakeModel.swift
//  Wind Run
//

import Foundation
import Observation

/// The answers being collected during coach setup, and where the runner is in the questions.
///
/// The engine decides which questions apply (`CoachEngine.intakeSteps`); this keeps the answers,
/// the current step, and the heart-rate settings, which are kept with the app's settings rather than in the intake.
@Observable
final class CoachIntakeModel {
    var intake: CoachIntake
    /// The question on screen, as an index into `steps`.
    var position = 0
    var heartRate: HeartRateSettings

    let now: Date
    let calendar: Calendar

    /// A refused goal the runner set aside by picking one of its alternatives, with its earliest date.
    /// It holds only while the goal is still that alternative; changing the goal by hand drops it.
    private var setAside: (goal: GoalChoice, earliest: Date?, alternative: GoalChoice)?

    var savedGoal: GoalChoice? { setAside?.alternative == intake.goal ? setAside?.goal : nil }
    var savedGoalEarliest: Date? { savedGoal == nil ? nil : setAside?.earliest }

    /// Picks one of a goal check's alternatives. A refused check's goal is kept to come back later.
    func choose(_ alternative: GoalChoice, from check: GoalCheck) {
        if check.verdict == .refused, let refused = check.savedGoal {
            setAside = (refused, check.savedGoalEarliest, alternative)
        } else if let kept = setAside, kept.alternative == intake.goal {
            // Another alternative from the check after it still sets the same goal aside.
            setAside = (kept.goal, kept.earliest, alternative)
        }
        intake.goal = alternative
    }

    init(flavor: CoachGoal, unit: DistanceUnit, now: Date = .now, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        let distance: RaceDistance = flavor == .event ? .tenK : .fiveK
        var intake = CoachIntake(goal: GoalChoice(flavor: flavor, distance: distance), answeredAt: now)
        intake.distanceUnit = unit
        // Coach only opens once the terms are accepted, so the intake starts with that acceptance.
        if let terms = TermsAcceptance.stored(), TermsAcceptance.isCurrent() {
            intake.termsAcceptedAt = terms.date
        }
        if flavor == .event {
            intake.goal.eventDate = calendar.date(byAdding: .weekOfYear, value: 16, to: calendar.startOfDay(for: now))
        }
        self.intake = intake
        self.heartRate = CoachHeartRateStore.load()
    }

    /// The questions that apply to the answers so far, in order.
    var steps: [IntakeStep] { CoachEngine.intakeSteps(intake) }

    var step: IntakeStep {
        let steps = steps
        return steps[min(position, steps.count - 1)]
    }

    var isLastStep: Bool { position >= steps.count - 1 }

    /// Whether the runner can move on: required steps without a safe default need an answer.
    var canContinue: Bool {
        switch step {
        case .goal: goalIsComplete
        // The level list shows the preset from the start; the engine keeps it within the ceiling.
        case .level: true
        default: step.canSkip || intake.isAnswered(step)
        }
    }

    /// Race day can be today or any day up to 52 weeks out (RC-12), never in the past.
    var raceDayRange: ClosedRange<Date> {
        let today = calendar.startOfDay(for: now)
        let latest = calendar.date(byAdding: .weekOfYear, value: 52, to: today) ?? today
        let endOfLatest = calendar.date(byAdding: .second, value: 86_399, to: latest) ?? latest
        return today...endOfLatest
    }

    var goalIsComplete: Bool {
        let goal = intake.goal
        guard goal.flavor.distances.contains(goal.distance) else { return false }
        switch goal.flavor {
        case .event:
            guard let date = goal.eventDate else { return false }
            return raceDayRange.contains(date)
        case .speedWork:
            // The goal time wheels always show a time inside the limits, and moving on stores it.
            return true
        case .buildDistance:
            return true
        }
    }

    func next() {
        settleShownAnswer()
        position = min(position + 1, steps.count - 1)
    }

    /// Keeps the answer a screen showed by default when the runner moves on without changing it.
    func settleShownAnswer() {
        switch step {
        case .level where intake.level == nil:
            intake.level = assessment.levels.preset
        case .goal where intake.goal.flavor == .speedWork && !intake.goal.strongFirstTime:
            let distance = intake.goal.distance
            intake.goal.targetSeconds = distance.speedWorkTarget(intake.goal.targetSeconds ?? Double(distance.speedWorkMinutes.lowerBound * 60))
        default:
            break
        }
    }

    func back() {
        position = max(position - 1, 0)
    }

    /// The runner's age, from the birth year. Nil until they pick one: age changes safety rules,
    /// so it's never filled in for them.
    var age: Int? {
        get { intake.age(on: now, calendar: calendar) }
        set { intake.birthYear = newValue.map { calendar.component(.year, from: now) - min(max($0, 18), 100) } }
    }

    /// The runner's level options and starting numbers for the answers so far.
    var assessment: RunnerAssessment {
        CoachEngine.assess(intake, now: now, calendar: calendar)
    }

    /// The level chosen, or the preset for these answers.
    var level: CommitmentLevel {
        intake.level ?? assessment.levels.preset
    }

    func checkGoal() -> GoalCheck {
        CoachEngine.checkGoal(intake.goal, intake: intake, level: level, now: now, calendar: calendar)
    }
}
