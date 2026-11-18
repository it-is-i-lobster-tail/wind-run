//
//  RunModelTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// The run model's own rules: the barometer's heights between readings, a pause's edges, the calls a run
/// ignores, and the lists it keeps as JSON.
@MainActor
struct RunModelTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    // Each test gets its own instance, so its own store. It has to outlive the models in it.
    private let container = WindRunSchema.makeContainer(inMemory: true)

    private func makeRun() -> Run {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        return run
    }

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    private func reading(at seconds: TimeInterval, _ meters: Double) -> AltitudeSample {
        AltitudeSample(timestamp: at(seconds), relativeMeters: meters)
    }

    // MARK: Barometer

    @Test func theBarometerNeedsTwoReadingsAndSomeDates() {
        #expect(Run.barometerHeights([reading(at: 0, 0)], at: [at(0)]) == nil)
        #expect(Run.barometerHeights([reading(at: 0, 0), reading(at: 60, 6)], at: []) == nil)
    }

    @Test func theBarometerReadsBetweenItsReadings() {
        let readings = [reading(at: 0, 0), reading(at: 60, 6)]
        #expect(Run.barometerHeights(readings, at: [at(0), at(30), at(60)]) == [0, 3, 6])
    }

    @Test func datesOutsideTheReadingsTakeTheNearestEnd() {
        let readings = [reading(at: 0, 0), reading(at: 60, 6)]
        #expect(Run.barometerHeights(readings, at: [at(-10), at(0), at(60)]) == [0, 0, 6])
        #expect(Run.barometerHeights(readings, at: [at(0), at(60), at(70)]) == [0, 6, 6])
    }

    @Test func theBarometerIsUsedOnlyWhenItCoversNineInTenDates() {
        let readings = [reading(at: 0, 0), reading(at: 10, 0)]
        let near = (0..<9).map { at(TimeInterval($0)) }
        // Nine of ten within 30 s of a reading.
        #expect(Run.barometerHeights(readings, at: near + [at(1_000)]) != nil)
        // Eight of ten.
        #expect(Run.barometerHeights(readings, at: Array(near.prefix(8)) + [at(1_000), at(1_001)]) == nil)
    }

    // MARK: Pauses

    @Test func aPauseNeverEndsBeforeItStarts() {
        let pause = RunPause(startDate: at(100))
        container.mainContext.insert(pause)
        pause.end(at: at(95))
        #expect(pause.endDate == at(100))
        #expect(pause.duration(at: at(200)) == 0)
    }

    @Test func anOpenPauseCountsUpToNow() {
        let pause = RunPause(startDate: at(100))
        container.mainContext.insert(pause)
        #expect(pause.duration(at: at(130)) == 30)
        #expect(pause.duration(at: at(90)) == 0)
        #expect(pause.contains(at(100)))
        #expect(pause.contains(at(10_000)))
        #expect(!pause.contains(at(99)))
    }

    @Test func anEndedPauseLeavesOutItsEnd() {
        let pause = RunPause(startDate: at(100))
        container.mainContext.insert(pause)
        pause.end(at: at(160))
        #expect(pause.contains(at(100)))
        #expect(pause.contains(at(159)))
        #expect(!pause.contains(at(160)))
        #expect(pause.duration(at: at(130)) == 30)
        #expect(pause.duration(at: at(500)) == 60)
    }

    // MARK: Ignored calls

    @Test func pausingTwiceKeepsOnePause() {
        let run = makeRun()
        run.pause(at: at(10))
        run.pause(at: at(20))
        #expect(run.pauses.count == 1)
        #expect(run.pauses.first?.startDate == at(10))
        #expect(run.status == .paused)
    }

    @Test func resumingARunThatIsntPausedChangesNothing() {
        let run = makeRun()
        run.resume(at: at(10))
        #expect(run.status == .active)
        #expect(run.pauses.isEmpty)
    }

    @Test func aFinishedRunStaysFinished() {
        let run = makeRun()
        run.finish(at: at(100))
        run.discard(at: at(200))
        run.finish(at: at(300))
        #expect(run.status == .complete)
        #expect(run.endDate == at(100))
    }

    @Test func finishingEndsAnOpenPause() {
        let run = makeRun()
        run.pause(at: at(40))
        run.finish(at: at(100))
        #expect(run.pauses.first?.endDate == at(100))
        #expect(run.activeDuration() == 40)
    }

    @Test func appleDistanceKeepsOnlyARealDistance() {
        let run = makeRun()
        run.recordAppleDistance(.nan)
        #expect(run.appleDistanceMeters == nil)
        run.recordAppleDistance(-1)
        #expect(run.appleDistanceMeters == nil)
        run.recordAppleDistance(.infinity)
        #expect(run.appleDistanceMeters == nil)
        run.recordAppleDistance(1_200)
        #expect(run.appleDistanceMeters == 1_200)
        run.finish(at: at(600))
        run.recordAppleDistance(1_500)
        #expect(run.appleDistanceMeters == 1_200)
    }

    @Test func theLastRecordedDateIsTheLaterOfTheLastFixAndReading() {
        let run = makeRun()
        #expect(run.lastRecordedDate == nil)
        run.record(RouteSample(timestamp: at(10), latitude: 0, longitude: 0, horizontalAccuracy: 5))
        #expect(run.lastRecordedDate == at(10))
        run.record(HeartRateSample(timestamp: at(20), beatsPerMinute: 150))
        #expect(run.lastRecordedDate == at(20))
        run.record(RouteSample(timestamp: at(30), latitude: 0.001, longitude: 0, horizontalAccuracy: 5))
        #expect(run.lastRecordedDate == at(30))
    }

    // MARK: Lists kept as JSON

    @Test func noStepCountsStoresNothing() {
        let run = makeRun()
        run.saveStepCounts([])
        #expect(run.stepCountDataValue == nil)
        #expect(run.stepCounts.isEmpty)
        #expect(run.stepTotal == nil)
        #expect(run.meanCadence == nil)
    }

    @Test func stepCountsRoundTripAndAnEmptyListClearsThem() {
        let run = makeRun()
        let counts = [
            StepCountSample(start: at(0), end: at(30), count: 100),
            StepCountSample(start: at(30), end: at(60), count: 50),
        ]
        run.saveStepCounts(counts)
        run.finish(at: at(60))
        #expect(run.stepCounts == counts)
        #expect(run.stepTotal == 150)
        #expect(run.meanCadence == 150)

        run.saveStepCounts([])
        #expect(run.stepCountDataValue == nil)
        #expect(run.stepTotal == nil)
    }

    @Test func aStepLogRoundTripsAndAnEmptyOneClearsIt() {
        let run = makeRun()
        let steps = [RecordedStep(index: 0, startElapsed: 0, endElapsed: 60, startMeters: 0, endMeters: 200, cut: false)]
        run.saveStepLog(steps)
        #expect(run.stepLog == steps)
        run.saveStepLog([])
        #expect(run.stepLogDataValue == nil)
        #expect(run.stepLog.isEmpty)
    }

    @Test func unreadableJSONReadsAsNothing() {
        #expect(Run.decodedJSON([StepCountSample].self, from: nil) == nil)
        #expect(Run.decodedJSON([StepCountSample].self, from: Data("not json".utf8)) == nil)
        #expect(Run.encodedJSONUnlessEmpty([StepCountSample]()) == nil)
        #expect(Run.encodedJSONUnlessEmpty([1, 2]) != nil)
    }
}
