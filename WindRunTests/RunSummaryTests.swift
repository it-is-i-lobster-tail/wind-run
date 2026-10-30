//
//  RunSummaryTests.swift
//  Wind Run Tests
//

import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import WindRun

/// What the run summary draws: each step's pace, pace over time, the climb, and the route by step.
@MainActor
struct RunSummaryTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    // Each test gets its own instance, so its own store. It has to outlive the models in it.
    private let container = WindRunSchema.makeContainer(inMemory: true)

    private func makeRun() -> Run {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        return run
    }

    /// A fix `meters` north of the start, `seconds` in, at `altitude` meters.
    private func sample(at seconds: TimeInterval, meters: Double, altitude: Double = 0, verticalAccuracy: Double = 0) -> RouteSample {
        RouteSample(
            timestamp: start.addingTimeInterval(seconds),
            latitude: meters / 111_111,
            longitude: 0,
            altitude: altitude,
            horizontalAccuracy: 5,
            verticalAccuracy: verticalAccuracy
        )
    }

    // MARK: Sections

    @Test func theSampleIntervalRunHasEveryStepWithTheWorkNumbered() {
        let run = WindRunSeed.intervalRun(in: container.mainContext, start: start)
        let sections = run.sections
        #expect(sections.map(\.name) == [
            "Warm up", "Work 1", "Recover", "Work 2", "Recover", "Work 3", "Recover", "Work 4", "Recover", "Cool down",
        ])
        #expect(sections.filter(\.isWork).count == 4)
        let slowestWork = sections.filter(\.isWork).compactMap(\.pace).max()!
        let fastestEasy = sections.filter { !$0.isWork }.compactMap(\.pace).min()!
        #expect(slowestWork < fastestEasy)
    }

    @Test func stepsSkippedWhenTheRunEndedEarlyAreLeftOut() {
        let plan = IntervalPlan.classicFiveByThree()
        container.mainContext.insert(plan)
        let run = makeRun()
        run.intervalPlanValue = plan
        var tracker = StepTracker(timeline: plan.timeline)
        _ = tracker.update(elapsed: 600, meters: 1_600)
        _ = tracker.update(elapsed: 780, meters: 2_400)
        tracker.finish(elapsed: 800, meters: 2_450)
        run.saveStepLog(tracker.recorded)

        #expect(run.sections.map(\.name) == ["Warm up", "Work 1", "Recover"])
        #expect(run.sections[1].pace == 180 / 0.8)
    }

    @Test func aRunWithoutStepsHasNoSections() {
        #expect(makeRun().sections.isEmpty)
    }

    // MARK: Pace over time

    @Test func paceFollowsTheRunAndLeavesOutPauses() {
        let run = makeRun()
        // 4:00 a kilometer for five minutes, a two-minute pause, then 6:00 a kilometer.
        for second in stride(from: 0.0, through: 300, by: 5) {
            run.record(sample(at: second, meters: second * 1_000 / 240))
        }
        run.pause(at: start.addingTimeInterval(300))
        run.resume(at: start.addingTimeInterval(420))
        for second in stride(from: 425.0, through: 725, by: 5) {
            run.record(sample(at: second, meters: 1_250 + (second - 420) * 1_000 / 360))
        }
        run.finish(at: start.addingTimeInterval(725))

        let points = run.paceTimeline
        #expect(points.count > 10)
        // Running time, so the pause leaves no hole in the time axis.
        #expect(points.last!.activeTime <= 605)
        let early = points.filter { $0.activeTime < 280 }
        let late = points.filter { $0.activeTime > 340 }
        #expect(early.allSatisfy { abs($0.secondsPerKilometer - 240) < 5 })
        #expect(late.allSatisfy { abs($0.secondsPerKilometer - 360) < 8 })
    }

    @Test func standingStillLeavesAGapInsteadOfASpike() {
        let run = makeRun()
        for second in stride(from: 0.0, through: 120, by: 5) {
            run.record(sample(at: second, meters: second * 1_000 / 300))
        }
        for second in stride(from: 125.0, through: 240, by: 5) {
            run.record(sample(at: second, meters: 400))
        }
        run.finish(at: start.addingTimeInterval(240))
        #expect(run.paceTimeline.allSatisfy { $0.secondsPerKilometer <= 15 * 60 })
        #expect(run.paceTimeline.allSatisfy { $0.activeTime < 160 })
    }

    // MARK: Cadence over time

    @Test func cadenceFollowsTheStepsAndLeavesOutPauses() {
        let run = makeRun()
        // 180 steps a minute for five minutes in 15-second stretches, a two-minute stop, then 160.
        var counts: [StepCountSample] = []
        for second in stride(from: 0.0, to: 300, by: 15) {
            counts.append(StepCountSample(start: start.addingTimeInterval(second), end: start.addingTimeInterval(second + 15), count: 45))
        }
        run.pause(at: start.addingTimeInterval(300))
        run.resume(at: start.addingTimeInterval(420))
        for second in stride(from: 420.0, to: 720, by: 15) {
            counts.append(StepCountSample(start: start.addingTimeInterval(second), end: start.addingTimeInterval(second + 15), count: 40))
        }
        run.saveStepCounts(counts)
        run.finish(at: start.addingTimeInterval(720))

        let points = run.cadenceTimeline
        #expect(points.count > 10)
        // Running time, so the stop leaves no hole in the time axis.
        #expect(points.last!.activeTime == 600)
        #expect(points.filter { $0.activeTime <= 300 }.allSatisfy { abs($0.stepsPerMinute - 180) < 0.5 })
        #expect(points.filter { $0.activeTime >= 330 }.allSatisfy { abs($0.stepsPerMinute - 160) < 0.5 })
    }

    @Test func aRunWithoutStepsHasNoCadence() {
        let run = makeRun()
        run.finish(at: start.addingTimeInterval(600))
        #expect(run.cadenceTimeline.isEmpty)
    }

    @Test func theSampleIntervalRunStopsTwiceAndCountsSteps() {
        let run = WindRunSeed.intervalRun(in: container.mainContext, start: start)
        #expect(run.pausedDuration() == 95)
        #expect(run.cadenceTimeline.count > 100)
        // The light in the warm up doesn't count toward the step's running time.
        #expect(run.sections.first?.seconds == 600)
    }

    // MARK: Elevation

    @Test func climbAndDropIgnoreGPSWobble() {
        let run = makeRun()
        // Up 20 m and down 12 m, with a meter of wobble on top.
        let altitudes: [Double] = [50, 51, 50, 51, 55, 60, 65, 70, 69, 70, 66, 62, 58, 59, 58]
        for (index, altitude) in altitudes.enumerated() {
            run.record(sample(at: Double(index) * 10, meters: Double(index) * 30, altitude: altitude, verticalAccuracy: 3))
        }
        run.finish(at: start.addingTimeInterval(150))
        let elevation = run.elevation
        #expect(elevation?.gain == 20)
        #expect(elevation?.loss == 12)
        #expect(elevation?.profile.count == altitudes.count)
    }

    @Test func routesWithoutGoodAltitudeHaveNoElevation() {
        let run = makeRun()
        run.record(sample(at: 0, meters: 0, altitude: 50))
        run.record(sample(at: 10, meters: 30, altitude: 90))
        #expect(run.elevation == nil)
    }

    // MARK: Route

    @Test func theRouteSplitsWhereWorkStartsAndEndsWithoutGaps() {
        let run = WindRunSeed.intervalRun(in: container.mainContext, start: start)
        let segments = run.routeSegments(sections: run.sections)
        // Warm up, then work and easy in turn: four work stretches, five easy ones.
        #expect(segments.filter(\.isWork).count == 4)
        #expect(segments.filter { !$0.isWork }.count == 5)
        for (earlier, later) in zip(segments, segments.dropFirst()) {
            #expect(earlier.coordinates.last!.latitude == later.coordinates.first!.latitude)
            #expect(earlier.isWork != later.isWork)
        }
    }

    @Test func aPlainRunIsOneStretch() {
        let run = makeRun()
        run.record(sample(at: 0, meters: 0))
        run.record(sample(at: 10, meters: 30))
        run.record(sample(at: 20, meters: 60))
        #expect(run.routeSegments(sections: []).count == 1)
    }

    // MARK: Formatting

    @Test func elevationReadsInMetersOrFeet() {
        #expect(RunFormat.elevation(37, unit: .kilometers, sign: .plus) == "+37 m")
        #expect(RunFormat.elevation(37, unit: .miles, sign: .minus) == "−121 ft")
        #expect(RunFormat.elevation(0, unit: .kilometers) == "0 m")
    }
}
