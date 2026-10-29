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
}
