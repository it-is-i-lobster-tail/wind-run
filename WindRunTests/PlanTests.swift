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

    @Test func eventPlanCountsWeeksToRaceDay() {
        let plan = CoachPlan(flavor: "event", startDate: start, eventDate: start.addingTimeInterval(84 * 86_400), goalDistanceMeters: 21_097.5)
        #expect(plan.weeksUntilEvent == 12)
        #expect(CoachPlan(flavor: "buildDistance", startDate: start).weeksUntilEvent == nil)
    }

    @Test func workoutsLandOnTheirDay() {
        let container = WindRunSchema.makeContainer(inMemory: true)
        let plan = CoachPlan(flavor: "buildDistance", startDate: start)
        container.mainContext.insert(plan)
        plan.addWeek()
        let week = plan.addWeek()
        let long = week.addWorkout(kind: "long", dayOffset: 5)
        week.addWorkout(kind: "easy", dayOffset: 1)

        #expect(week.order == 1)
        #expect(week.workouts.map(\.kind) == ["easy", "long"])
        #expect(long.scheduledDate == Calendar.current.date(byAdding: .day, value: 12, to: start))
    }

    @Test func sessionsAreFoundByTheirEngineID() {
        let container = WindRunSchema.makeContainer(inMemory: true)
        let plan = CoachPlan(flavor: "speedWork", startDate: start)
        container.mainContext.insert(plan)
        let week = plan.addWeek(order: 0)
        let id = UUID()
        let workout = week.addWorkout(sessionID: id, kind: "intervals", dayOffset: 2)

        #expect(week.workout(withSessionID: id) === workout)
        #expect(week.workout(withSessionID: UUID()) == nil)
    }

    @Test func targetsRoundTrip() {
        let workout = CoachWorkout(kind: "easy", dayOffset: 0)
        let target = CoachWorkoutTarget(title: "Easy run", detail: "Conversational", notes: "", meters: nil, seconds: 1_800, pace: 390...420, effort: 2...3, runWalk: nil, isKeySession: false, isQuality: false)
        workout.update(kind: "easy", dayOffset: 9, date: nil, order: 0, status: "planned", target: target)

        #expect(workout.target == target)
        #expect(workout.dayOffset == 6)
    }

    @Test func onlyOneCurrentPlanIsReturned() {
        let first = CoachPlan(flavor: "speedWork")
        let second = CoachPlan(flavor: "buildDistance")
        second.stop()

        #expect([second, first].active === first)
    }

    @Test func aPausedPlanIsStillTheCurrentOne() {
        let plan = CoachPlan(flavor: "event")
        plan.updateSummary(status: .paused, startDate: start, eventDate: nil, goalDistanceMeters: nil)
        #expect([plan].active === plan)
    }
}

@MainActor
struct RunFormatTests {
    @Test func durations() {
        #expect(RunFormat.duration(59) == "0:59")
        #expect(RunFormat.duration(32 * 60 + 10) == "32:10")
        #expect(RunFormat.duration(3_723) == "1:02:03")
    }

    @Test func distanceIsCutDownSoARaceIsntShownDoneEarly() {
        #expect(RunFormat.distance(4_995, unit: .kilometers) == "4.99 km")
        #expect(RunFormat.distance(4_999.9, unit: .kilometers) == "4.99 km")
        #expect(RunFormat.distance(5_000, unit: .kilometers) == "5.00 km")
        #expect(RunFormat.distance(1_609, unit: .miles) == "0.99 mi")
        #expect(RunFormat.distance(402.336 * 4, unit: .miles) == "1.00 mi")
        // What's left rounds up, so it doesn't read 0.00 before it's done; a plan's distance rounds to the nearest.
        #expect(RunFormat.distance(4, unit: .kilometers, rounding: .up) == "0.01 km")
        #expect(RunFormat.distance(21_097.5, unit: .kilometers, rounding: .toNearestOrAwayFromZero) == "21.10 km")
    }

    @Test func runRowsSayTheDayAndTheDateOnceItsMoreThanAWeekAgo() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 17, hour: 12))!
        #expect(RunRow.when(now.addingTimeInterval(-3_600), now: now, calendar: calendar).hasPrefix("Today, "))
        #expect(RunRow.when(now.addingTimeInterval(-86_400), now: now, calendar: calendar).hasPrefix("Yesterday, "))
        let monthAgo = calendar.date(byAdding: .day, value: -30, to: now)!
        let shown = RunRow.when(monthAgo, now: now, calendar: calendar)
        #expect(shown.hasPrefix(monthAgo.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())))
    }

    @Test func runRowsReadAsWordsToVoiceOver() {
        let spoken = RunRow.spoken(date: .now, meters: 5_020, seconds: 32 * 60 + 10, pace: 384.5, unit: .kilometers)
        #expect(spoken.hasSuffix("5.02 kilometers in 32 minutes 10 seconds, 6 minutes 24 seconds per kilometer."))
    }

    @Test func paceConvertsToMiles() {
        #expect(RunFormat.pace(300, unit: .kilometers) == "5:00 /km")
        #expect(RunFormat.pace(300, unit: .miles) == "8:02 /mi")
        #expect(RunFormat.pace(nil, unit: .kilometers) == "–:–– /km")
    }
}
