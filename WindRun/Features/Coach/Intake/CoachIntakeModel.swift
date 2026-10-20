//
//  CoachIntakeModel.swift
//  Wind Run
//

import Foundation
import Observation

/// The answers being collected during coach setup, and where the runner is in the questions.
///
/// The engine decides which questions apply (`CoachEngine.intakeSteps`); this keeps the answers,
/// the current step, and the settings that stay on the device rather than in the intake.
@Observable
final class CoachIntakeModel {
    var intake: CoachIntake
    /// The question on screen, as an index into `steps`.
    var position = 0
    var heartRate: HeartRateSettings

    let now: Date
    let calendar: Calendar

    init(flavor: CoachGoal, unit: DistanceUnit, now: Date = .now, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
        let distance: RaceDistance = flavor == .event ? .tenK : .fiveK
        var intake = CoachIntake(goal: GoalChoice(flavor: flavor, distance: distance), answeredAt: now)
        intake.distanceUnit = unit
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
            return goal.targetSeconds != nil || goal.strongFirstTime
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
