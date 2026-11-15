//
//  DistanceEstimatorTests.swift
//  Wind Run Tests
//

import CoreLocation
import Foundation
import SwiftData
import Testing
@testable import WindRun

@MainActor
struct DistanceEstimatorTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let container = WindRunSchema.makeContainer(inMemory: true)

    /// A fix `north` and `east` meters from the start, `seconds` in.
    private func fix(
        at seconds: TimeInterval,
        north: Double,
        east: Double = 0,
        speed: Double = -1,
        speedAccuracy: Double = -1,
        accuracy: Double = 5
    ) -> DistanceEstimator.Fix {
        DistanceEstimator.Fix(
            time: start.addingTimeInterval(seconds),
            latitude: north / 111_111,
            longitude: east / 111_111,
            horizontalAccuracy: accuracy,
            speed: speed,
            speedAccuracy: speedAccuracy
        )
    }

    private func measure(_ fixes: [DistanceEstimator.Fix]) -> (meters: Double, track: Double, steps: [DistanceEstimator.Step]) {
        let route = MeasuredRoute(fixes) { _ in true }
        return (route.meters, route.trackMeters, route.steps)
    }

    @Test func aSteadyRunCountsSpeedTimesTime() {
        let fixes = (0...100).map { fix(at: Double($0), north: Double($0) * 3, speed: 3, speedAccuracy: 0.3) }
        let result = measure(fixes)
        #expect(abs(result.meters - 300) < 0.001)
        #expect(result.steps.dropFirst().allSatisfy { $0.counting == .speed })
    }

    @Test func sidewaysWobbleAddsNothing() {
        // Running north at 2.5 m/s while the fixes swing 3 m either side, as GPS does.
        let fixes = (0...200).map { second in
            fix(at: Double(second), north: Double(second) * 2.5, east: second.isMultiple(of: 2) ? 3 : -3, speed: 2.5, speedAccuracy: 0.3)
        }
        let result = measure(fixes)
        #expect(abs(result.meters - 500) < 0.001)
        // Adding up the straight lines, as runs used to, reads far longer.
        #expect(result.track > 650)
    }

    @Test func aSpikeIsFlaggedAndAddsNothingByTheStraightLine() {
        var fixes = (0...20).map { fix(at: Double($0), north: Double($0) * 3) }
        // One fix jumps 40 m east and comes straight back.
        fixes[10] = fix(at: 10, north: 30, east: 40)
        let result = measure(fixes)
        #expect(result.steps[10].isSpike)
        #expect(result.steps[10].meters == 0)
        #expect(!result.steps[11].isSpike)
        #expect(abs(result.meters - 60) < 0.5)
        #expect(result.track > 130)
    }

    @Test func aSpikeWithAGoodSpeedStillCountsItsSpeed() {
        var fixes = (0...20).map { fix(at: Double($0), north: Double($0) * 3, speed: 3, speedAccuracy: 0.3) }
        fixes[10] = fix(at: 10, north: 30, east: 25, speed: 3, speedAccuracy: 0.3)
        let result = measure(fixes)
        #expect(result.steps[10].isSpike)
        #expect(abs(result.meters - 60) < 0.001)
    }

    @Test func standingStillAddsNothing() {
        let fixes = (0...60).map { second in
            fix(at: Double(second), north: second.isMultiple(of: 2) ? 2 : -2, east: second.isMultiple(of: 3) ? 1 : -1, speed: 0.2, speedAccuracy: 0.5)
        }
        #expect(measure(fixes).meters == 0)
    }

    @Test func fixesWithoutSpeedUseTheStraightLine() {
        let fixes = (0...10).map { fix(at: Double($0) * 5, north: Double($0) * 15) }
        let result = measure(fixes)
        #expect(abs(result.meters - result.track) < 0.001)
        #expect(result.steps.dropFirst().allSatisfy { $0.counting == .track })
    }

    @Test func anUnsureSpeedUsesTheStraightLine() {
        let fixes = (0...10).map { fix(at: Double($0), north: Double($0) * 3, speed: 6, speedAccuracy: 4) }
        let result = measure(fixes)
        #expect(abs(result.meters - result.track) < 0.001)
        #expect(result.meters < 35)
    }

    @Test func aLongGapUsesTheStraightLine() {
        // Lost under a bridge for 30 s: the speed at the far end shouldn't stand for the whole gap.
        let fixes = [
            fix(at: 0, north: 0, speed: 3, speedAccuracy: 0.3),
            fix(at: 30, north: 90, speed: 0.5, speedAccuracy: 0.3),
        ]
        let result = measure(fixes)
        #expect(result.steps[1].counting == .track)
        #expect(abs(result.meters - result.track) < 0.001)
    }

    @Test func speedAndTheStraightLineNeverCountTheSameStretchTwice() {
        // Speed counts through a spike; then the speed drops out and the straight line takes over.
        var fixes = (0...10).map { fix(at: Double($0), north: Double($0) * 3, speed: 3, speedAccuracy: 0.3) }
        fixes[10] = fix(at: 10, north: 30, east: 40, speed: 3, speedAccuracy: 0.3)
        fixes.append(fix(at: 11, north: 33))
        let result = measure(fixes)
        #expect(result.steps[11].counting == .track)
        // From the last good fix (27 m at 9 s) the line is 6 m, but speed already counted second 10.
        #expect(abs(result.steps[11].meters - 3) < 0.1)
        #expect(abs(result.meters - 33) < 0.1)
    }

    @Test func pausedFixesAddNothingAndTheNextStretchStartsFromThem() {
        let fixes = [
            fix(at: 0, north: 0),
            fix(at: 100, north: 300),
            // Paused: a ride home that must never count, not even as a spike.
            fix(at: 110, north: 2_000),
            fix(at: 200, north: 2_300),
        ]
        let route = MeasuredRoute(fixes) { $0 < start.addingTimeInterval(105) || $0 > start.addingTimeInterval(150) }
        #expect(route.steps[2].meters == 0)
        #expect(!route.steps[3].isSpike)
        #expect(abs(route.meters - 600) < 5)
    }

    // MARK: Runs

    private func makeRun() -> Run {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        return run
    }

    @Test func newRunsAreMeasuredBySpeedAndKeepTheStraightLineSum() {
        let run = makeRun()
        for second in 0...120 {
            run.record(RouteSample(
                timestamp: start.addingTimeInterval(Double(second)),
                latitude: Double(second) * 2.5 / 111_111,
                longitude: (second.isMultiple(of: 2) ? 2 : -2) / 111_111,
                horizontalAccuracy: 5,
                speed: 2.5,
                speedAccuracy: 0.3
            ))
        }
        run.finish(at: start.addingTimeInterval(120))

        #expect(run.distanceMethod == DistanceEstimator.method)
        #expect(abs(run.distanceMeters - 300) < 0.001)
        #expect((run.gpsTrackMeters ?? 0) > run.distanceMeters)
        // The charts and sections are measured the same way, so they add up to the run's distance.
        #expect(abs((run.activeRoute.last?.meters ?? 0) - run.distanceMeters) < 0.001)
    }

    @Test func aRunPickedUpAfterTheAppClosedCarriesOn() throws {
        let run = makeRun()
        for second in 0...10 {
            run.record(RouteSample(timestamp: start.addingTimeInterval(Double(second)), latitude: Double(second) * 3 / 111_111, longitude: 0, horizontalAccuracy: 5, speed: 3, speedAccuracy: 0.3))
        }
        try container.mainContext.save()
        let id = run.runID
        let fresh = ModelContext(container)
        let reloaded = try #require(try fresh.fetch(FetchDescriptor<Run>(predicate: #Predicate { $0.runIDValue == id })).first)
        reloaded.record(RouteSample(timestamp: start.addingTimeInterval(11), latitude: 33 / 111_111, longitude: 0, horizontalAccuracy: 5, speed: 3, speedAccuracy: 0.3))
        #expect(abs(reloaded.distanceMeters - 33) < 0.001)
    }

    @Test func appleDistanceIsKeptUntilTheRunFinishes() {
        let run = makeRun()
        run.recordAppleDistance(120)
        run.recordAppleDistance(250)
        #expect(run.appleDistanceMeters == 250)
        run.finish(at: start.addingTimeInterval(100))
        run.recordAppleDistance(999)
        #expect(run.appleDistanceMeters == 250)
    }
}
