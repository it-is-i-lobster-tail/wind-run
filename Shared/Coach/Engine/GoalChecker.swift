//
//  GoalChecker.swift
//  Wind Run
//

import Foundation

/// The realism check: can the goal be reached safely, by when, and what to say (RC-1 to RC-9).
enum GoalChecker {
    /// RC-2's Green long run and volume for a goal, in meters (the 5K's long run also has a 30-min form).
    static func greenTargets(for goal: GoalChoice) -> (longRun: Double, volume: Double) {
        switch goal.distance {
        case .mile: (1_609.344, 0)
        case .fiveK: (5_000, 0)
        case .tenK: (10_000, 15_000)
        case .halfMarathon: goal.hasTimeGoal ? (21_000, 32_000) : (16_000, 25_000)
        case .marathon: (30_000, 40_000)
        }
    }

    static func check(
        _ goal: GoalChoice,
        intake: CoachIntake,
        assessment: RunnerAssessment,
        paces: TrainingPaces,
        level: CommitmentLevel,
        injuries: [InjuryReport] = [],
        now: Date,
        calendar: Calendar
    ) -> GoalCheck {
        // RC-1: refusals.
        if assessment.habitMode, goal.flavor != .buildDistance {
            return refusal(.fewRunDays, message: "A plan for this goal needs at least 2 run days a week. One run a week still counts: when two fit your week, I'll build a full plan.")
        }
        if goal.flavor == .event, assessment.overlays.earlyWindow, goal.distance > .tenK {
            return refusal(.earlyWindow, message: "In your first weeks of regular running, events go up to 10K. Let's train for a 10K first; your \(goal.distance.name.lowercased()) is saved for later.")
        }
        if goal.distance == .marathon, intake.finished != .yesRecently {
            let longest = intake.lastFourWeeks?.longest?.meters ?? 0
            let finishedHalf = false
            if assessment.monthsRunning < 12 || (!finishedHalf && longest < 16_000) {
                let months = Int(assessment.monthsRunning.rounded())
                return refusal(.firstMarathon, message: "A first marathon needs a year of running and a half marathon (or a 16 km (10 mi) run) first. You're at \(months) months. Let's train for a half: your marathon is saved.")
            }
        }
        if injuries.contains(where: { !$0.status.isClosed && $0.level == .severe }) {
            return refusal(.severeInjury, message: "Your plan is paused for your injury. Once you're ready to run again, I'll check this goal.")
        }

        // RC-4: the paths in the plan's unit.
        let unit = assessment.start.volumeUnit
        let pace = paces.easyPace ?? RunnerAssessor.fallbackPace
        let targets = greenTargets(for: goal)
        var longTarget = unit == .time ? targets.longRun / 1_000 * pace : targets.longRun
        if goal.distance == .marathon { longTarget = min(longTarget, unit == .time ? 210 * 60 : 35_000) }
        let volumeTarget = unit == .time ? targets.volume / 1_000 * pace : targets.volume
        let start = assessment.start.planningLongest.amount(in: unit)
        let cycle = CycleWeek.cycle(for: level, stepBackEveryThird: assessment.recoveryTier.stepsBackEveryThird, twoWeekHold: false)
        let longWeeks = Progression.longRunPathWeeks(newLongest: Progression.newLongestWeeks(from: start, to: longTarget), on: cycle)
        let volumeWeeks = Progression.volumePathWeeks(
            loading: Progression.loadingWeeks(from: assessment.start.v0, to: volumeTarget, rate: level.loadingRate),
            on: cycle
        )
        let calibration = assessment.start.calibrates ? Progression.calibrationWeeks : 0
        let speedBlock = goal.hasTimeGoal && goal.flavor != .buildDistance ? Progression.speedBlockWeeks : 0
        let taper = goal.flavor == .event ? Progression.taperWeeks(for: goal.distance) : 0
        let build = max(longWeeks, volumeWeeks)
        let earliest = build + calibration + speedBlock + taper
        let likely = Progression.likelyWeeks(earliest: earliest)
        let buffer = Progression.bufferWeeks(buildWeeks: build + speedBlock, recovery: assessment.recoveryTier)
        let earliestDate = calendar.date(byAdding: .weekOfYear, value: earliest, to: now) ?? now
        let likelyDate = calendar.date(byAdding: .weekOfYear, value: likely, to: now) ?? now

        var status: DistanceStatus = .green
        var verdict: GoalVerdict = .green
        if let eventDate = goal.eventDate {
            let weeks = (calendar.dateComponents([.day], from: now, to: eventDate).day ?? 0) / 7
            if weeks >= earliest + buffer {
                status = .green
            } else if weeks >= earliest {
                status = .amber
            } else {
                status = .red
            }
            verdict = status == .green ? .green : (status == .amber ? .amber : .red)
        }
        let projectedLongest = Progression.projectedLongRun(from: start, weeks: build, on: cycle)
        let feasibility = Feasibility(
            earliestWeeks: earliest,
            likelyWeeks: likely,
            earliestDate: earliestDate,
            likelyDate: likelyDate,
            bufferWeeks: buffer,
            projectedLongest: Load(projectedLongest, in: unit, pace: paces.easyPace),
            projectedVolume: Progression.projectedVolume(from: assessment.start.v0, weeks: build, on: cycle, rate: level.loadingRate),
            longRunStatus: status,
            volumeStatus: status,
            status: status,
            raceToLongest: projectedLongest > 0 ? (unit == .time ? goal.distance.meters / 1_000 * pace : goal.distance.meters) / projectedLongest : 0,
            longRunTimeLimited: false,
            volumeTimeLimited: false
        )
        let forecast = PaceCalculator.forecast(
            goal.distance,
            paces: paces,
            firstTime: assessment.overlays.firstTimer,
            weeklyMeters: Load(assessment.start.v0, in: unit, pace: paces.easyPace).meters,
            age: assessment.age,
            now: now,
            calendar: calendar
        )
        let message: String
        switch verdict {
        case .green:
            message = goal.eventDate == nil
                ? "This fits. At \(level.name) you could be ready in about \(earliest)-\(likely) weeks."
                : "This fits. Your long runs reach \(CoachFormat.distance(targets.longRun, unit: intake.distanceUnit)) by \(CoachFormat.date(earliestDate, calendar: calendar)), with \(buffer) weeks spare for busy or sick weeks."
        case .amber:
            message = "This is doable, but it uses the spare weeks a plan needs for busy or sick weeks."
        case .red, .refused:
            message = "You can run \(CoachFormat.load(assessment.start.planningLongest, in: unit, unit: intake.distanceUnit)) now. A \(goal.distance.shortName) needs long runs of about \(CoachFormat.distance(targets.longRun, unit: intake.distanceUnit)). I add at most 10% to your longest run, one step at a time with easier weeks between, so that takes about \(earliest)-\(likely) weeks at \(level.name)."
        }
        return GoalCheck(
            verdict: verdict,
            refusal: nil,
            feasibility: feasibility,
            forecast: forecast,
            timeGoal: nil,
            alternatives: [],
            savedGoalEarliest: nil,
            plansRunWalk: false,
            cutoffAtRisk: false,
            canInsist: verdict == .red,
            message: message
        )
    }

    static func refusal(_ reason: RefusalReason, message: String) -> GoalCheck {
        GoalCheck(
            verdict: .refused,
            refusal: reason,
            feasibility: nil,
            forecast: nil,
            timeGoal: nil,
            alternatives: [],
            savedGoalEarliest: nil,
            plansRunWalk: false,
            cutoffAtRisk: false,
            canInsist: false,
            message: message
        )
    }
}
