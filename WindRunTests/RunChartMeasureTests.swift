//
//  RunChartMeasureTests.swift
//  Wind Run Tests
//

import Foundation
import Testing
@testable import WindRun

/// The measuring line on the run's time charts: which reading it shows and how it's labeled.
struct RunChartMeasureTests {
    private let points = [0.0, 10, 20, 30, 100, 110].map { HeartRatePoint(activeTime: $0, beatsPerMinute: 120 + $0) }

    @Test func picksTheClosestReading() {
        #expect(RunChartMeasure.nearest(points, to: 14, at: \.activeTime)?.activeTime == 10)
        #expect(RunChartMeasure.nearest(points, to: 16, at: \.activeTime)?.activeTime == 20)
        #expect(RunChartMeasure.nearest(points, to: -5, at: \.activeTime)?.activeTime == 0)
        #expect(RunChartMeasure.nearest(points, to: 130, at: \.activeTime)?.activeTime == 110)
    }

    @Test func aGapInTheReadingsReadsAsNothing() {
        // 65 s is 35 s from both 30 and 100, past the reach.
        #expect(RunChartMeasure.nearest(points, to: 65, at: \.activeTime) == nil)
        #expect(RunChartMeasure.nearest(points, to: 150, at: \.activeTime) == nil)
        #expect(RunChartMeasure.nearest([HeartRatePoint](), to: 0, at: \.activeTime) == nil)
    }

    @Test func labelsTimeAndReading() {
        #expect(RunChartMeasure.label(time: 754.6, reading: "152 bpm") == "12:34 · 152 bpm")
        #expect(RunChartMeasure.label(time: 754, reading: nil) == "12:34")
    }
}
