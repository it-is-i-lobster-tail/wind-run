//
//  PlanTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

@MainActor
struct IntervalPlanTests {
    @Test func timelineWritesOutRepeats() {
        let container = WindRunSchema.makeContainer(inMemory: true)
        let plan = IntervalPlan.classicFiveByThree()
        container.mainContext.insert(plan)

        let timeline = plan.timeline
        // Warm up, 5 × (work, recovery), cool down.
        #expect(timeline.count == 12)
        #expect(timeline.first?.kind == .warmup)
        #expect(timeline.last?.kind == .cooldown)
        #expect(timeline.filter { $0.kind == .work }.count == 5)
        #expect(timeline[3] == PlannedIntervalStep(kind: .work, goal: .time(180), repetition: 2, repeatCount: 5))
        #expect(plan.timedDuration == 45 * 60)
    }

    @Test func goalRoundTripsThroughStorage() {
        let step = IntervalStep(kind: .work, goal: .distance(meters: 400))
        #expect(step.goal == .distance(meters: 400))
        step.goal = .open
        #expect(step.goal == .open)
    }

    @Test func repeatCountIsClamped() {
        #expect(IntervalBlock(repeatCount: 0).repeatCount == 1)
        #expect(IntervalBlock(repeatCount: 500).repeatCount == IntervalBlock.repeatRange.upperBound)
    }
}

@MainActor
struct CoachPlanTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func eventPlanNeedsARaceAhead() {
        let noDate = CoachPlan(goal: .event, startDate: start, baselineWeeklyMeters: 15_000, runsPerWeek: 3, eventDistance: .halfMarathon)
        #expect(!noDate.isValid)

        let tooSoon = CoachPlan(goal: .event, startDate: start, baselineWeeklyMeters: 15_000, runsPerWeek: 3, eventDate: start.addingTimeInterval(3 * 86_400), eventDistance: .tenK)
        #expect(!tooSoon.isValid)

        let twelveWeeks = CoachPlan(goal: .event, startDate: start, baselineWeeklyMeters: 15_000, runsPerWeek: 3, eventDate: start.addingTimeInterval(84 * 86_400), eventDistance: .halfMarathon)
        #expect(twelveWeeks.isValid)
        #expect(twelveWeeks.weeksUntilEvent == 12)
    }

    @Test func runsPerWeekIsClamped() {
        let plan = CoachPlan(goal: .buildDistance, baselineWeeklyMeters: 10_000, runsPerWeek: 9)
        #expect(plan.runsPerWeek == CoachPlan.runsPerWeekRange.upperBound)
    }

    @Test func workoutsLandOnTheirDay() {
        let container = WindRunSchema.makeContainer(inMemory: true)
        let plan = CoachPlan(goal: .buildDistance, startDate: start, baselineWeeklyMeters: 10_000, runsPerWeek: 3)
        container.mainContext.insert(plan)
        plan.addWeek()
        let week = plan.addWeek()
        let long = week.addWorkout(.long, dayOffset: 5, targetMeters: 8_000)
        week.addWorkout(.easy, dayOffset: 1, targetMeters: 4_000)

        #expect(week.order == 1)
        #expect(week.plannedMeters == 12_000)
        #expect(long.scheduledDate == Calendar.current.date(byAdding: .day, value: 12, to: start))
    }

    @Test func onlyOneActivePlanIsReturned() {
        let first = CoachPlan(goal: .speedWork, baselineWeeklyMeters: 0, runsPerWeek: 3)
        let second = CoachPlan(goal: .buildDistance, baselineWeeklyMeters: 0, runsPerWeek: 3)
        second.stop()

        #expect([second, first].active === first)
    }
}

@MainActor
struct RunFormatTests {
    @Test func durations() {
        #expect(RunFormat.duration(59) == "0:59")
        #expect(RunFormat.duration(32 * 60 + 10) == "32:10")
        #expect(RunFormat.duration(3_723) == "1:02:03")
    }

    @Test func paceConvertsToMiles() {
        #expect(RunFormat.pace(300, unit: .kilometers) == "5:00 /km")
        #expect(RunFormat.pace(300, unit: .miles) == "8:02 /mi")
        #expect(RunFormat.pace(nil, unit: .kilometers) == "–:–– /km")
    }
}
