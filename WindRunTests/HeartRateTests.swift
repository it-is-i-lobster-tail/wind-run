//
//  HeartRateTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

@MainActor
struct HeartRateTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    // Each test gets its own instance, so its own store. It has to outlive the models in it.
    private let container = WindRunSchema.makeContainer(inMemory: true)

    private func makeRun() -> Run {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        return run
    }

    private func reading(at seconds: TimeInterval, _ beatsPerMinute: Double) -> HeartRateSample {
        HeartRateSample(timestamp: start.addingTimeInterval(seconds), beatsPerMinute: beatsPerMinute)
    }

    @Test func averageAndMaximumComeFromTheReadings() {
        let run = makeRun()
        run.record(reading(at: 5, 140))
        run.record(reading(at: 10, 150))
        run.record(reading(at: 15, 160))

        #expect(run.averageHeartRate == 150)
        #expect(run.maximumHeartRate == 160)
        #expect(run.heartRateSamples.map(\.beatsPerMinute) == [140, 150, 160])
    }

    @Test func noReadingsMeansNoHeartRate() {
        let run = makeRun()
        run.finish(at: start.addingTimeInterval(60))

        #expect(run.averageHeartRate == nil)
        #expect(run.maximumHeartRate == nil)
    }

    @Test func readingsOnlyCountWhileRunning() {
        let run = makeRun()
        run.record(reading(at: 5, 150))
        run.pause(at: start.addingTimeInterval(10))
        run.record(reading(at: 15, 90))
        run.resume(at: start.addingTimeInterval(20))
        run.record(reading(at: 25, 154))
        run.finish(at: start.addingTimeInterval(30))
        run.record(reading(at: 35, 100))

        #expect(run.heartRateSamples.count == 2)
        #expect(run.averageHeartRate == 152)
    }

    @Test func outOfOrderAndEmptyReadingsAreIgnored() {
        let run = makeRun()
        run.record(reading(at: 10, 150))
        run.record(reading(at: 10, 151))
        run.record(reading(at: 5, 140))
        run.record(reading(at: 15, 0))

        #expect(run.heartRateSamples.map(\.beatsPerMinute) == [150])
    }

    @Test func deletingARunDeletesItsHeartRate() throws {
        let run = makeRun()
        run.record(reading(at: 5, 140))
        try container.mainContext.save()

        container.mainContext.delete(run)
        try container.mainContext.save()

        #expect(try container.mainContext.fetch(FetchDescriptor<HeartRateSample>()).isEmpty)
    }

    @Test func heartRateIsShownInWholeBeats() {
        #expect(RunFormat.heartRate(142.4) == "142 bpm")
        #expect(RunFormat.heartRate(142.6, withUnit: false) == "143")
        #expect(RunFormat.heartRate(nil) == "–– bpm")
        #expect(RunFormat.heartRate(nil, withUnit: false) == "––")
    }
}
