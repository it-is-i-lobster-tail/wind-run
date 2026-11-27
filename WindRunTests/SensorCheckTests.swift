//
//  SensorCheckTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// The sensor checkup's rules: what setup says, what the live test shows, the Run tab's chips, and why a
/// finished run is missing something.
@MainActor
struct SensorCheckTests {
    /// Everything set up and allowed, on an iPhone with the watch app.
    private var allGood: SensorSetup {
        SensorSetup(
            heartRateOn: true,
            health: .allowed,
            location: .allowed,
            preciseLocation: true,
            stepsOn: true,
            motionAvailable: true,
            motionAllowed: true,
            motionDenied: false,
            barometerAvailable: true,
            watch: .installed
        )
    }

    private func row(_ kind: SensorKind, in rows: [SensorRow]) -> SensorRow? {
        rows.first { $0.id == kind }
    }

    // MARK: Setup

    @Test func everythingSetUpIsAllGreen() {
        let rows = SensorRules.setupRows(allGood)
        #expect(rows.map(\.id) == [.heartRate, .healthWorkouts, .location, .preciseLocation, .motion, .barometer, .watchApp])
        #expect(rows.allSatisfy { $0.state == .ok })
        #expect(rows.allSatisfy { $0.fix == nil })
    }

    @Test func heartRateOffOffersToTurnItOn() {
        var setup = allGood
        setup.heartRateOn = false
        let row = SensorRules.heartRate(setup)
        #expect(row.state == .warning)
        #expect(row.fix == .turnOnHeartRate)
        // Off by choice isn't a problem the Run tab should nag about.
        #expect(SensorRules.readyProblem(setup, SensorLiveReadings(), elapsed: 0) == nil)
    }

    @Test func healthBlockingWorkoutsIsAProblemOnlyWithHeartRateOn() {
        var setup = allGood
        setup.health = .denied
        #expect(SensorRules.health(setup).state == .problem)
        #expect(SensorRules.health(setup).fix == .healthSettings)
        setup.heartRateOn = false
        #expect(SensorRules.health(setup).state == .warning)
    }

    @Test func healthNotAskedWithHeartRateOnAsks() {
        var setup = allGood
        setup.health = .notAsked
        #expect(SensorRules.health(setup).fix == .turnOnHeartRate)
        setup.heartRateOn = false
        #expect(SensorRules.health(setup).state == .notUsed)
    }

    @Test func noHealthOnTheDeviceMeansNoHeartRate() {
        var setup = allGood
        setup.health = .unavailable
        #expect(SensorRules.heartRate(setup).state == .notUsed)
        #expect(SensorRules.heartRate(setup).fix == nil)
    }

    @Test func locationOffAndPreciseLocationOffAreProblems() {
        var setup = allGood
        setup.location = .denied
        #expect(SensorRules.location(setup).state == .problem)
        #expect(SensorRules.location(setup).fix == .openSettings)
        #expect(SensorRules.preciseLocation(setup).state == .notUsed)

        setup.location = .allowed
        setup.preciseLocation = false
        #expect(SensorRules.preciseLocation(setup).state == .problem)
        #expect(SensorRules.readyProblem(setup, SensorLiveReadings(), elapsed: 0)?.id == .preciseLocation)
    }

    @Test func locationNotAskedIsWaiting() {
        var setup = allGood
        setup.location = .notAsked
        #expect(SensorRules.location(setup).state == .waiting)
    }

    @Test func motionRules() {
        var setup = allGood
        setup.motionDenied = true
        setup.motionAllowed = false
        #expect(SensorRules.motion(setup).state == .problem)
        #expect(SensorRules.motion(setup).fix == .openSettings)
        #expect(SensorRules.barometer(setup).state == .warning)

        setup.stepsOn = false
        #expect(SensorRules.motion(setup).state == .warning)

        setup.motionDenied = false
        #expect(SensorRules.motion(setup).state == .notUsed)
        #expect(SensorRules.motion(setup).fix == .turnOnSteps)

        setup.stepsOn = true
        #expect(SensorRules.motion(setup).state == .waiting)

        setup.motionAvailable = false
        #expect(SensorRules.motion(setup).state == .notUsed)
        #expect(SensorRules.motion(setup).fix == nil)
    }

    @Test func noBarometerIsFine() {
        var setup = allGood
        setup.barometerAvailable = false
        #expect(SensorRules.barometer(setup).state == .notUsed)
    }

    @Test func watchRowFollowsWatchConnectivity() {
        var setup = allGood
        setup.watch = nil
        #expect(SensorRules.watchApp(setup) == nil)
        setup.watch = .notPaired
        #expect(SensorRules.watchApp(setup)?.state == .notUsed)
        setup.watch = .appNotInstalled
        #expect(SensorRules.watchApp(setup)?.state == .warning)
    }

    // MARK: Live test

    @Test func heartRateWaitsThenSaysWhatToTry() {
        var setup = allGood
        setup.earbudsConnected = true
        let live = SensorLiveReadings(heartRate: .listening, gpsStarted: true)
        #expect(SensorRules.liveHeartRate(setup, live, elapsed: 10).state == .waiting)
        let late = SensorRules.liveHeartRate(setup, live, elapsed: SensorRules.heartRateWait)
        #expect(late.state == .problem)
        #expect(late.detail.contains("Heart Rate is on in your AirPods settings"))
        #expect(late.detail.contains("start the run on the watch"))

        setup.earbudsConnected = false
        setup.watch = .notPaired
        let tips = SensorRules.heartRateTips(setup)
        #expect(tips.contains("strap is paired"))
        #expect(!tips.contains("watch"))
    }

    @Test func heartRateReadingShowsItsSourceAndCount() {
        let live = SensorLiveReadings(heartRate: .listening, beatsPerMinute: 87.6, source: .earbuds, readingCount: 14)
        let row = SensorRules.liveHeartRate(allGood, live, elapsed: 40)
        #expect(row.state == .ok)
        #expect(row.beatsPerMinute == 88)
        #expect(row.detail == "From AirPods or Powerbeats. 14 readings so far.")
    }

    @Test func heartRateOffOrBlockedSaysSoInsteadOfTesting() {
        var setup = allGood
        setup.heartRateOn = false
        #expect(SensorRules.liveHeartRate(setup, SensorLiveReadings(), elapsed: 50).fix == .turnOnHeartRate)
        setup.heartRateOn = true
        setup.health = .denied
        let row = SensorRules.liveHeartRate(setup, SensorLiveReadings(), elapsed: 50)
        #expect(row.state == .problem)
        #expect(row.fix == .healthSettings)
    }

    @Test func heartRateSessionTroubles() {
        #expect(SensorRules.liveHeartRate(allGood, SensorLiveReadings(heartRate: .couldNotStart), elapsed: 1).title == "Heart rate couldn't start")
        #expect(SensorRules.liveHeartRate(allGood, SensorLiveReadings(heartRate: .endedEarly), elapsed: 1).title == "Heart rate stopped")
    }

    @Test func gpsAccuracyBands() {
        func state(_ accuracy: Double?) -> SensorState {
            SensorRules.liveGPS(allGood, SensorLiveReadings(gpsStarted: true, gpsAccuracy: accuracy)).state
        }
        #expect(state(nil) == .waiting)
        #expect(state(4) == .ok)
        #expect(state(SensorRules.goodAccuracy) == .ok)
        #expect(state(22) == .warning)
        #expect(state(65) == .problem)
        #expect(SensorRules.liveGPS(allGood, SensorLiveReadings(gpsStarted: true, gpsAccuracy: 4.4)).title == "GPS ±4 m")
    }

    @Test func gpsNotStartedIsNotPartOfTheCheck() {
        #expect(SensorRules.liveGPS(allGood, SensorLiveReadings()).state == .notUsed)
    }

    @Test func stepsLiveRow() {
        #expect(SensorRules.liveSteps(allGood, SensorLiveReadings(stepsStarted: true))?.state == .waiting)
        #expect(SensorRules.liveSteps(allGood, SensorLiveReadings(stepsStarted: true, steps: 12))?.title == "Steps 12")
        var setup = allGood
        setup.motionAvailable = false
        #expect(SensorRules.liveSteps(setup, SensorLiveReadings()) == nil)
    }

    // MARK: Run tab

    @Test func chipsShowOnlyWhatIsOn() {
        var setup = allGood
        let live = SensorLiveReadings(heartRate: .listening, beatsPerMinute: 72, source: .strapOrSensor, readingCount: 3, gpsStarted: true, gpsAccuracy: 4, stepsStarted: true, steps: 2)
        let chips = SensorRules.chips(setup, live, elapsed: 20)
        #expect(chips.map(\.id) == [.gps, .heartRate, .steps])
        #expect(chips.map(\.text) == ["GPS ±4 m", "72 Strap", "Steps"])
        #expect(chips.allSatisfy { $0.state == .ok })

        setup.heartRateOn = false
        setup.stepsOn = false
        #expect(SensorRules.chips(setup, live, elapsed: 20).map(\.id) == [.gps])
    }

    @Test func heartChipTurnsRedWithNoReading() {
        let live = SensorLiveReadings(heartRate: .listening, gpsStarted: true, gpsAccuracy: 5)
        let heart = SensorRules.chips(allGood, live, elapsed: 45).first { $0.id == .heartRate }
        #expect(heart?.state == .problem)
        #expect(heart?.text == "No reading")
        #expect(SensorRules.readyProblem(allGood, live, elapsed: 45)?.id == .heartRate)
        #expect(SensorRules.readyProblem(allGood, live, elapsed: 5) == nil)
    }

    @Test func setupProblemsComeBeforeLiveOnes() {
        var setup = allGood
        setup.location = .denied
        let live = SensorLiveReadings(heartRate: .listening)
        #expect(SensorRules.readyProblem(setup, live, elapsed: 45)?.id == .location)
        #expect(SensorRules.chips(setup, live, elapsed: 45).first?.text == "GPS off")
    }

    // MARK: Finished runs

    private func report(
        heartRateOn: Bool = true,
        session: RunSensorReport.HeartRateSession = .started,
        endedEarly: Bool = false,
        workoutSession: Bool = true,
        stepsOn: Bool = true,
        motionAllowed: Bool = true,
        locationAllowed: Bool = true,
        precise: Bool = true,
        earbuds: Bool = false
    ) -> RunSensorReport {
        RunSensorReport(
            heartRateOn: heartRateOn,
            health: .allowed,
            heartRateSession: session,
            heartRateEndedEarly: endedEarly,
            workoutSessionStarted: workoutSession,
            stepsOn: stepsOn,
            motionAllowed: motionAllowed,
            barometerUsed: true,
            locationAllowed: locationAllowed,
            preciseLocation: precise,
            earbudsConnected: earbuds
        )
    }

    @Test func heartRateOffIsTheReason() {
        var now = allGood
        now.heartRateOn = false
        let facts = RunSensorFacts(report: report(heartRateOn: false, session: .off, earbuds: true))
        let row = RunSensorRules.heartRate(facts, now: now)
        #expect(row.state == .problem)
        #expect(row.detail == "Heart rate was off in Settings, so none was read. Headphones were connected.")
        #expect(row.fix == .turnOnHeartRate)
        // Turned on since: no button, and it says so.
        let later = RunSensorRules.heartRate(facts, now: allGood)
        #expect(later.fix == nil)
        #expect(later.detail.hasSuffix("It's on now."))
    }

    @Test func blockedAndFailedSessions() {
        var now = allGood
        now.health = .denied
        let blocked = RunSensorRules.heartRate(RunSensorFacts(report: report(session: .blockedByHealth)), now: now)
        #expect(blocked.detail.contains("Health didn't allow workouts"))
        #expect(blocked.fix == .healthSettings)
        #expect(RunSensorRules.heartRate(RunSensorFacts(report: report(session: .blockedByHealth)), now: allGood).fix == nil)
        #expect(RunSensorRules.heartRate(RunSensorFacts(report: report(session: .couldNotStart)), now: allGood).title == "Heart rate couldn't start")
        #expect(RunSensorRules.heartRate(RunSensorFacts(report: report(endedEarly: true)), now: allGood).title == "Heart rate stopped")
    }

    @Test func sessionStartedButNothingCameIn() {
        let iPhone = RunSensorRules.heartRate(RunSensorFacts(report: report(earbuds: true)), now: allGood)
        #expect(iPhone.title == "No heart rate came in")
        #expect(iPhone.detail.contains("AirPods"))
        let watch = RunSensorRules.heartRate(RunSensorFacts(report: report(), recordedOnWatch: true), now: allGood)
        #expect(watch.detail.contains("Wear the watch snugly"))
    }

    @Test func recordedHeartRateSaysWhatMeasuredIt() {
        let facts = RunSensorFacts(report: report(), heartRateReadings: 420, heartRateSources: [.appleWatch, .strapOrSensor])
        let row = RunSensorRules.heartRate(facts, now: allGood)
        #expect(row.state == .ok)
        #expect(row.detail == "420 readings from Apple Watch and a strap or sensor.")
        var early = facts
        early.report = report(endedEarly: true)
        #expect(RunSensorRules.heartRate(early, now: allGood).state == .warning)
    }

    @Test func olderRunsOnlyShowWhatTheyRecorded() {
        let facts = RunSensorFacts(report: nil, heartRateReadings: 0, fixes: 300, typicalAccuracy: 4, appleDistance: nil, steps: nil, hasBarometer: false)
        let rows = RunSensorRules.rows(facts, now: allGood)
        #expect(rows.map(\.id) == [.heartRate, .gps, .appleDistance, .steps, .barometer])
        #expect(rows.allSatisfy { $0.fix == nil })
        #expect(rows[0].detail.contains("don't say why"))
        #expect(rows[1].detail == "300 fixes, typical accuracy ±4 m.")
    }

    @Test func gpsReasons() {
        #expect(RunSensorRules.gps(RunSensorFacts(report: report(locationAllowed: false))).fix == .openSettings)
        #expect(RunSensorRules.gps(RunSensorFacts(report: report(precise: false))).detail.contains("Precise Location"))
        #expect(RunSensorRules.gps(RunSensorFacts(report: report())).state == .warning)
        #expect(RunSensorRules.gps(RunSensorFacts(fixes: 10, typicalAccuracy: 25)).state == .warning)
    }

    @Test func appleDistanceNeedsASession() {
        var now = allGood
        now.health = .denied
        let row = RunSensorRules.appleDistance(RunSensorFacts(report: report(workoutSession: false)), now: now)
        #expect(row.state == .warning)
        #expect(row.fix == .healthSettings)
        #expect(RunSensorRules.appleDistance(RunSensorFacts(appleDistance: 5_020), now: allGood).state == .ok)
    }

    @Test func stepsAndClimbReasons() {
        var now = allGood
        now.stepsOn = false
        #expect(RunSensorRules.steps(RunSensorFacts(report: report(stepsOn: false)), now: now).fix == .turnOnSteps)
        #expect(RunSensorRules.steps(RunSensorFacts(report: report(stepsOn: false)), now: allGood).fix == nil)
        now = allGood
        now.motionAllowed = false
        #expect(RunSensorRules.steps(RunSensorFacts(report: report(motionAllowed: false)), now: now).state == .problem)
        #expect(RunSensorRules.climb(RunSensorFacts(report: report(motionAllowed: false)), now: now).fix == .openSettings)
        #expect(RunSensorRules.climb(RunSensorFacts(hasBarometer: true), now: allGood).state == .ok)
        #expect(RunSensorRules.steps(RunSensorFacts(steps: 5_200), now: allGood).detail == "5200 steps from the iPhone's motion sensor.")
    }

    @Test func cyclingHasNoStepsRow() {
        let rows = RunSensorRules.rows(RunSensorFacts(countsSteps: false), now: allGood)
        #expect(!rows.contains { $0.id == .steps })
    }

    // MARK: The stored report

    private let container = WindRunSchema.makeContainer(inMemory: true)

    @Test func reportIsKeptOnTheRunAndGoesWithAWatchRun() throws {
        let context = container.mainContext
        let run = Run(startDate: Date(timeIntervalSinceReferenceDate: 0))
        context.insert(run)
        #expect(run.sensorReport == nil)
        run.updateSensorReport { $0.heartRateEndedEarly = true }
        #expect(run.sensorReport == nil)

        run.saveSensorReport(report(earbuds: true))
        run.updateSensorReport { $0.heartRateEndedEarly = true }
        #expect(run.sensorReport?.heartRateEndedEarly == true)
        #expect(run.sensorFacts.report?.earbudsConnected == true)

        run.finish(at: Date(timeIntervalSinceReferenceDate: 600))
        let record = try #require(WatchRunRecord(run))
        let decoded = try JSONDecoder().decode(WatchRunRecord.self, from: JSONEncoder().encode(record))
        let other = WindRunSchema.makeContainer(inMemory: true)
        let copy = try #require(try decoded.save(into: other.mainContext))
        #expect(copy.sensorReport == run.sensorReport)
    }

    @Test func reportHoldsNoReadingsOrNames() throws {
        let data = try JSONEncoder().encode(report(earbuds: true))
        let keys = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.sorted()
        #expect(keys == [
            "barometerUsed", "earbudsConnected", "health", "heartRateEndedEarly", "heartRateOn", "heartRateSession",
            "locationAllowed", "motionAllowed", "preciseLocation", "stepsOn", "workoutSessionStarted",
        ])
    }

    @Test func typicalAccuracyIsTheMiddleKnownOne() {
        #expect(RunSensorReport.typical([-1, 3, 9, 4, 30]) == 9)
        #expect(RunSensorReport.typical([-1]) == nil)
    }

    @Test func demoCheckIsFrozen() {
        let check = SensorCheck(demo: allGood, live: SensorLiveReadings(heartRate: .listening, beatsPerMinute: 90, readingCount: 1), elapsed: 22)
        check.start(.test)
        check.stop()
        #expect(check.isRunning)
        #expect(check.liveRows().first?.beatsPerMinute == 90)
    }
}
