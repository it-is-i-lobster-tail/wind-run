//
//  WatchRunDisplayGPSTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The GPS symbol by the Watch run screen's header: location off always shows, a weak signal only while running.
@MainActor
struct WatchRunDisplayGPSTests {
    private func problem(status: RunStatus = .active, gps: GPSSignal = .good, locationOff: Bool = false) -> WatchRunDisplay.GPSProblem? {
        WatchRunDisplay(WatchRunDisplay.Input(
            status: status,
            elapsed: 60,
            meters: 200,
            unit: .kilometers,
            gps: gps,
            locationOff: locationOff
        )).gpsProblem
    }

    @Test func locationOffShowsOffEvenWhenPaused() {
        #expect(problem(status: .paused, locationOff: true) == .off)
        #expect(problem(gps: .weak, locationOff: true) == .off)
        #expect(problem(gps: .good, locationOff: true) == .off)
    }

    @Test func aWeakOrSearchingSignalShowsWhileRunning() {
        #expect(problem(gps: .weak) == .weak)
        #expect(problem(gps: .searching) == .weak)
    }

    @Test func noGPSWarningWhilePausedOrGood() {
        #expect(problem(status: .paused, gps: .weak) == nil)
        #expect(problem(status: .paused, gps: .searching) == nil)
        #expect(problem(gps: .good) == nil)
    }

    @Test func gpsProblemSymbols() {
        #expect(WatchRunDisplay.GPSProblem.off.symbol == "location.slash.fill")
        #expect(WatchRunDisplay.GPSProblem.off.spoken == "No GPS")
        #expect(WatchRunDisplay.GPSProblem.weak.symbol == "location")
        #expect(WatchRunDisplay.GPSProblem.weak.spoken == "GPS weak")
    }
}
