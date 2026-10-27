//
//  CalorieTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// Calories from Minetti's curves, 100 m at a time, and the heights they read from the barometer or GPS.
@MainActor
struct CalorieTests {
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

    /// Whether two lists of numbers match to within rounding.
    private func close(_ values: [Double], _ expected: [Double]) -> Bool {
        values.count == expected.count && zip(values, expected).allSatisfy { abs($0 - $1) < 1e-9 }
    }

    /// `count` legs of `meters` each at `speed`, climbing `grade` of each.
    private func legs(_ count: Int, meters: Double = 10, speed: Double = 4, grade: Double = 0) -> [EnergyLeg] {
        Array(repeating: EnergyLeg(meters: meters, seconds: meters / speed, climb: meters * grade), count: count)
    }

    // MARK: Minetti's curves

    @Test func theCurvesMatchMinettisFlatCosts() {
        #expect(EnergyCost.running(grade: 0) == 3.6)
        #expect(EnergyCost.walking(grade: 0) == 2.5)
        #expect(abs(EnergyCost.running(grade: 0.4) - 16.85) < 0.01)
        #expect(abs(EnergyCost.running(grade: -0.4) - 3.61) < 0.01)
    }

    @Test func runningDownhillIsCheapestAroundMinusTwentyPercent() {
        let cheapest = stride(from: -0.45, through: 0.45, by: 0.01).min { EnergyCost.running(grade: $0) < EnergyCost.running(grade: $1) }!
        #expect(abs(cheapest - -0.18) < 0.015)
        #expect(EnergyCost.running(grade: 0.1) > EnergyCost.running(grade: 0))
        #expect(EnergyCost.running(grade: -0.1) < EnergyCost.running(grade: 0))
    }

    // MARK: Estimates

    @Test func tenFlatKilometersAtSeventyKilogramsIsAboutSixHundred() throws {
        let estimate = try #require(CalorieEstimator.estimate(legs(1_000)))
        #expect(abs(estimate.kilocalories(bodyMass: 70) - 602.3) < 0.5)
        #expect(estimate.hillShare == 0)
        #expect(estimate.walkedMeters == 0)
    }

    @Test func climbingCostsMoreAndTheHillsShareSaysHowMuch() throws {
        let estimate = try #require(CalorieEstimator.estimate(legs(100, grade: 0.1)))
        // 1 km at 10%: Minetti's 5.97 J/kg/m along the slope.
        #expect(abs(estimate.perKilogram - 1.4336) < 0.001)
        #expect(estimate.hillShare > 0.35)
    }

    @Test func upAndBackDownStillCostsMoreThanFlat() throws {
        let estimate = try #require(CalorieEstimator.estimate(legs(50, grade: 0.1) + legs(50, grade: -0.1)))
        #expect(estimate.perKilogram > estimate.flatPerKilogram)
    }

    @Test func slopesAreCappedAtFortyPercent() throws {
        let steep = try #require(CalorieEstimator.estimate(legs(100, speed: 2, grade: 0.4)))
        let steeper = try #require(CalorieEstimator.estimate(legs(100, speed: 2, grade: 0.7)))
        #expect(steep.perKilogram == steeper.perKilogram)
        let down = try #require(CalorieEstimator.estimate(legs(100, speed: 3, grade: -0.4)))
        let further = try #require(CalorieEstimator.estimate(legs(100, speed: 3, grade: -0.9)))
        #expect(down.perKilogram == further.perKilogram)
    }

    @Test func slowerThanTheWalkingSpeedUsesTheWalkingCurve() throws {
        let walk = try #require(CalorieEstimator.estimate(legs(100, speed: 1.4)))
        #expect(walk.walkedMeters == 1_000)
        #expect(abs(walk.perKilogram - 2.5 * 1_000 / 4_184) < 0.0001)

        let jog = try #require(CalorieEstimator.estimate(legs(100, speed: 2.0)))
        #expect(jog.walkedMeters == 0)
        #expect(abs(jog.perKilogram - 3.6 * 1_000 / 4_184) < 0.0001)
    }

    @Test func legsAreCutIntoHundredMeterStretches() {
        let chunks = CalorieEstimator.chunks([EnergyLeg(meters: 250, seconds: 50, climb: 10)])
        #expect(close(chunks.map(\.meters), [100, 100, 50]))
        #expect(close(chunks.map(\.seconds), [20, 20, 10]))
        #expect(close(chunks.map(\.climb), [4, 4, 2]))
    }

    @Test func aShortLastStretchJoinsTheOneBefore() {
        let chunks = CalorieEstimator.chunks([EnergyLeg(meters: 230, seconds: 46, climb: 0)])
        #expect(close(chunks.map(\.meters), [100, 130]))
    }

    @Test func noGroundNoEstimate() {
        #expect(CalorieEstimator.estimate([]) == nil)
        #expect(CalorieEstimator.estimate([EnergyLeg(meters: 0, seconds: 30, climb: 0)]) == nil)
    }

    // MARK: Heights

    @Test func theBarometerSetsTheClimbAndGPSTheLevel() throws {
        let run = makeRun()
        var barometer: [AltitudeSample] = []
        // 1 km up a steady 5% climb, GPS height 100 m too high and wobbling by 4 m.
        for step in 0...100 {
            let seconds = Double(step) * 2.5
            let meters = Double(step) * 10
            let climb = meters * 0.05
            run.record(sample(at: seconds, meters: meters, altitude: 100 + climb + (step.isMultiple(of: 2) ? 4 : -4), verticalAccuracy: 5))
            barometer.append(AltitudeSample(timestamp: start.addingTimeInterval(seconds), relativeMeters: climb))
        }
        run.saveBarometricAltitude(barometer)
        run.finish(at: start.addingTimeInterval(250))

        let track = try #require(run.altitudeTrack)
        #expect(track.source == .barometer)
        #expect(abs(track.points.first!.altitude - 100) < 4.5)
        let elevation = try #require(run.elevation)
        #expect(abs(elevation.gain - 50) < 1.5)
        #expect(elevation.loss == 0)

        let estimate = try #require(run.calorieEstimate)
        let steady = try #require(CalorieEstimator.estimate(legs(100, grade: 0.05)))
        #expect(abs(estimate.perKilogram - steady.perKilogram) / steady.perKilogram < 0.02)
    }

    @Test func aBarometerThatStoppedEarlyGivesWayToGPS() throws {
        let run = makeRun()
        for step in 0...60 {
            run.record(sample(at: Double(step) * 5, meters: Double(step) * 15, altitude: 50, verticalAccuracy: 4))
        }
        run.saveBarometricAltitude([
            AltitudeSample(timestamp: start, relativeMeters: 0),
            AltitudeSample(timestamp: start.addingTimeInterval(30), relativeMeters: 1),
        ])
        run.finish(at: start.addingTimeInterval(300))
        #expect(run.altitudeTrack?.source == .gps)
    }

    @Test func gpsWobbleOnTheFlatAddsAlmostNothing() throws {
        let run = makeRun()
        for step in 0...300 {
            let wobble = [0.0, 3, -2, 4, -3, 1][step % 6]
            run.record(sample(at: Double(step) * 2.5, meters: Double(step) * 10, altitude: 40 + wobble, verticalAccuracy: 6))
        }
        run.finish(at: start.addingTimeInterval(750))
        let estimate = try #require(run.calorieEstimate)
        #expect(abs(estimate.hillShare) < 0.02)
    }

    @Test func groundCoveredWhilePausedIsLeftOut() throws {
        let run = makeRun()
        for step in 0...20 {
            run.record(sample(at: Double(step) * 2.5, meters: Double(step) * 10, altitude: 10, verticalAccuracy: 3))
        }
        run.pause(at: start.addingTimeInterval(51))
        // Walked 300 m up 30 m while paused.
        run.resume(at: start.addingTimeInterval(200))
        for step in 0...20 {
            run.record(sample(at: 201 + Double(step) * 2.5, meters: 500 + Double(step) * 10, altitude: 40, verticalAccuracy: 3))
        }
        run.finish(at: start.addingTimeInterval(260))

        // 400 m of running, not the 700 m it would be with the ground covered while paused. The test fixes are
        // laid out at 111,111 m a degree; the true distance at the equator is about half a percent shorter.
        let legs = run.energyLegs
        #expect(abs(legs.reduce(0) { $0 + $1.meters } - 400) < 4)
        #expect(legs.allSatisfy { abs($0.climb) < 0.001 })
    }

    @Test func aRouteWithoutHeightsCountsAsFlat() throws {
        let run = makeRun()
        for step in 0...40 {
            run.record(sample(at: Double(step) * 2.5, meters: Double(step) * 10))
        }
        run.finish(at: start.addingTimeInterval(100))
        #expect(run.altitudeTrack == nil)
        let estimate = try #require(run.calorieEstimate)
        #expect(estimate.perKilogram == estimate.flatPerKilogram)
    }

    // MARK: Keeping calories with the run

    @Test func caloriesAreKeptAtTheWeightWhenTheRunFinished() {
        let run = makeRun()
        for step in 0...100 {
            run.record(sample(at: Double(step) * 2.5, meters: Double(step) * 10))
        }
        run.finish(at: start.addingTimeInterval(250))

        run.settleCalories(bodyMass: nil)
        #expect(run.activeCalories == nil)
        run.settleCalories(bodyMass: 70)
        // 1 km at Minetti's 3.6 J/kg/m is 60.2 kcal, less the half percent the test fixes fall short of a kilometer.
        let expected = 3.6 * 70 * run.distanceMeters / 4_184
        #expect(abs((run.activeCalories ?? 0) - expected) < 0.01)
        #expect(abs(expected - 60.2) < 0.5)
    }

    @Test func anUnfinishedRunKeepsNoCalories() {
        let run = makeRun()
        run.record(sample(at: 0, meters: 0))
        run.record(sample(at: 25, meters: 100))
        run.settleCalories(bodyMass: 70)
        #expect(run.activeCalories == nil)
    }

    @Test func theBarometerKeepsAReadingEveryFiveSecondsAndTheNewest() {
        let monitor = AltimeterMonitor()
        for second in 0...12 {
            monitor.receive(Double(second) / 10, at: start.addingTimeInterval(Double(second)))
        }
        #expect(monitor.samples.map(\.timestamp) == [0, 5, 10, 12].map { start.addingTimeInterval($0) })
    }

    @Test func barometerReadingsGoFromTheWatchToTheIPhone() throws {
        let run = makeRun()
        run.record(sample(at: 0, meters: 0))
        run.record(sample(at: 10, meters: 40))
        run.saveBarometricAltitude([AltitudeSample(timestamp: start, relativeMeters: 0), AltitudeSample(timestamp: start.addingTimeInterval(10), relativeMeters: 2)])
        run.finish(at: start.addingTimeInterval(10))

        let encoded = try #require(WatchRunRecord(run)?.encoded())
        let record = try #require(WatchRunRecord.decode(encoded))
        let iPhone = WindRunSchema.makeContainer(inMemory: true)
        let copy = try #require(record.insert(into: iPhone.mainContext))
        #expect(copy.barometricAltitude.map(\.relativeMeters) == [0, 2])
    }

    // MARK: Weight

    @Test func weightIsTypedInPoundsWithImperialUnits() {
        #expect(BodyWeight.kilograms(fromTyped: "154", unit: .miles).map { ($0 * 10).rounded() / 10 } == 69.9)
        #expect(BodyWeight.kilograms(fromTyped: "72,5", unit: .kilometers) == 72.5)
        #expect(BodyWeight.kilograms(fromTyped: "7", unit: .kilometers) == nil)
        #expect(BodyWeight.kilograms(fromTyped: "", unit: .kilometers) == nil)
        #expect(BodyWeight.typed(69.853, unit: .miles) == "154")
    }

    @Test func weightStaysOnThisIPhone() {
        #expect(!CloudSettings.keys.contains(BodyWeight.storageKey))
    }
}
