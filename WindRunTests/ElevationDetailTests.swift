//
//  ElevationDetailTests.swift
//  Wind Run Tests
//

import Testing
@testable import WindRun

@MainActor
struct ElevationDetailTests {
    private static let profile = [ElevationPoint(activeTime: 0, meters: 15.8), ElevationPoint(activeTime: 60, meters: 40)]

    @Test func showsTheStartingHeightBeforeTheClimbAndDrop() {
        let summary = ElevationSummary(gain: 36.6, loss: 12.2, profile: Self.profile)
        #expect(RunDetailView.elevationDetail(summary, unit: .miles) == "Start 52 ft  +120 ft  −40 ft")
        #expect(RunDetailView.elevationDetail(summary, unit: .kilometers) == "Start 16 m  +37 m  −12 m")
    }

    @Test func barometerOnlyRunsShowJustTheClimbAndDrop() {
        let summary = ElevationSummary(gain: 36.6, loss: 12.2, profile: Self.profile, isRelative: true)
        #expect(RunDetailView.elevationDetail(summary, unit: .miles) == "+120 ft  −40 ft")
    }
}
