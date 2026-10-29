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

    /// Every chart's value labels take this width, so the plot areas, and the bands in them, line up.
    static let valueLabelWidth: CGFloat = 44

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
                    // Centered under its gridline.
                    AxisValueLabel(anchor: .top) {
                        if let seconds = value.as(Double.self) {
                            Text(RunFormat.duration(seconds))
                        }
                    }
                }
            }
    }

    /// Value labels down the side at a fixed width, so the charts stacked on the page line up.
    func runValueAxis(values: [Double], label: @escaping (Double) -> String) -> some View {
        chartYAxis {
            AxisMarks(values: values) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(label(number))
                            .frame(width: RunChartAxis.valueLabelWidth, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// Pale bands behind a chart where the hard steps were, so each rep shows up in every chart.
struct WorkBands: ChartContent {
    static let fill = Color.accentColor.opacity(0.12)

    let sections: [RunSection]

    var body: some ChartContent {
        ForEach(sections.filter(\.isWork)) { section in
            RectangleMark(
                xStart: .value("Start", section.startTime),
                xEnd: .value("End", section.endTime)
            )
            .foregroundStyle(Self.fill)
        }
    }
}

/// What a chart's shading and colors mean, under the chart.
struct ChartLegend: View {
    enum Item: Hashable {
        /// The bands where the hard steps were.
        case workSections
        /// The grey start of the heart rate line, which the stats leave out.
        case heartRateSettling
    }

    let items: [Item]

    var body: some View {
        // Side by side, or one under the other when the text is too big to fit.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: LayoutMetrics.sectionSpacing) { entries }
            VStack(alignment: .leading, spacing: 4) { entries }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var entries: some View {
        ForEach(items, id: \.self) { item in
            HStack(spacing: 6) {
                swatch(for: item)
                    .accessibilityHidden(true)
                Text(label(for: item))
            }
        }
    }

    private func label(for item: Item) -> String {
        switch item {
        case .workSections: "Work sections"
        case .heartRateSettling:
            "First \(Int(Run.heartRateSettlingTime / 60)) min, not in stats"
        }
    }

    @ViewBuilder
    private func swatch(for item: Item) -> some View {
        switch item {
        case .workSections:
            RoundedRectangle(cornerRadius: 2)
                .fill(WorkBands.fill)
                // A faint edge, so the pale fill still reads at this size.
                .overlay { RoundedRectangle(cornerRadius: 2).strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1) }
                .frame(width: 14, height: 10)
        case .heartRateSettling:
            Capsule()
                .fill(.gray)
                .frame(width: 14, height: 3)
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

    /// Whole minutes either side of the fastest and slowest pace.
    private var domain: ClosedRange<Double> {
        let paces = points.map { perUnit($0.secondsPerKilometer) }
        let fastest = ((paces.min() ?? 240) / 60).rounded(.down) * 60
        let slowest = ((paces.max() ?? 420) / 60).rounded(.up) * 60
        return fastest...max(slowest, fastest + 60)
    }

    /// A label every minute, or every two or five when the range is wide, so there are about four.
    private var ticks: [Double] {
        let step = [60.0, 120, 300].first { (domain.upperBound - domain.lowerBound) / $0 <= 4 } ?? 600
        return Array(stride(from: domain.lowerBound, through: domain.upperBound, by: step))
    }

    var body: some View {
        Chart {
            WorkBands(sections: sections)

            ForEach(points, id: \.self) { point in
                LineMark(
                    x: .value("Time", point.activeTime),
                    y: .value("Pace", -perUnit(point.secondsPerKilometer))
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)
            }

            if let average, domain.contains(perUnit(average)) {
                RuleMark(y: .value("Average", -perUnit(average)))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
        }
        .runTimeAxis(total: total)
        // Faster is better, so it goes at the top: pace is drawn below zero, so the smallest is highest.
        .chartYScale(domain: -domain.upperBound...(-domain.lowerBound))
        .runValueAxis(values: ticks.map { -$0 }) { RunFormat.duration(-$0) }
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

    /// Three round heights across the chart.
    private var ticks: [Double] {
        let span = domain.upperBound - domain.lowerBound
        let step = [5.0, 10, 20, 25, 50, 100, 200, 500].first { span / $0 <= 3 } ?? 1_000
        let first = (domain.lowerBound / step).rounded(.up) * step
        return Array(stride(from: first, through: domain.upperBound, by: step))
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
        .runValueAxis(values: ticks) { "\(Int($0.rounded()))" }
        .accessibilityLabel("Elevation over the run")
    }
}

/// Steps a minute across the run against time spent running, with the mean dashed.
struct CadenceChart: View {
    let points: [CadencePoint]
    let mean: Double?
    let duration: TimeInterval
    var sections: [RunSection] = []

    private var total: TimeInterval {
        RunChartAxis.total(duration: duration, lastPoint: points.last?.activeTime)
    }

    /// Cadence sits well above zero, so the axis spans the readings, to the nearest 20 steps a minute.
    private var domain: ClosedRange<Double> {
        let rates = points.map(\.stepsPerMinute)
        let low = ((rates.min() ?? 140) / 20).rounded(.down) * 20
        let high = ((rates.max() ?? 180) / 20).rounded(.up) * 20
        return low...max(high, low + 20)
    }

    /// A label every 20 steps a minute, or every 40 when the range is wide, so there are about four.
    private var ticks: [Double] {
        let step = (domain.upperBound - domain.lowerBound) / 20 <= 4 ? 20.0 : 40
        return Array(stride(from: domain.lowerBound, through: domain.upperBound, by: step))
    }

    var body: some View {
        Chart {
            WorkBands(sections: sections)

            ForEach(points, id: \.self) { point in
                LineMark(
                    x: .value("Time", point.activeTime),
                    y: .value("Cadence", point.stepsPerMinute)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)
            }

            if let mean, domain.contains(mean) {
                RuleMark(y: .value("Average", mean))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.secondary)
            }
        }
        .runTimeAxis(total: total)
        .chartYScale(domain: domain)
        .runValueAxis(values: ticks) { "\(Int($0))" }
        .accessibilityLabel("Cadence over the run")
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
