//
//  RunChartTests.swift
//  Wind Run Tests
//

import CoreLocation
import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import WindRun

/// The rules under the run detail's charts and route map: point spacing and gaps, axis ranges and ticks,
/// and how the route is shaded and cut.
@MainActor
struct RunChartTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    // Each test gets its own store. It has to outlive the models in it.
    private let container = WindRunSchema.makeContainer(inMemory: true)

    /// A fix `meters` north of the start, `time` seconds into the running, on `stretch`.
    private func fix(time: TimeInterval, meters: Double, stretch: Int = 0) -> ActiveFix {
        let sample = RouteSample(timestamp: start.addingTimeInterval(time), latitude: meters / 111_111, longitude: 0)
        container.mainContext.insert(sample)
        return ActiveFix(time: time, meters: meters, stretch: stretch, sample: sample)
    }

    // MARK: Pace and cadence points

    @Test func chartPointsAreTenSecondsApartOnAShortRun() {
        #expect(Run.chartSpacing(span: 1_000) == 10)
        #expect(Run.chartSpacing(span: 4_000) == 10)
    }

    @Test func chartPointsSpreadOutOnALongRun() {
        // Past 4,000 seconds, about 400 points across the run.
        #expect(Run.chartSpacing(span: 8_000) == 20)
    }

    @Test func aLineBreaksOnlyPastTheGap() {
        // 10 × 1.5 for the spacing, plus half the 30 second window.
        #expect(Run.chartWindow == 30)
        #expect(!Run.startsNewChartSegment(at: 40, after: 10, spacing: 10))
        #expect(Run.startsNewChartSegment(at: 40.5, after: 10, spacing: 10))
    }

    @Test func paceAndCadenceSmoothOnePassOverTheirWindowedValues() {
        let distances = [0.0, 50, 100, 125, 200]
        let fixes = distances.enumerated().map { fix(time: Double($0.offset) * 15, meters: $0.element) }
        let pace = Run.paceTimeline(fixes, buffers: ChartPauseBuffers())
        #expect(pace.map(\.activeTime) == [15, 30, 45, 60])
        #expect(pace.map(\.secondsPerKilometer) == [300, 310, 380, 300])

        let run = Run(startDate: start)
        container.mainContext.insert(run)
        run.saveStepCounts([30.0, 60, 60, 30].enumerated().map { index, count in
            let date = start.addingTimeInterval(Double(index) * 15)
            return StepCountSample(start: date, end: date.addingTimeInterval(15), count: count)
        })
        let cadence = run.cadenceSeries(buffers: run.chartPauseBuffers)
        #expect(cadence.map.map(\.stepsPerMinute) == [120, 180, 240, 180])
        #expect(cadence.chart.map(\.stepsPerMinute) == [120, 180, 228, 180])
    }

    // MARK: Axes

    @Test func zoomKeepsThePinchAnchorAtTheSamePosition() {
        let domain = 100.0...180.0
        let zoom = ChartWindow.zoom(domain, by: 2, anchor: 0.25, within: domain, minimumSpan: 10)
        #expect(zoom == 110...150)
        #expect(ChartWindow.zoom(zoom, by: 100, anchor: 0, within: domain, minimumSpan: 10) == 110...120)
        #expect(ChartWindow.zoom(zoom, by: 0.1, anchor: 1, within: domain, minimumSpan: 10) == domain)
    }

    @Test func panningStopsAtTheFirstAndLastRepWithoutChangingZoom() {
        let domain = 1.0...6.0
        #expect(ChartWindow.clamped(start: -3, span: 2, within: domain) == 1...3)
        #expect(ChartWindow.clamped(start: 2.5, span: 2, within: domain) == 2.5...4.5)
        #expect(ChartWindow.clamped(start: 8, span: 2, within: domain) == 4...6)
    }

    @Test func theRangeRoundsOutToWholeSteps() {
        #expect(RunChartAxis.roundedDomain([151, 152], step: 20, fallback: 100...180) == 140...160)
        #expect(RunChartAxis.roundedDomain([305, 361], step: 60, fallback: 240...420) == 300...420)
    }

    @Test func theRangeIsAtLeastOneStepTall() {
        #expect(RunChartAxis.roundedDomain([160, 160], step: 20, fallback: 100...180) == 160...180)
    }

    @Test func withNoValuesTheRangeIsTheFallback() {
        #expect(RunChartAxis.roundedDomain([], step: 60, fallback: 240...420) == 240...420)
        #expect(RunChartAxis.roundedDomain([], step: 20, fallback: 140...180) == 140...180)
    }

    @Test func timeTicksKeepToAboutFiveLabels() {
        #expect(RunChartAxis.tickSpacing(total: 300) == 60)
        #expect(RunChartAxis.tickSpacing(total: 1_800) == 600)
        #expect(RunChartAxis.tickSpacing(total: 20_000) == 7_200)
    }

    @Test func theTimeAxisIsNeverEmpty() {
        #expect(RunChartAxis.total(duration: 0, lastPoint: nil) == 1)
        #expect(RunChartAxis.total(duration: 600, lastPoint: 610) == 610)
        #expect(RunChartAxis.total(duration: 600, lastPoint: 590) == 600)
    }

    @Test func theHeartRateLineStartsGreyOnlyWhenItRunsPastTheSettlingTime() {
        let settling = Run.heartRateSettlingTime

        #expect(HeartRateChart.hasSettlingStretch([
            HeartRatePoint(activeTime: 0, beatsPerMinute: 120),
            HeartRatePoint(activeTime: settling, beatsPerMinute: 150),
        ]))
        #expect(!HeartRateChart.hasSettlingStretch([
            HeartRatePoint(activeTime: 0, beatsPerMinute: 120),
            HeartRatePoint(activeTime: settling - 1, beatsPerMinute: 150),
        ]))
        #expect(!HeartRateChart.hasSettlingStretch([
            HeartRatePoint(activeTime: settling, beatsPerMinute: 150),
            HeartRatePoint(activeTime: settling + 60, beatsPerMinute: 155),
        ]))
        #expect(!HeartRateChart.hasSettlingStretch([]))
    }

    @Test func meanCadenceIsStepsOverRunningTime() {
        #expect(Run.meanCadence(steps: 1_800, seconds: 600) == 180)
        #expect(Run.meanCadence(steps: 1_800, seconds: 0) == nil)
        #expect(Run.meanCadence(steps: nil, seconds: 600) == nil)
    }

    @Test func theWorkBandsAreInTheKeyOnlyWithHardSteps() {
        let easy = RunSection(id: 0, name: "Warm up", isWork: false, startTime: 0, endTime: 600, meters: 1_500)
        let hard = RunSection(id: 1, name: "Work", isWork: true, startTime: 600, endTime: 840, meters: 1_000)

        #expect(ChartLegend.Item.work(in: [easy, hard]) == [.workSections])
        #expect(ChartLegend.Item.work(in: [easy]).isEmpty)
        #expect(ChartLegend.Item.work(in: []).isEmpty)
    }

    // MARK: Route shades

    @Test func eachPaletteHasAShadeForEveryLevel() {
        #expect(RouteShade.paletteSizes.speed == RouteColoring.levels)
        #expect(RouteShade.paletteSizes.grade == RouteColoring.levels)
    }

    @Test func voiceOverStepsUpAndDownThroughTheColorings() {
        #expect(ChartPageSwipe.offset(for: .increment) == 1)
        #expect(ChartPageSwipe.offset(for: .decrement) == -1)
    }

    @Test func paceShadesFillGapsAndSpreadATinyRangeAroundTheMiddle() {
        // Both percentiles land on 3.0, so the half a meter a second spread runs from 2.75 to 3.25.
        #expect(Run.levels(for: [nil, 3.0, nil, 3.2], coloring: .pace) == [4, 4, 4, 7])
    }

    @Test func noValuesMeanNoShades() {
        #expect(Run.levels(for: [nil, nil], coloring: .pace) == nil)
        #expect(Run.levels(for: [], coloring: .grade) == nil)
    }

    @Test func gradeShadesUseAFixedScale() {
        #expect(Run.levels(for: [0, 0.06, -0.06, 0.1], coloring: .grade) == [4, 8, 0, 8])
    }

    @Test func climbNoiseIsTwoMetersForGPSAndOneForTheBarometer() {
        #expect(Run.climbNoise(for: .gps) == 2)
        #expect(Run.climbNoise(for: .barometer) == 1)
    }

    // MARK: Route lines

    @Test func eachSegmentStartsWhereTheLastEnded() {
        let fixes = (0..<4).map { fix(time: Double($0) * 5, meters: Double($0) * 10) }

        let segments = Run.segments(fixes: fixes, levels: [1, 1, 2, 2])

        #expect(segments.map(\.id) == [0, 1])
        #expect(segments.map(\.level) == [1, 2])
        #expect(segments.map(\.coordinates.count) == [3, 2])
        #expect(segments[0].coordinates.last?.latitude == fixes[2].sample.coordinate.latitude)
        #expect(segments[1].coordinates.first?.latitude == fixes[2].sample.coordinate.latitude)
        #expect(segments[1].coordinates.last?.latitude == fixes[3].sample.coordinate.latitude)
    }

    @Test func aShadeOnTheLastFixAloneIsLeftOff() {
        let fixes = (0..<4).map { fix(time: Double($0) * 5, meters: Double($0) * 10) }

        let segments = Run.segments(fixes: fixes, levels: [1, 1, 1, 2])

        // The first segment reaches the last fix, and the one-point tail after it isn't drawn.
        #expect(segments.map(\.level) == [1])
        #expect(segments.map(\.coordinates.count) == [4])
    }

    @Test func mismatchedLevelsGiveNoSegments() {
        let fixes = (0..<3).map { fix(time: Double($0) * 5, meters: Double($0) * 10) }

        #expect(Run.segments(fixes: fixes, levels: [1, 1]).isEmpty)
        #expect(Run.segments(fixes: Array(fixes.prefix(1)), levels: [1]).isEmpty)
    }

    @Test func speedsDontReadAcrossAPause() {
        // 20 m/s before the pause, 2 m/s after it. Read across the pause, fix 3 would be 220 m in 25 seconds.
        let fixes = [
            fix(time: 0, meters: 0),
            fix(time: 5, meters: 100),
            fix(time: 10, meters: 200),
            fix(time: 15, meters: 200, stretch: 1),
            fix(time: 20, meters: 210, stretch: 1),
            fix(time: 25, meters: 220, stretch: 1),
        ]

        #expect(Run.speeds(along: fixes) == [20, 20, 20, 2, 2, 2])
    }

    @Test func aRouteTooShortForTheReachHasNoGrades() {
        let fixes = (0..<3).map { fix(time: Double($0) * 5, meters: Double($0) * 5) }

        let grades = Run.grades(along: fixes, heights: [0, 1, 2])

        #expect(grades.count == 3)
        #expect(grades.allSatisfy { $0 == nil })
    }
}
