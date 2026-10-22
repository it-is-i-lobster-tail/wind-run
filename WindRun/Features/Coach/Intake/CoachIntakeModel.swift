//
//  CoachIntakeModel.swift
//  Wind Run
//

import Foundation
import Observation

/// The answers being collected during coach setup, and which screen the runner is on.
///
/// The engine decides which questions apply (`CoachIntake.steps`) and groups them into screens (`SetupScreen`).
/// Setup starts from the answers saved by earlier setups, fills in what Apple Health and logged runs say, and shows
/// only the screens whose answers don't hold yet: never more than `SetupScreen.maxQuestions`.
@Observable
final class CoachIntakeModel {
    var intake: CoachIntake
    /// The screen on show.
    private(set) var screen: SetupScreen
    var heartRate: HeartRateSettings

    let now: Date
    let calendar: Calendar

    /// Every answer so far, to keep for the next plan.
    private(set) var saved: SavedCoachAnswers?
    /// Logged runs and Health workouts, kept to fill "Have you finished this distance?" in when the goal changes.
    private var workouts: [PastWorkout] = []
    /// The screens this setup shows. A screen the runner has seen stays; one whose answers come in from Health
    /// before the runner gets to it drops out.
    private var shown: Set<SetupScreen>
    private var visited: Set<SetupScreen> = []
    /// Screens asked again whatever the saved answers say: the running screens after 12 weeks away from the app.
    private let asksAgain: Set<SetupScreen>

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

    init(
        flavor: CoachGoal,
        unit: DistanceUnit,
        saved: SavedCoachAnswers? = nil,
        backAfterLongBreak: Bool = AppOpens.backAfterLongBreak(),
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        self.now = now
        self.calendar = calendar
        self.saved = saved
        var intake = saved?.newIntake(flavor: flavor, unit: unit, now: now, calendar: calendar)
            ?? CoachIntake(goal: CoachIntake.defaultGoal(flavor: flavor, distance: CoachIntake.defaultDistance(for: flavor), now: now, calendar: calendar), answeredAt: now)
        intake.distanceUnit = unit
        // Coach only opens once the terms are accepted, so the intake starts with that acceptance.
        if let terms = TermsAcceptance.stored(), TermsAcceptance.isCurrent() {
            intake.termsAcceptedAt = terms.date
        }
        // Other training comes from Apple Health; until it's read, none.
        if intake.otherTraining == nil { intake.otherTraining = [] }
        self.intake = intake
        // Heart rate isn't asked at setup: it's on unless the runner turned it off in Plan settings.
        self.heartRate = CoachHeartRateStore.load()
        // Back after more than 12 weeks away, a new plan asks the running screens again, filled in (Brendon,
        // 2026-10-22). A first setup asks them anyway.
        asksAgain = backAfterLongBreak && saved != nil ? [.runningSoFar, .runningLately] : []
        let shown = intake.pendingScreens(now: now, calendar: calendar).union(asksAgain)
        self.shown = shown
        self.screen = shown.contains(.terms) ? .terms : .goal
    }

    /// Fills answers in from Apple Health and logged runs, and drops the screens they answer that the runner hasn't
    /// reached yet.
    func fill(body: HealthBody, workouts: [PastWorkout]) {
        self.workouts = workouts
        IntakePrefill.fill(&intake, body: body, workouts: workouts, now: now, calendar: calendar)
        shown = visited.union([screen]).union(asksAgain).union(intake.pendingScreens(now: now, calendar: calendar))
    }

    /// Whether any runs came in to fill the running questions from.
    var hasRunData: Bool { workouts.contains { $0.isRun } }

    /// The screens setup shows, in order.
    var screens: [SetupScreen] {
        SetupScreen.allCases.filter { shown.contains($0) }
    }

    /// The questions on the screen on show, follow-ups included once they're opened.
    var steps: [IntakeStep] { screen.steps(for: intake) }

    /// The screen's place among the questions, from 1; the terms aren't a question.
    var questionNumber: Int { (questions.firstIndex(of: screen) ?? 0) + 1 }
    var questionCount: Int { questions.count }
    private var questions: [SetupScreen] { screens.filter { $0 != .terms } }

    var isFirstScreen: Bool { screens.first == screen }
    var isLastScreen: Bool { screens.last == screen }

    /// Whether the runner can move on: the goal must be complete, and steps without a safe default need an answer.
    /// Anything else left empty is skipped with its cautious default (IN-21).
    var canContinue: Bool {
        if screen == .goal { return goalIsComplete }
        return steps.allSatisfy { $0.canSkip || intake.isAnswered($0) }
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
        commit()
        if let index = screens.firstIndex(of: screen), index + 1 < screens.count {
            screen = screens[index + 1]
        }
    }

    func back() {
        if let index = screens.firstIndex(of: screen), index > 0 {
            screen = screens[index - 1]
        }
    }

    /// Records the screen's answers, with today's date, and skips what was left empty (IN-21). Leaving the goal
    /// brings in the saved or logged "Have you finished this distance?" for the goal picked, and any screen the new
    /// goal needs.
    func commit() {
        visited.insert(screen)
        if screen == .goal {
            settleGoalTime()
            if let saved {
                saved.applyFinished(to: &intake)
            } else if intake.answerDates[.finished] == nil {
                intake.finished = nil
            }
            IntakePrefill.fillFinished(&intake, runs: workouts.filter(\.isRun).sorted { $0.start < $1.start }, now: now, calendar: calendar)
        } else {
            for step in steps {
                if intake.isAnswered(step) {
                    intake.markAnswered(step, at: now)
                } else {
                    intake.markSkipped(step, at: now)
                }
            }
        }
        shown.formUnion(intake.pendingScreens(now: now, calendar: calendar))
        remember()
    }

    /// Keeps the answers so far for the next setup.
    func remember() {
        if saved == nil {
            saved = SavedCoachAnswers(intake: intake, savedAt: .now)
        } else {
            saved?.remember(intake, at: .now)
        }
    }

    /// Stores the Speed Work goal time the wheels show, in whole minutes inside its distance's limits, including
    /// the first time they show when the runner moves on without turning them.
    func settleGoalTime() {
        guard intake.goal.flavor == .speedWork, !intake.goal.strongFirstTime else { return }
        let distance = intake.goal.distance
        intake.goal.targetSeconds = distance.speedWorkTarget(intake.goal.targetSeconds ?? Double(distance.speedWorkMinutes.lowerBound * 60))
    }

    /// Keeps the level the goal check showed when the runner starts without changing it.
    func settleShownAnswer() {
        if intake.level == nil {
            intake.level = assessment.levels.preset
        }
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
