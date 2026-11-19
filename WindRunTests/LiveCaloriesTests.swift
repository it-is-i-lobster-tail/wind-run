//
//  LiveCaloriesTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// Calories as the run goes, and the one stretch cost they share with the finished run's estimate.
@MainActor
struct LiveCaloriesTests {
    // MARK: One stretch

    @Test func aStretchFasterThanWalkingRuns() {
        let stretch = CalorieEstimator.cost(meters: 100, seconds: 30, grade: 0)
        #expect(!stretch.isWalking)
        #expect(stretch.joules == EnergyCost.running(grade: 0) * 100)
    }

    @Test func aStretchSlowerThanWalkingWalks() {
        // 1 m/s is under the 1.8 m/s walking speed.
        let stretch = CalorieEstimator.cost(meters: 100, seconds: 100, grade: 0)
        #expect(stretch.isWalking)
        #expect(stretch.joules == EnergyCost.walking(grade: 0) * 100)
    }

    @Test func aStretchWithNoTimeRuns() {
        #expect(!CalorieEstimator.cost(meters: 100, seconds: 0, grade: 0).isWalking)
    }

    @Test func theGradeIsCappedBothWays() {
        #expect(CalorieEstimator.clampedGrade(0.9) == CalorieEstimator.maximumGrade)
        #expect(CalorieEstimator.clampedGrade(-0.9) == -CalorieEstimator.maximumGrade)
        #expect(CalorieEstimator.clampedGrade(0.1) == 0.1)
        #expect(CalorieEstimator.cost(meters: 100, seconds: 30, grade: 0.9).joules == CalorieEstimator.cost(meters: 100, seconds: 30, grade: 0.4).joules)
    }

    // MARK: As the run goes

    @Test func liveCaloriesMatchTheEstimateOnOneFlatStretch() throws {
        var live = LiveCalories()
        live.add(meters: 100, seconds: 30, grade: nil)
        let estimate = try #require(CalorieEstimator.estimate([EnergyLeg(meters: 100, seconds: 30, climb: 0)]))
        #expect(abs(live.perKilogram - estimate.perKilogram) < 1e-12)
        #expect(live.perKilogram > 0)
    }

    @Test func liveCaloriesMatchTheEstimateOnOneClimb() throws {
        var live = LiveCalories()
        live.add(meters: 100, seconds: 30, grade: 0.1)
        let estimate = try #require(CalorieEstimator.estimate([EnergyLeg(meters: 100, seconds: 30, climb: 10)]))
        #expect(abs(live.perKilogram - estimate.perKilogram) < 1e-9)
    }

    @Test func liveCaloriesUseTheWalkingCurveBelowWalkingSpeed() {
        var live = LiveCalories()
        live.add(meters: 100, seconds: 100, grade: nil)
        let expected = EnergyCost.walking(grade: 0) * 100 / CalorieEstimator.joulesPerKilocalorie
        #expect(abs(live.perKilogram - expected) < 1e-12)
    }

    @Test func liveCaloriesCapTheGrade() {
        var steep = LiveCalories()
        steep.add(meters: 100, seconds: 30, grade: 0.9)
        var capped = LiveCalories()
        capped.add(meters: 100, seconds: 30, grade: 0.4)
        #expect(steep.perKilogram == capped.perKilogram)

        var steepDown = LiveCalories()
        steepDown.add(meters: 100, seconds: 30, grade: -0.9)
        var cappedDown = LiveCalories()
        cappedDown.add(meters: 100, seconds: 30, grade: -0.4)
        #expect(steepDown.perKilogram == cappedDown.perKilogram)
    }

    @Test func noGroundAddsNoLiveCalories() {
        var live = LiveCalories()
        live.add(meters: 0, seconds: 30, grade: nil)
        live.add(meters: -5, seconds: 30, grade: nil)
        #expect(live.perKilogram == 0)
    }

    @Test func liveCaloriesAddUp() {
        var live = LiveCalories()
        live.add(meters: 100, seconds: 30, grade: nil)
        let once = live.perKilogram
        live.add(meters: 100, seconds: 30, grade: nil)
        #expect(abs(live.perKilogram - 2 * once) < 1e-12)
    }
}
