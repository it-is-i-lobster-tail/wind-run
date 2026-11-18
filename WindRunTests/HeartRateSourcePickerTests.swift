//
//  HeartRateSourcePickerTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// What's measuring heart rate, worked out from the live readings and Health's records of them.
@MainActor
struct HeartRateSourcePickerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    private func record(_ source: HeartRateSource, at seconds: TimeInterval, _ beatsPerMinute: Double, device: DeviceInfo? = nil) -> HeartRateSourceSample {
        HeartRateSourceSample(source: source, date: start.addingTimeInterval(seconds), beatsPerMinute: beatsPerMinute, device: device)
    }

    @Test func aReadingMatchesWithinThreeSecondsAndHalfABeat() {
        let strap = [record(.strapOrSensor, at: 0, 150)]
        #expect(HeartRateMonitor.match(150, at: start.addingTimeInterval(3), in: strap) == .strapOrSensor)
        #expect(HeartRateMonitor.match(150, at: start.addingTimeInterval(3.01), in: strap) == nil)
        #expect(HeartRateMonitor.match(150.49, at: start, in: strap) == .strapOrSensor)
        #expect(HeartRateMonitor.match(150.5, at: start, in: strap) == nil)
        #expect(HeartRateMonitor.match(150, at: start, in: []) == nil)
    }

    @Test func whenTwoRecordsMatchTheBetterRankedOneWins() {
        let both = [record(.appleWatch, at: 1, 150), record(.strapOrSensor, at: 2, 150)]
        #expect(HeartRateMonitor.match(150, at: start, in: both) == .strapOrSensor)
        let earbudsAndWatch = [record(.earbuds, at: 0, 150), record(.appleWatch, at: 0, 150)]
        #expect(HeartRateMonitor.match(150, at: start, in: earbudsAndWatch) == .appleWatch)
    }

    @Test func theSameReadingIsTheSameEitherWayRound() {
        let a = start
        let b = start.addingTimeInterval(3)
        #expect(HeartRateMonitor.isSameReading(150, at: a, 150.2, at: b))
        #expect(HeartRateMonitor.isSameReading(150.2, at: b, 150, at: a))
        #expect(!HeartRateMonitor.isSameReading(150, at: a, 150, at: start.addingTimeInterval(-3.01)))
        #expect(!HeartRateMonitor.isSameReading(150, at: a, 149.5, at: a))
    }

    @Test func nothingIsKnownUntilSomethingIsSeen() {
        var picker = HeartRateSourcePicker()
        #expect(picker.source == nil)
        #expect(picker.live(150, at: start) == nil)
        #expect(picker.sourcesSeen == 0)

        // The watch starts out as the watch's own.
        var onWatch = HeartRateSourcePicker(initial: .appleWatch)
        #expect(onWatch.live(150, at: start) == .appleWatch)
    }

    @Test func aStrapThatDropsOutHandsOverToTheWatch() {
        var picker = HeartRateSourcePicker()
        _ = picker.saw([record(.strapOrSensor, at: 0, 150), record(.appleWatch, at: 0, 148)])
        #expect(picker.source == .strapOrSensor)
        #expect(picker.sourcesSeen == 2)

        // Still within a minute of the strap's last reading.
        _ = picker.saw([record(.appleWatch, at: 60, 148)])
        #expect(picker.source == .strapOrSensor)

        // More than a minute since the strap's last reading.
        _ = picker.saw([record(.appleWatch, at: 61, 148)])
        #expect(picker.source == .appleWatch)
    }

    @Test func recordsThatMatchTheLiveReadingsWin() {
        var picker = HeartRateSourcePicker()
        #expect(picker.live(150, at: start) == nil)
        // The earbuds' record is this reading; the watch's synced readings aren't.
        _ = picker.saw([record(.earbuds, at: 1, 150), record(.appleWatch, at: 2, 120)])
        #expect(picker.source == .earbuds)

        // A later live reading matched to the earbuds' record already in.
        #expect(picker.live(150, at: start.addingTimeInterval(1)) == .earbuds)

        // The match counts for a minute of records after it.
        _ = picker.saw([record(.appleWatch, at: 60, 120)])
        #expect(picker.source == .earbuds)
        _ = picker.saw([record(.appleWatch, at: 62, 120)])
        #expect(picker.source == .appleWatch)
    }

    @Test func twoSourcesMatchingOneReadingGoToTheBetterRanked() {
        var earbudsFirst = HeartRateSourcePicker()
        _ = earbudsFirst.live(150, at: start)
        _ = earbudsFirst.saw([record(.earbuds, at: 1, 150), record(.appleWatch, at: 1, 150)])
        #expect(earbudsFirst.source == .appleWatch)

        var watchFirst = HeartRateSourcePicker()
        _ = watchFirst.live(150, at: start)
        _ = watchFirst.saw([record(.appleWatch, at: 1, 150), record(.earbuds, at: 1, 150)])
        #expect(watchFirst.source == .appleWatch)

        var separately = HeartRateSourcePicker()
        _ = separately.live(150, at: start)
        _ = separately.saw([record(.earbuds, at: 1, 150)])
        #expect(separately.source == .earbuds)
        _ = separately.saw([record(.appleWatch, at: 2, 150)])
        #expect(separately.source == .appleWatch)
    }

    @Test func eachDeviceIsHandedBackOnce() {
        let strap = DeviceInfo(kind: .strapOrSensor, model: "H10")
        let watch = DeviceInfo(kind: .appleWatch, model: "Watch7,1")
        var picker = HeartRateSourcePicker()
        let first = picker.saw([
            record(.strapOrSensor, at: 0, 150, device: strap),
            record(.appleWatch, at: 0, 148, device: watch),
            record(.strapOrSensor, at: 1, 151, device: strap),
        ])
        #expect(first == [strap, watch])
        #expect(picker.saw([record(.strapOrSensor, at: 2, 152, device: strap)]).isEmpty)
        #expect(picker.saw([record(.appleWatch, at: 3, 149)]).isEmpty)
    }
}
