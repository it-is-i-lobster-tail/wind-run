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

    /// Every chart's value labels take this width at the default text size, so the plot areas, and the
    /// bands in them, line up. It grows with the text size, the same for every chart.
    static let valueLabelWidth: CGFloat = 44

    /// Ticks every 15 or 30 seconds, or 1, 2, 5, 10, 15, 30 or 60 minutes, whichever keeps the axis to about five
    /// labels. The seconds and 2 minutes are for a chart zoomed in on a few minutes.
    static func tickSpacing(total: TimeInterval) -> TimeInterval {
        let choices: [TimeInterval] = [15, 30, 60, 120, 300, 600, 900, 1_800, 3_600]
        return choices.first { total / $0 <= 5 } ?? 7_200
    }

    /// The values' range widened to whole steps either side, at least one step tall. With no values, the
    /// fallback widened the same way.
    static func roundedDomain(_ values: [Double], step: Double, fallback: ClosedRange<Double>) -> ClosedRange<Double> {
        let low = ((values.min() ?? fallback.lowerBound) / step).rounded(.down) * step
        let high = ((values.max() ?? fallback.upperBound) / step).rounded(.up) * step
        return low...max(high, low + step)
    }
}

extension EnvironmentValues {
    /// How many value labels a run chart aims for down its side, when it has more height than on the run page,
    /// such as full screen. Unset, each chart uses the few that suit its card.
    @Entry var runChartValueLabels: Int? = nil

    /// Whether a run chart zooms in on part of the run with two fingers, then moves along it with one. Full
    /// screen only: on the run page a drag scrolls the page.
    @Entry var runChartZooms = false
}

extension View {
    /// Time labels along the bottom, "5:00", "10:00" and so on. Full screen, the time axis also zooms.
    func runTimeAxis(total: TimeInterval) -> some View {
        modifier(RunTimeAxis(total: total))
    }

    /// Value labels down the side at a fixed width, so the charts stacked on the page line up.
    func runValueAxis(values: [Double], label: @escaping (Double) -> String) -> some View {
        modifier(RunValueAxis(values: values, label: label))
    }
}

/// The time axis, from the start to the end of the running. Where zooming is on, two fingers spread or pinch
/// the part of the run showing, around the point between them, one finger drags it along the run, and a double
/// tap shows the whole run again. The chart draws the run under a window it moves itself, rather than scrolling,
/// so the line, the bands and the labels always fill the plot together.
private struct RunTimeAxis: ViewModifier {
    let total: TimeInterval

    @Environment(\.runChartZooms) private var zooms
    /// How many times closer than the whole run.
    @State private var zoom: Double = Self.initialZoom
    /// The zoom when the current pinch began.
    @State private var pinchStartZoom: Double?
    /// The time at the chart's left edge.
    @State private var start: TimeInterval = 0
    /// The left edge when the current drag began.
    @State private var dragStartTime: TimeInterval?
    /// The chart's width, to turn a drag into time.
    @State private var width: CGFloat = 1

    @ScaledMetric(relativeTo: .caption2) private var valueLabelWidth = RunChartAxis.valueLabelWidth

    /// The part of the run showing never gets shorter than this.
    private static let shortestVisible: TimeInterval = 60

    private var maximumZoom: Double { max(total / Self.shortestVisible, 1) }

    private var visibleLength: TimeInterval { zooms ? total / zoom : total }

    /// The part of the run on screen.
    private var window: ClosedRange<TimeInterval> {
        zooms ? start...(start + visibleLength) : 0...total
    }

    /// A label at each round time in the window.
    private var ticks: [TimeInterval] {
        let spacing = RunChartAxis.tickSpacing(total: visibleLength)
        let first = (window.lowerBound / spacing).rounded(.up) * spacing
        return Array(stride(from: first, through: window.upperBound, by: spacing))
    }

    private static var initialZoom: Double {
        #if DEBUG
        RunDetailDemo.zoom ?? 1
        #else
        1
        #endif
    }

    func body(content: Content) -> some View {
        let axis = content
            .chartXScale(domain: window)
            .chartXAxis {
                AxisMarks(values: ticks) { value in
                    AxisGridLine()
                    // Centered under its gridline.
                    AxisValueLabel(anchor: .top) {
                        if let seconds = value.as(Double.self) {
                            Text(RunFormat.duration(seconds))
                        }
                    }
                }
            }
        if zooms {
            axis
                // What lies outside the window stays out of sight.
                .chartPlotStyle { $0.clipped() }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .contentShape(.rect)
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            let from = pinchStartZoom ?? zoom
                            if pinchStartZoom == nil { pinchStartZoom = zoom }
                            setZoom(from * value.magnification, around: value.startAnchor.x)
                        }
                        .onEnded { _ in
                            pinchStartZoom = nil
                            Trace.changed("Full screen chart", "Zoom", to: (zoom * 10).rounded() / 10)
                        }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { value in
                            // Two fingers are zooming; one moves the window.
                            guard pinchStartZoom == nil, zoom > 1 else { return }
                            let from = dragStartTime ?? start
                            if dragStartTime == nil { dragStartTime = start }
                            // Content follows the finger: a drag to the right shows earlier in the run.
                            let plotWidth = max(width - valueLabelWidth, 1)
                            setStart(from - Double(value.translation.width / plotWidth) * visibleLength)
                        }
                        .onEnded { _ in dragStartTime = nil }
                )
                .onTapGesture(count: 2) {
                    guard zoom > 1 else { return }
                    Trace.tap("Full screen chart", "Show whole run")
                    withAnimation { setZoom(1, around: 0.5) }
                }
                .onAppear { setZoom(zoom, around: 0.5) }
        } else {
            axis
        }
    }

    /// Zooms to `newZoom`, keeping the time at `anchor` (0 at the left edge, 1 at the right) where it is.
    private func setZoom(_ newZoom: Double, around anchor: CGFloat) {
        let anchor = min(max(Double(anchor), 0), 1)
        let pinned = start + visibleLength * anchor
        zoom = min(max(newZoom, 1), maximumZoom)
        setStart(pinned - visibleLength * anchor)
    }

    /// Moves the left edge, keeping the window inside the run.
    private func setStart(_ time: TimeInterval) {
        start = min(max(time, 0), total - visibleLength)
    }
}

/// The value labels at a width that scales with the text, so "10:00" isn't cut to "1…" at large sizes.
private struct RunValueAxis: ViewModifier {
    let values: [Double]
    let label: (Double) -> String

    @ScaledMetric(relativeTo: .caption2) private var width = RunChartAxis.valueLabelWidth

    func body(content: Content) -> some View {
        let width = width
        content.chartYAxis {
            AxisMarks(values: values) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(label(number))
                            .frame(width: width, alignment: .leading)
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

/// The dashed line across a chart at its average.
struct AverageRule: ChartContent {
    let value: Double

    var body: some ChartContent {
        RuleMark(y: .value("Average", value))
            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            .foregroundStyle(.secondary)
    }
}

/// What a chart's shading and colors mean, under the chart.
struct ChartLegend: View {
    enum Item: Hashable {
        /// The bands where the hard steps were.
        case workSections
        /// The grey start of the heart rate line, which the stats leave out.
        case heartRateSettling

        /// The work bands' entry when the run had hard steps, or nothing.
        static func work(in sections: [RunSection]) -> [Item] {
            sections.contains(where: \.isWork) ? [.workSections] : []
        }
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
    @Environment(\.runChartValueLabels) private var valueLabels

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
        unit.perUnit(secondsPerKilometer)
    }

    /// Whole minutes either side of the fastest and slowest pace.
    private var domain: ClosedRange<Double> {
        RunChartAxis.roundedDomain(points.map { perUnit($0.secondsPerKilometer) }, step: 60, fallback: 240...420)
    }

    /// A label every minute, or every two or five when the range is wide, so there are about four. Given
    /// more height, every half minute when that fits.
    private var ticks: [Double] {
        let target = Double(valueLabels ?? 4)
        let choices: [Double] = target > 4 ? [30, 60, 120, 300] : [60, 120, 300]
        let step = choices.first { (domain.upperBound - domain.lowerBound) / $0 <= target } ?? 600
        return Array(stride(from: domain.lowerBound, through: domain.upperBound, by: step))
    }

    var body: some View {
        Chart {
            WorkBands(sections: sections)

            ForEach(points, id: \.self) { point in
                // Each stretch between stops is its own line, so a stop shows as a gap rather than a
                // steady pace that never happened.
                LineMark(
                    x: .value("Time", point.activeTime),
                    y: .value("Pace", -perUnit(point.secondsPerKilometer)),
                    series: .value("Stretch", point.segment)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)
            }

            if let average, domain.contains(perUnit(average)) {
                AverageRule(value: -perUnit(average))
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
    @Environment(\.runChartValueLabels) private var valueLabels

    let points: [ElevationPoint]
    let duration: TimeInterval
    var sections: [RunSection] = []
    let unit: DistanceUnit

    private var total: TimeInterval {
        RunChartAxis.total(duration: duration, lastPoint: points.last?.activeTime)
    }

    private func height(_ meters: Double) -> Double {
        unit.height(fromMeters: meters)
    }

    /// Room above and below the profile, so a gentle hill doesn't fill the chart like a mountain.
    private var domain: ClosedRange<Double> {
        let heights = points.map { height($0.meters) }
        let low = heights.min() ?? 0
        let high = heights.max() ?? 0
        let padding = max((high - low) * 0.25, unit == .miles ? 30 : 10)
        return (low - padding)...(high + padding)
    }

    /// Three round heights across the chart, or more when it's given the height.
    private var ticks: [Double] {
        let span = domain.upperBound - domain.lowerBound
        let target = Double(valueLabels ?? 3)
        let step = [5.0, 10, 20, 25, 50, 100, 200, 500].first { span / $0 <= target } ?? 1_000
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
    @Environment(\.runChartValueLabels) private var valueLabels

    let points: [CadencePoint]
    let mean: Double?
    let duration: TimeInterval
    var sections: [RunSection] = []

    private var total: TimeInterval {
        RunChartAxis.total(duration: duration, lastPoint: points.last?.activeTime)
    }

    /// Cadence sits well above zero, so the axis spans the readings, to the nearest 20 steps a minute.
    private var domain: ClosedRange<Double> {
        RunChartAxis.roundedDomain(points.map(\.stepsPerMinute), step: 20, fallback: 140...180)
    }

    /// A label every 20 steps a minute, or every 40 when the range is wide, so there are about four. Given
    /// more height, every 10 when that fits.
    private var ticks: [Double] {
        let target = Double(valueLabels ?? 4)
        let choices: [Double] = target > 4 ? [10, 20] : [20]
        let step = choices.first { (domain.upperBound - domain.lowerBound) / $0 <= target } ?? 40
        return Array(stride(from: domain.lowerBound, through: domain.upperBound, by: step))
    }

    var body: some View {
        Chart {
            WorkBands(sections: sections)

            ForEach(points, id: \.self) { point in
                LineMark(
                    x: .value("Time", point.activeTime),
                    y: .value("Cadence", point.stepsPerMinute),
                    series: .value("Stretch", point.segment)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)
            }

            if let mean, domain.contains(mean) {
                AverageRule(value: mean)
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
