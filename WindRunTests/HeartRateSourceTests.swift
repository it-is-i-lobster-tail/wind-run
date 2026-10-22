//
//  HeartRateSourceTests.swift
//  Wind Run Tests
//

import Foundation
import SwiftData
import Testing
@testable import WindRun

/// The runner never picks a heart-rate source: each reading says what measured it, and the best wins.
@MainActor
struct HeartRateSourceTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let container = WindRunSchema.makeContainer(inMemory: true)

    @Test func readingsSayWhatMeasuredThem() {
        #expect(HeartRateSource(deviceName: "AirPods Pro", deviceModel: "0x2027", manufacturer: "Apple Inc.", productType: "iPhone17,1") == .earbuds)
        #expect(HeartRateSource(deviceName: "Powerbeats Pro 2", deviceModel: nil, manufacturer: "Beats", productType: "iPhone17,1") == .earbuds)
        // A strap's readings are its own even when the watch passes them on.
        #expect(HeartRateSource(deviceName: "Polar H10 1A2B3C4D", deviceModel: "H10", manufacturer: "Polar Electro Oy", productType: "Watch7,1") == .strapOrSensor)
        #expect(HeartRateSource(deviceName: "Apple Watch", deviceModel: "Watch", manufacturer: "Apple Inc.", productType: "Watch7,1") == .appleWatch)
        #expect(HeartRateSource(deviceName: nil, deviceModel: nil, manufacturer: nil, productType: "Watch7,1") == .appleWatch)
        #expect(HeartRateSource(deviceName: "iPhone", deviceModel: "iPhone", manufacturer: "Apple Inc.", productType: "iPhone17,1") == nil)
        #expect(HeartRateSource(deviceName: nil, deviceModel: nil, manufacturer: nil, productType: nil) == nil)
    }

    @Test func heartRateIsOnUntilTheRunnerTurnsItOff() throws {
        let defaults = try #require(UserDefaults(suiteName: "HeartRateSourceTests.\(UUID())"))
        let fresh = CoachHeartRateStore.load(from: defaults)
        #expect(fresh.enabled)
        #expect(fresh.coachingAllowed)
        #expect(fresh.device == .off)

        var off = fresh
        off.enabled = false
        CoachHeartRateStore.save(off, to: defaults)
        #expect(!CoachHeartRateStore.load(from: defaults).enabled)
    }

    @Test func aStrapBeatsTheWatchWhichBeatsEarbuds() {
        #expect(HeartRateSource.best([.earbuds, .appleWatch]) == .appleWatch)
        #expect(HeartRateSource.best([.earbuds, .strapOrSensor, .appleWatch]) == .strapOrSensor)
        #expect(HeartRateSource.best([.earbuds]) == .earbuds)
        #expect(HeartRateSource.best([]) == nil)
    }

    @Test func theRunReadsOnlyItsBestSource() {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        run.record(HeartRateSample(timestamp: start.addingTimeInterval(5), beatsPerMinute: 120, source: .earbuds))
        run.record(HeartRateSample(timestamp: start.addingTimeInterval(10), beatsPerMinute: 140, source: .strapOrSensor))
        run.record(HeartRateSample(timestamp: start.addingTimeInterval(15), beatsPerMinute: 125, source: .earbuds))
        run.record(HeartRateSample(timestamp: start.addingTimeInterval(20), beatsPerMinute: 142, source: .strapOrSensor))

        let reading = RunHeartRateReading(run)
        #expect(reading.source == .chestStrap)
        #expect(reading.samples.map(\.beatsPerMinute) == [140, 142])
    }

    @Test func readingsBeforeTheOnlySourceWasFoundCountAsItsOwn() {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        run.record(HeartRateSample(timestamp: start.addingTimeInterval(5), beatsPerMinute: 120))
        run.record(HeartRateSample(timestamp: start.addingTimeInterval(10), beatsPerMinute: 130, source: .appleWatch))

        let reading = RunHeartRateReading(run)
        #expect(reading.source == .appleWatch)
        #expect(reading.samples.count == 2)
    }

    @Test func olderRunsReadWithThePickedSource() throws {
        let run = Run(startDate: start)
        container.mainContext.insert(run)
        for second in stride(from: 0, to: 600, by: 5) {
            run.record(HeartRateSample(timestamp: start.addingTimeInterval(TimeInterval(second)), beatsPerMinute: 140))
        }
        run.finish(at: start.addingTimeInterval(600))
        #expect(RunHeartRateReading(run).source == nil)
        let picked = try #require(LoggedRun(run, track: nil, heartRateSettings: HeartRateSettings(device: .chestStrap)).heartRate)
        #expect(picked.source == .chestStrap)
        let off = try #require(LoggedRun(run, track: nil, heartRateSettings: HeartRateSettings(device: .chestStrap, enabled: false)).heartRate)
        #expect(off.source == .off)
    }
}
