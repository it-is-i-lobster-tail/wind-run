import Foundation
import HealthKit
import SwiftData
import Testing
@testable import WindRun

@MainActor
struct CyclingWorkoutTests {
    @Test func customRideRoundTripsThroughTheWatchAndStaysOutOfCoach() throws {
        let phone = WindRunSchema.makeContainer(inMemory: true)
        let watch = WindRunSchema.makeContainer(inMemory: true)
        var draft = WorkoutDraft.starter()
        draft.sport = .cycling
        let plan = draft.save(replacing: nil, in: phone.mainContext)
        #expect(WorkoutDraft(plan).sport == .cycling)
        #expect(plan.name == "My New Ride")
        let packet = WatchSavedWorkout.encode([WatchSavedWorkout(plan)])
        let received = try #require(WatchSavedWorkout.decode(packet).first)
        let copy = received.makePlan(in: watch.mainContext)
        #expect(copy.sport == .cycling)

        let ride = Run(kind: .intervals, sport: copy.sport)
        watch.mainContext.insert(ride)
        ride.intervalPlanValue = copy
        ride.finish(at: ride.startDate.addingTimeInterval(600))
        let record = try #require(WatchRunRecord(ride))
        let imported = try #require(try record.save(into: phone.mainContext))
        #expect(imported.sport == .cycling)
        #expect(imported.intervalPlan?.sport == .cycling)
        #expect(HealthWorkout(imported)?.sport.healthConfiguration.activityType == .cycling)
        #expect(imported.sport.healthDistanceType == HKQuantityType(.distanceCycling))
        #expect(RecentRunsReader.appRuns(in: phone.mainContext).isEmpty)
    }

    @Test func olderModelsReadAsRunning() {
        let run = Run()
        run.workoutTypeValue = nil
        #expect(run.sport == .running)
        #expect(WorkoutDraft(IntervalPlan(name: "Older workout")).sport == .running)
    }

    @Test func cyclingCaloriesAgreeLiveAndAfterFinishing() throws {
        // Half an hour at 13 mph is 8 gross METs, or 245 active kcal for a 70 kg rider.
        let leg = EnergyLeg(meters: 6.5 * DistanceUnit.miles.meters, seconds: 1_800, climb: 25)
        let stop = EnergyLeg(meters: 0, seconds: 300, climb: 0)
        let estimate = try #require(CalorieEstimator.estimate([leg, stop], sport: .cycling))
        var live = LiveCalories()
        live.add(meters: leg.meters, seconds: leg.seconds, grade: 0.04, sport: .cycling)
        #expect(estimate.kilocalories(bodyMass: 70) == 245)
        #expect(live.perKilogram == estimate.perKilogram)
        #expect(CalorieEstimator.estimate([stop], sport: .cycling) == nil)
        #expect(estimate.walkedMeters == 0)
    }

    @Test func cyclingDistanceAtRoadSpeedIsKeptInRecordingAndReplay() {
        let ride = Run(sport: .cycling)
        for second in 0...10 {
            ride.record(RouteSample(timestamp: ride.startDate.addingTimeInterval(Double(second)),
                                    latitude: Double(second * 12) / 111_000, longitude: 0,
                                    horizontalAccuracy: 3, speed: 12))
        }
        #expect(ride.distanceMeters == 120)
        #expect(ride.activeRoute.last?.meters == 120)
    }

    @Test func cyclingCalloutsUseTheirOwnFrequencyMetricsAndSpeed() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("distance", forKey: PaceCalloutSettings.modeKey)
        #expect(PaceCalloutSettings.current(for: .cycling, in: defaults).mode == .off)
        defaults.set("time", forKey: PaceCalloutSettings.key(PaceCalloutSettings.modeKey, for: .cycling))
        defaults.set(60.0, forKey: PaceCalloutSettings.key(PaceCalloutSettings.secondsKey, for: .cycling))
        for (unit, speed, clip) in [(DistanceUnit.kilometers, "24 kilometers per hour", "speed_240"),
                                     (.miles, "14.9 miles per hour", "speed_149")] {
            defaults.set(unit.rawValue, forKey: DistanceUnit.storageKey)
            let cycling = PaceCalloutSettings.current(for: .cycling, in: defaults)
            #expect(cycling.paces == [.speed])
            var tracker = try #require(PaceCalloutTracker(settings: cycling))
            let update = tracker.update(elapsed: 60, meters: 400)
            let split = try #require(update)
            #expect(split.spokenText == "1 minute, speed \(speed).")
            let pieces = try #require(VoiceScript.bundled.pieces(for: split.spokenText))
            #expect(pieces.map(\.clip).contains(clip))
            let sample = try #require(PaceCallout.sample(for: cycling))
            #expect(VoiceScript.bundled.pieces(for: sample.spokenText) != nil)
        }
        defaults.set("", forKey: PaceCalloutSettings.key(PaceCalloutSettings.pacesKey, for: .cycling))
        #expect(PaceCalloutSettings.current(for: .cycling, in: defaults).paces.isEmpty)
        let running = PaceCalloutSettings.current(in: defaults)
        #expect(running.mode == .distance)
        #expect(running.paces == [.split])
        #expect(Set(PaceCalloutSettings.syncedKeys).isSubset(of: Set(SettingsSync.keys)))
        #expect(Set(PaceCalloutSettings.syncedKeys).isSubset(of: Set(CloudSettings.keys)))
    }
}
