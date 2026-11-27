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

    @Test func aSteadyRunCountsItsLine() {
        let fixes = (0...100).map { fix(at: Double($0), north: Double($0) * 3, speed: 3, speedAccuracy: 0.3) }
        let result = measure(fixes)
        #expect(abs(result.meters - 300) < 0.5)
        #expect(result.steps.dropFirst().allSatisfy { $0.counting == .smoothed })
    }

    @Test func aSpeedReadingLowDoesNotShortenTheRun() {
        // The iPhone reported speeds about 18% under the real pace; the distance follows the fixes, not that.
        let fixes = (0...600).map { fix(at: Double($0), north: Double($0) * 2.9, speed: 2.4, speedAccuracy: 0.8) }
        #expect(abs(measure(fixes).meters - 1_740) < 2)
    }

    @Test func sidewaysWobbleIsSmoothedOut() {
        // Running north at 2.5 m/s while the fixes swing 3 m either side, as GPS does.
        let fixes = (0...200).map { second in
            fix(at: Double(second), north: Double(second) * 2.5, east: second.isMultiple(of: 2) ? 3 : -3, speed: 2.5, speedAccuracy: 0.3)
        }
        let result = measure(fixes)
        #expect(result.meters >= 499 && result.meters < 515)
        // Adding up the straight lines reads far longer.
        #expect(result.track > 650)
    }

    @Test func noisyFixesReadCloseToTheTruth() {
        // Two meters of random error each way, a fix a second, along 1,800 m.
        var random = SeededRandom(seed: 7)
        let fixes = (0...600).map { second in
            fix(at: Double(second), north: Double(second) * 3 + random.gaussian() * 2, east: random.gaussian() * 2, speed: 3, speedAccuracy: 0.3, accuracy: 4)
        }
        let result = measure(fixes)
        #expect(result.meters > 1_790 && result.meters < 1_950)
        #expect(result.track > result.meters + 100)
    }

    @Test func cornersAreKept() {
        // A 100 m square at 3 m/s with exact fixes: smoothing mustn't cut the corners off.
        var fixes: [DistanceEstimator.Fix] = []
        var second = 0.0
        for side in 0..<4 {
            for step in 0..<34 {
                let along = min(Double(step) * 3, 100)
                let (north, east): (Double, Double) = switch side {
                case 0: (along, 0)
                case 1: (100, along)
                case 2: (100 - along, 100)
                default: (0, 100 - along)
                }
                fixes.append(fix(at: second, north: north, east: east, speed: 3, speedAccuracy: 0.3, accuracy: 4))
                second += 1
            }
        }
        let meters = measure(fixes).meters
        #expect(meters > 396 && meters < 410)
    }

    @Test func aSpikeIsFlaggedAndAddsNothing() {
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

    @Test func standingStillAddsNothing() {
        let fixes = (0...60).map { second in
            fix(at: Double(second), north: second.isMultiple(of: 2) ? 2 : -2, east: second.isMultiple(of: 3) ? 1 : -1, speed: 0.2, speedAccuracy: 0.5)
        }
        #expect(measure(fixes).meters == 0)
    }

    @Test func aLongGapCountsTheStraightLine() {
        // Lost under a bridge for 30 s: smoothing starts again on the far side.
        let fixes = [
            fix(at: 0, north: 0, speed: 3, speedAccuracy: 0.3),
            fix(at: 30, north: 90, speed: 3, speedAccuracy: 0.3),
        ]
        let result = measure(fixes)
        #expect(result.steps[1].counting == .track)
        // The estimator's flat map takes 111,195 m a degree where these fixes take 111,111, so 90 m reads 90.07.
        #expect(abs(result.meters - 90) < 0.1)
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

    @Test func newRunsAreMeasuredByTheSmoothedLineAndKeepTheStraightLineSum() {
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
        #expect(abs(run.distanceMeters - 300) < 15)
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
        let before = reloaded.distanceMeters
        reloaded.record(RouteSample(timestamp: start.addingTimeInterval(11), latitude: 33 / 111_111, longitude: 0, horizontalAccuracy: 5, speed: 3, speedAccuracy: 0.3))
        // Carries on from the last fix, picking up its pace again over the next few.
        #expect(abs(before - 30) < 0.5)
        #expect(reloaded.distanceMeters > before + 1 && reloaded.distanceMeters <= 33.1)
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

    @Test func runsMeasuredBySpeedAreMeasuredAgain() {
        let run = makeRun()
        for second in 0...100 {
            run.record(RouteSample(timestamp: start.addingTimeInterval(Double(second)), latitude: Double(second) * 3 / 111_111, longitude: 0, horizontalAccuracy: 4, speed: 2.4, speedAccuracy: 0.8))
        }
        run.finish(at: start.addingTimeInterval(100))
        // As the reported-speed method left it: 100 s at 2.4 m/s.
        run.distanceMetersValue = 240
        run.distanceMethodValue = DistanceEstimator.speedMethod

        #expect(run.remeasureDistance())
        #expect(run.distanceMethod == DistanceEstimator.method)
        #expect(abs(run.distanceMeters - 300) < 1)
        #expect(abs((run.activeRoute.last?.meters ?? 0) - run.distanceMeters) < 0.001)
        // Only once.
        #expect(!run.remeasureDistance())
    }

    @Test func otherRunsAreNotMeasuredAgain() {
        let older = makeRun()
        older.distanceMethodValue = nil
        older.distanceMetersValue = 1_234
        older.finish(at: start.addingTimeInterval(600))
        #expect(!older.remeasureDistance())
        #expect(older.distanceMeters == 1_234)

        let going = makeRun()
        going.distanceMethodValue = DistanceEstimator.speedMethod
        #expect(!going.remeasureDistance())
    }
}

/// Repeatable random numbers, so a noisy route is the same every run of the tests.
private struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> Double {
        // SplitMix64.
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }

    /// A normal number with mean 0 and spread 1.
    mutating func gaussian() -> Double {
        let u = max(next(), .leastNonzeroMagnitude)
        return (-2 * log(u)).squareRoot() * cos(2 * .pi * next())
    }
}
