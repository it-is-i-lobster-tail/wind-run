//
//  RunTrackTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

@MainActor
struct RunTrackTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let container = WindRunSchema.makeContainer(inMemory: true)

    /// A run north along a meridian: one fix every `every` seconds at `metersPerSecond`.
    private func makeRun(
        seconds: TimeInterval,
        every: TimeInterval = 5,
        metersPerSecond: Double = 3,
        altitude: (TimeInterval) -> Double = { _ in 0 },
        accuracy: (TimeInterval) -> Double = { _ in 5 }
    ) -> Run {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        var time: TimeInterval = 0
        while time <= seconds {
            run.record(RouteSample(
                timestamp: start.addingTimeInterval(time),
                latitude: (time * metersPerSecond) / 111_195,
                longitude: 0,
                altitude: altitude(time),
                horizontalAccuracy: accuracy(time)
            ))
            time += every
        }
        run.finish(at: start.addingTimeInterval(seconds))
        return run
    }

    @Test func splitsEachKilometer() throws {
        // 3 m/s for 20 minutes is 3.6 km: three whole kilometers of about 333 s each.
        let track = try #require(RunTrack(makeRun(seconds: 1_200)))
        #expect(track.kilometerSplits.count == 3)
        for split in track.kilometerSplits {
            #expect(abs(split - 333.3) < 3)
        }
        #expect(track.poorGPSShare == 0)
        #expect(abs(track.longestNonStop - 1_200) < 1)
    }

    @Test func gapsAndInaccurateFixesCountAsPoorGPS() throws {
        // The last quarter of the run has fixes worse than 20 m.
        let track = try #require(RunTrack(makeRun(seconds: 800, accuracy: { $0 >= 600 ? 25 : 5 })))
        #expect(abs(track.poorGPSShare - 0.25) < 0.02)
    }

    @Test func climbIsSplitByHalf() throws {
        // Climbs 30 m steadily in the second half only.
        let track = try #require(RunTrack(makeRun(seconds: 1_000, altitude: { $0 > 500 ? ($0 - 500) * 0.06 : 0 })))
        #expect(track.climbFirstHalf == 0)
        #expect(abs(track.climbSecondHalf - 30) < 2.5)
    }

    @Test func aPauseBreaksTheNonStopStretch() throws {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        for time in stride(from: 0.0, through: 1_500, by: 5) {
            if time == 600 { run.pause(at: start.addingTimeInterval(600)) }
            if time == 900 { run.resume(at: start.addingTimeInterval(900)) }
            run.record(RouteSample(timestamp: start.addingTimeInterval(time), latitude: time * 3 / 111_195, longitude: 0, horizontalAccuracy: 5))
        }
        run.finish(at: start.addingTimeInterval(1_500))

        let track = try #require(RunTrack(run))
        // 600 s before the pause, 600 s after it; neither stretch counts the pause.
        #expect(abs(track.longestNonStop - 600) < 6)
    }

    @Test func noRouteMeansNoTrack() {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        run.finish(at: start.addingTimeInterval(60))
        #expect(RunTrack(run) == nil)
    }
}
