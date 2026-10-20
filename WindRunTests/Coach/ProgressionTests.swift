//
//  ProgressionTests.swift
//  WindRunTests
//

import Foundation
import Testing
@testable import WindRun

/// The path math against the rules' tables: RC-5's long-run path and the Build Distance rows (BD-3d).
@MainActor
struct ProgressionTests {
    let gentle = CycleWeek.cycle(for: .gentle, stepBackEveryThird: false, twoWeekHold: false)
    let steady = CycleWeek.cycle(for: .steady, stepBackEveryThird: false, twoWeekHold: false)
    let ambitious = CycleWeek.cycle(for: .ambitious, stepBackEveryThird: false, twoWeekHold: false)

    func earliest(_ start: Double, _ target: Double, _ cycle: [CycleWeek], taper: Int) -> Int? {
        Progression.earliestLongRunWeeks(from: start, to: target, cycle: cycle, calibrates: true, taperWeeks: taper)
    }

    @Test func newLongestWeeksFollowTenPercentSteps() {
        #expect(Progression.newLongestWeeks(from: 8, to: 10) == 3)
        #expect(Progression.newLongestWeeks(from: 8, to: 16) == 8)
        #expect(Progression.newLongestWeeks(from: 10, to: 10) == 0)
        #expect(Progression.newLongestWeeks(from: 10, to: 11) == 1)
    }

    /// RC-5, the 8 km row: 10K 7 (8/6), half 15 (19/14), half time goal 20 (25/18), marathon 25 (32/23).
    @Test func rc5EightKilometreRow() {
        #expect(earliest(8, 10, steady, taper: 1) == 7)
        #expect(earliest(8, 10, gentle, taper: 1) == 8)
        #expect(earliest(8, 10, ambitious, taper: 1) == 6)
        #expect(earliest(8, 16, steady, taper: 2) == 15)
        #expect(earliest(8, 16, gentle, taper: 2) == 19)
        #expect(earliest(8, 16, ambitious, taper: 2) == 14)
        #expect(earliest(8, 21, steady, taper: 2) == 20)
        #expect(earliest(8, 21, gentle, taper: 2) == 25)
        #expect(earliest(8, 21, ambitious, taper: 2) == 18)
        #expect(earliest(8, 30, steady, taper: 3) == 25)
        #expect(earliest(8, 30, gentle, taper: 3) == 32)
        #expect(earliest(8, 30, ambitious, taper: 3) == 23)
    }

    /// RC-5, the 3 km and 10 km rows at Steady, and "ready" where no N week is needed.
    @Test func rc5OtherRows() {
        #expect(earliest(3, 10, steady, taper: 1) == 22)
        #expect(earliest(3, 16, steady, taper: 2) == 30)
        #expect(earliest(3, 21, steady, taper: 2) == 35)
        #expect(earliest(3, 30, steady, taper: 3) == 42)
        #expect(earliest(10, 10, steady, taper: 1) == nil)
        #expect(earliest(10, 16, steady, taper: 2) == 11)
        #expect(earliest(10, 30, steady, taper: 3) == 22)
    }

    /// RC-11's owner example: from 4.5 km, the half is 24 weeks (likely 28) and the marathon 34 (likely 39).
    @Test func ownerExampleDates() throws {
        let half = try #require(earliest(4.5, 16, steady, taper: 2))
        let marathon = try #require(earliest(4.5, 30, steady, taper: 3))
        #expect(half == 24)
        #expect(Progression.likelyWeeks(earliest: half) == 28)
        #expect(marathon == 34)
        #expect(Progression.likelyWeeks(earliest: marathon) == 39)
    }

    /// Build Distance from a 5 km P-L30 to a 10 km, 21.1 km and 30 km long run, calibration included, no taper.
    @Test func buildDistanceRows() {
        #expect(earliest(5, 10, gentle, taper: 0) == 17)
        #expect(earliest(5, 21.1, gentle, taper: 0) == 33)
        #expect(earliest(5, 30, gentle, taper: 0) == 39)
        #expect(earliest(5, 10, steady, taper: 0) == 13)
        #expect(earliest(5, 21.1, steady, taper: 0) == 25)
        #expect(earliest(5, 30, steady, taper: 0) == 30)
        #expect(earliest(5, 10, ambitious, taper: 0) == 12)
        #expect(earliest(5, 21.1, ambitious, taper: 0) == 23)
        #expect(earliest(5, 30, ambitious, taper: 0) == 27)
    }

    @Test func bufferWeeks() {
        #expect(Progression.bufferWeeks(buildWeeks: 6, recovery: .normal) == 2)
        #expect(Progression.bufferWeeks(buildWeeks: 13, recovery: .normal) == 3)
        #expect(Progression.bufferWeeks(buildWeeks: 13, recovery: .low) == 5)
    }

    @Test func cyclesPerLevel() {
        #expect(gentle == [.newLongest, .heldLongRun, .newLongest, .stepBack])
        #expect(steady == [.newLongest, .newLongest, .stepBack])
        #expect(ambitious == [.newLongest, .newLongest, .newLongest, .stepBack])
        #expect(CycleWeek.cycle(for: .ambitious, stepBackEveryThird: true, twoWeekHold: false) == [.newLongest, .newLongest, .stepBack])
        #expect(CycleWeek.cycle(for: .steady, stepBackEveryThird: false, twoWeekHold: true) == [.newLongest, .heldLongRun, .newLongest, .stepBack])
    }
}
