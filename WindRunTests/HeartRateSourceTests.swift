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

    @Test func coachHeartRateIsTheSettingsSwitch() throws {
        let defaults = try #require(UserDefaults(suiteName: "HeartRateSourceTests.\(UUID())"))
        // Off until the runner turns it on, so the coach never claims heart rate that isn't being recorded.
        let fresh = CoachHeartRateStore.load(from: defaults)
        #expect(!fresh.enabled)
        #expect(!fresh.coachingAllowed)
        #expect(fresh.device == .off)

        // Turned on in Settings or on the first-open question: the coach sees it.
        defaults.set(true, forKey: HeartRateMonitor.storageKey)
        #expect(CoachHeartRateStore.load(from: defaults).enabled)
        #expect(CoachHeartRateStore.load(from: defaults).coachingAllowed)

        // Turned off in plan settings: Settings sees it, and the coach's other choices are kept.
        var off = CoachHeartRateStore.load(from: defaults)
        off.enabled = false
        off.useForCoaching = false
        CoachHeartRateStore.save(off, to: defaults)
        #expect(!defaults.bool(forKey: HeartRateMonitor.storageKey))
        #expect(!CoachHeartRateStore.load(from: defaults).enabled)
        #expect(!CoachHeartRateStore.load(from: defaults).useForCoaching)

        // Older saved settings that said on give way to the switch.
        var stale = off
        stale.enabled = true
        defaults.set(try JSONEncoder().encode(stale), forKey: CoachHeartRateStore.storageKey)
        #expect(!CoachHeartRateStore.load(from: defaults).enabled)
    }

    @Test func aStrapBeatsTheWatchWhichBeatsEarbuds() {
        #expect(HeartRateSource.best([.earbuds, .appleWatch]) == .appleWatch)
        #expect(HeartRateSource.best([.earbuds, .strapOrSensor, .appleWatch]) == .strapOrSensor)
        #expect(HeartRateSource.best([.earbuds]) == .earbuds)
        #expect(HeartRateSource.best([]) == nil)
    }
}
