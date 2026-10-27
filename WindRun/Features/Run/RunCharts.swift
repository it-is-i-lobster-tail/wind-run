//
//  RunCharts.swift
//  Wind Run
//

import Charts
import SwiftUI

/// What the run's charts share, so pace, heart rate and elevation line up one above the other.
enum RunChartAxis {
    /// The time axis runs from the start to the end of the time spent running.
    static func total(duration: TimeInterval, lastPoint: TimeInterval?) -> TimeInterval {
        max(duration, lastPoint ?? 0, 1)
    }

    /// Ticks every 1, 5, 10, 15, 30 or 60 minutes, whichever keeps the axis to about five labels.
    static func tickSpacing(total: TimeInterval) -> TimeInterval {
        let choices: [TimeInterval] = [60, 300, 600, 900, 1_800, 3_600]
        return choices.first { total / $0 <= 5 } ?? 7_200
    }
}

extension View {
    /// Time labels along the bottom, "5:00", "10:00" and so on.
    func runTimeAxis(total: TimeInterval) -> some View {
        chartXScale(domain: 0...total)
            .chartXAxis {
                AxisMarks(values: .stride(by: RunChartAxis.tickSpacing(total: total))) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let seconds = value.as(Double.self) {
                            Text(RunFormat.duration(seconds))
                        }
                    }
                }
            }
    }
}

/// Pale bands behind a chart where the hard steps were, so each rep shows up in every chart.
struct WorkBands: ChartContent {
    let sections: [RunSection]

    var body: some ChartContent {
        ForEach(sections.filter(\.isWork)) { section in
            RectangleMark(
                xStart: .value("Start", section.startTime),
                xEnd: .value("End", section.endTime)
            )
            .foregroundStyle(Color.accentColor.opacity(0.12))
        }
    }
}

/// Pace across the run against time spent running, faster higher up, with the average dashed.
struct PaceChart: View {
    let points: [PacePoint]
    /// Seconds per kilometer for the whole run.
    let average: TimeInterval?
    let duration: TimeInterval
    var sections: [RunSection] = []
    let unit: DistanceUnit

    private var total: TimeInterval {
        RunChartAxis.total(duration: duration, lastPoint: points.last?.activeTime)
    }

    /// Pace in seconds per the runner's unit, which is what the axis shows.
    private func perUnit(_ secondsPerKilometer: Double) -> Double {
        secondsPerKilometer * unit.meters / 1_000
    }

    var body: some View {
        Chart {
            WorkBands(sections: sections)

            ForEach(points, id: \.self) { point in
                LineMark(
                    x: .value("Time", point.activeTime),
                    y: .value("Pace", perUnit(point.secondsPerKilometer))
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)
            }

            if let average {
                RuleMark(y: .value("Average", perUnit(average)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
        }
        .runTimeAxis(total: total)
        // Faster is better, so it goes at the top.
        .chartYScale(domain: .automatic(includesZero: false, reversed: true))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(RunFormat.duration(seconds))
                    }
                }
            }
        }
        .accessibilityLabel("Pace over the run")
    }
}

/// Height above sea level across the run against time spent running.
struct ElevationChart: View {
    let points: [ElevationPoint]
    let duration: TimeInterval
    var sections: [RunSection] = []
    let unit: DistanceUnit

    private var total: TimeInterval {
        RunChartAxis.total(duration: duration, lastPoint: points.last?.activeTime)
    }

    private func height(_ meters: Double) -> Double {
        unit == .miles ? meters / 0.3048 : meters
    }

    /// Room above and below the profile, so a gentle hill doesn't fill the chart like a mountain.
    private var domain: ClosedRange<Double> {
        let heights = points.map { height($0.meters) }
        let low = heights.min() ?? 0
        let high = heights.max() ?? 0
        let padding = max((high - low) * 0.25, unit == .miles ? 30 : 10)
        return (low - padding)...(high + padding)
    }

    var body: some View {
        Chart {
            WorkBands(sections: sections)

            ForEach(points, id: \.self) { point in
                AreaMark(
                    x: .value("Time", point.activeTime),
                    yStart: .value("Base", domain.lowerBound),
                    yEnd: .value("Elevation", height(point.meters))
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.secondary.opacity(0.25))

                LineMark(
                    x: .value("Time", point.activeTime),
                    y: .value("Elevation", height(point.meters))
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.secondary)
            }
        }
        .runTimeAxis(total: total)
        .chartYScale(domain: domain)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let meters = value.as(Double.self) {
                        Text("\(Int(meters.rounded())) \(unit == .miles ? "ft" : "m")")
                    }
                }
            }
        }
        .accessibilityLabel("Elevation over the run")
    }
}

#Preview("Pace and elevation") {
    let pace = (0...240).map { step in
        let seconds = Double(step) * 10
        return PacePoint(activeTime: seconds, secondsPerKilometer: 330 + 60 * sin(seconds / 200))
    }
    let elevation = (0...240).map { step in
        let seconds = Double(step) * 10
        return ElevationPoint(activeTime: seconds, meters: 60 + 9 * sin(seconds / 300))
    }
    return VStack(spacing: 24) {
        PaceChart(points: pace, average: 330, duration: 2_400, unit: .kilometers)
            .frame(height: 180)
        ElevationChart(points: elevation, duration: 2_400, unit: .kilometers)
            .frame(height: 120)
    }
    .padding()
}
