//
//  HeightSmoothingTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// Heights smoothed along the route for calories, a barometer carrying on from the height a run had kept,
/// and a run from another device left silent for a day.
@MainActor
struct HeightSmoothingTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    // Each test gets its own instance, so its own store. It has to outlive the models in it.
    private let container = WindRunSchema.makeContainer(inMemory: true)
    private var context: ModelContext { container.mainContext }

    /// A fix `meters` along the route, on `stretch`.
    private func fix(meters: Double, stretch: Int = 0) -> ActiveFix {
        let sample = RouteSample(timestamp: start.addingTimeInterval(meters / 3), latitude: meters / 111_111, longitude: 0, horizontalAccuracy: 5)
        return ActiveFix(time: meters / 3, meters: meters, stretch: stretch, sample: sample)
    }

    /// A height track with a point at each of `meters`, at the matching `altitudes`, all on `stretch`.
    private func track(_ source: AltitudeSource, meters: [Double], altitudes: [Double], stretch: Int = 0) -> AltitudeTrack {
        let points = zip(meters, altitudes).enumerated().map { index, pair in
            AltitudeTrack.Point(index: index, time: pair.0 / 3, meters: pair.0, stretch: stretch, altitude: pair.1)
        }
        return AltitudeTrack(source: source, points: points)
    }

    // MARK: Smoothed heights

    @Test func smoothedHeightsAverageWithinReach() {
        // GPS heights are averaged over 50 m either side, which takes in all three points.
        let gps = track(.gps, meters: [0, 20, 40], altitudes: [0, 3, 6])
        #expect(Run.smoothedHeights(gps, fixes: [fix(meters: 20)]) == [3])
    }

    @Test func smoothedHeightsInterpolateAcrossAGap() {
        // The barometer's 10 m reach finds nothing at 100 m, so it takes the heights either side in proportion.
        let barometer = track(.barometer, meters: [0, 200], altitudes: [0, 10])
        #expect(Run.smoothedHeights(barometer, fixes: [fix(meters: 100)]) == [5])
    }

    @Test func smoothedHeightsTakeTheNearestAtTheEnds() {
        let barometer = track(.barometer, meters: [100, 200], altitudes: [4, 8])
        #expect(Run.smoothedHeights(barometer, fixes: [fix(meters: 0), fix(meters: 300)]) == [4, 8])
    }

    @Test func smoothedHeightsStayOnTheirStretch() {
        let barometer = track(.barometer, meters: [0, 20], altitudes: [1, 2], stretch: 0)
        #expect(Run.smoothedHeights(barometer, fixes: [fix(meters: 10, stretch: 1)]) == [nil])
    }

    @Test func noTrackGivesNoHeights() {
        #expect(Run.smoothedHeights(nil, fixes: [fix(meters: 0), fix(meters: 10)]) == [nil, nil])
    }

    @Test func gpsReachesFurtherThanTheBarometer() {
        #expect(Run.smoothingReach(for: .gps) == 50)
        #expect(Run.smoothingReach(for: .barometer) == 10)
    }

    // MARK: A barometer carried on

    @Test func aContinuedBarometerAddsTheLastKeptHeight() {
        let monitor = AltimeterMonitor(continuing: [AltitudeSample(timestamp: start, relativeMeters: 12)])
        #expect(monitor.latest?.relativeMeters == 12)
        // The new barometer starts from zero, so 3 m on it is 15 m above the run's start.
        monitor.receive(3, at: start.addingTimeInterval(10))
        #expect(monitor.latest?.relativeMeters == 15)
        #expect(monitor.samples.map(\.relativeMeters) == [12, 15])
        // Too soon to keep, but still the newest.
        monitor.receive(1, at: start.addingTimeInterval(12))
        #expect(monitor.latest?.relativeMeters == 13)
        #expect(monitor.samples.map(\.relativeMeters) == [12, 15, 13])
    }

    @Test func aNewBarometerAddsNothing() {
        let monitor = AltimeterMonitor()
        #expect(monitor.latest == nil)
        monitor.receive(3, at: start)
        #expect(monitor.latest?.relativeMeters == 3)
    }

    // MARK: A run silent for a day

    /// A run that started ten minutes before `now` and had a fix a minute before.
    private func runUnderWay(now: Date) -> Run {
        let run = Run(startDate: now.addingTimeInterval(-600))
        context.insert(run)
        run.record(RouteSample(timestamp: now.addingTimeInterval(-60), latitude: 0, longitude: 0, horizontalAccuracy: 5))
        return run
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "HeightSmoothingTests-\(UUID().uuidString)")!
    }

    @Test func anotherDevicesRunSilentForADayIsFinished() {
        let now = Date.now
        let run = runUnderWay(now: now)

        let aDayLater = now.addingTimeInterval(25 * 60 * 60)
        RunRecovery.finishLeftoverRuns(in: context, savingTo: nil, defaults: isolatedDefaults(), now: aDayLater)

        #expect(run.status == .complete)
        #expect(run.endDate == now.addingTimeInterval(-60))
    }

    @Test func anotherDevicesRunSilentForLessThanADayIsLeftAlone() {
        let now = Date.now
        let run = runUnderWay(now: now)

        let laterThatDay = now.addingTimeInterval(23 * 60 * 60)
        RunRecovery.finishLeftoverRuns(in: context, savingTo: nil, defaults: isolatedDefaults(), now: laterThatDay)

        #expect(run.status == .active)
    }
}
