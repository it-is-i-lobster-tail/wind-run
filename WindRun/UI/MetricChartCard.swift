import Charts
import SwiftUI

struct DistributionSeries {
    let name: String
    let distribution: EmpiricalDistribution
    let color: Color
    let dash: [CGFloat]

    init(name: String, rawValues: [Double], metric: RunChartMetric, unit: DistanceUnit, color: Color, dash: [CGFloat] = []) {
        self.name = name
        self.color = color
        self.dash = dash
        distribution = EmpiricalDistribution(rawValues.map { metric.measuredValue($0, unit: unit) })
    }
}

enum MetricChartAxis: String {
    case time = "Time", distance = "Distance", reps = "Reps", sections = "Sections"

    func title(for name: String) -> String {
        switch self {
        case .time: "\(name) over time"
        case .distance: "\(name) by distance"
        case .reps: "\(name) by work rep"
        case .sections: "Pace by section"
        }
    }

    func explanation(for metric: RunChartMetric, relativeHeight: Bool) -> String {
        if self == .sections {
            return "Each bar shows a workout section’s average pace. Longer bars mark faster sections."
        }
        if self == .reps {
            switch metric {
            case .pace: return "Each point is one work rep’s average pace. A downward slope means the later reps were slower."
            case .heart: return "Each point is the average heart rate during a work rep. Follow the line to see how your effort changed across reps."
            case .cadence: return "Each point is a work rep’s average steps per minute. Compare the first and last reps to see how your step rate changed."
            case .elevation: return "Each point is a work rep’s average height relative to the start of that run."
            }
        }
        switch metric {
        case .pace: return self == .distance
            ? "Compare pace at the same distance into each run. Higher points mean faster running."
            : "Follow your pace from the start of the run. Higher points mean faster running."
        case .heart: return self == .distance
            ? "Compare heart rate at the same distance into each run. A higher line means more beats per minute."
            : "This line follows your heart rate through the run. Look for where it rose during harder stretches and fell during recovery."
        case .cadence: return "Cadence counts steps per minute across both feet. Follow the line to see where you changed your step rate."
        case .elevation:
            return relativeHeight
                ? "Zero marks your starting elevation. Positive values are above the start and negative values are below it."
                : "The line follows your elevation above sea level. Rising and falling stretches show the climbs and descents."
        }
    }

    func distributionExplanation(for metric: RunChartMetric) -> String {
        switch self {
        case .sections: return "Choose a pace to see what percentage of workout sections averaged that pace or faster. Each section counts once."
        case .reps:
            let threshold = metric == .pace ? "that pace or faster" : "that value or lower"
            return "Choose a \(metric.rawValue.lowercased()) value to see what percentage of work reps averaged \(threshold). Each rep counts once."
        case .time, .distance: return metric.distributionExplanation
        }
    }
}

struct MetricChartCard<Legend: View, Timeline: View>: View {
    let metric: RunChartMetric
    let unit: DistanceUnit
    let name: String
    let axis: MetricChartAxis
    var detail: String? = nil
    var demoName: String? = nil
    var relativeHeight = true
    var hasData = true
    let distributions: () -> [DistributionSeries]
    @ViewBuilder let legend: () -> Legend
    @ViewBuilder let timeline: (Bool) -> Timeline
    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection = 0

    private var title: String {
        if selection == 0 { return axis.title(for: name) }
        return axis == .sections ? "Section pace distribution" : "\(name) distribution"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer(minLength: 4)
                pageKey
                if hasData { ExpandChartButton(title: title) { isExpanded = true } }
            }
            Text(metric.unit(unit) + (selection == 0 ? detail.map { " · " + $0 } ?? "" : ""))
                .font(.caption).foregroundStyle(.secondary)
            graph(expanded: false)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .windRunGlassCard()
        .contentShape(.rect)
        #if DEBUG
        .onAppear { if let demoName, RunDetailDemo.opens(chart: demoName) { isExpanded = true } }
        #endif
        .fullScreenCover(isPresented: $isExpanded) {
            FullScreenChart(title: title, unit: metric.unit(unit), detail: selection == 0 ? detail : nil,
                            supportsZoom: axis != .sections || selection == 1) {
                VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
                    HStack {
                        legend()
                        Spacer()
                        pageKey
                    }
                    graph(expanded: true)
                }
            }
        }
    }

    private func graph(expanded: Bool) -> some View {
        MetricChartPager(selection: $selection, expanded: expanded) { index in
            graphPage(index, expanded: expanded)
                .environment(\.expandRunChart, !expanded && index == 0 && hasData ? $isExpanded : nil)
        }
    }

    private func graphPage(_ index: Int, expanded: Bool) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            if index == 0, axis == .sections {
                timeline(expanded)
                    .contentShape(.rect)
                    .onTapGesture { if !expanded { isExpanded = true } }
            } else if index == 0 {
                timeline(expanded)
            } else if hasData {
                DistributionPlot(metric: metric, unit: unit, axisTitle: name, series: distributions(), expanded: expanded)
            } else {
                Text("No readings for this distribution.").foregroundStyle(.secondary)
            }
            Text(index == 0 ? axis.explanation(for: metric, relativeHeight: relativeHeight) : axis.distributionExplanation(for: metric))
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pageKey: some View {
        Button { advance(1) } label: {
            HStack(spacing: 5) {
                Text(selection == 1 ? "ECDF" : axis.rawValue).font(.caption.weight(.semibold))
                ChartPageDots(count: 2, selection: selection)
            }
            .fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(.quaternary, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) chart view")
        .accessibilityValue(selection == 0 ? "Workout, 1 of 2" : "Cumulative distribution, 2 of 2")
        .accessibilityHint("Double tap to switch views.")
        .accessibilityAdjustableAction { advance(ChartPageSwipe.offset(for: $0)) }
    }

    private func advance(_ offset: Int) {
        withAnimation(reduceMotion ? nil : .snappy) {
            selection = ChartPageSwipe.step(selection, by: offset, count: 2)
        }
    }
}

/// Use the extra width of a landscape chart for readings, leaving more height for the plot.
struct ChartReadouts<Content: View>: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            if verticalSizeClass == .compact {
                HStack(spacing: LayoutMetrics.sectionSpacing) { content }
                    .fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) { content }
        }
    }
}

private struct DistributionPlot: View {
    let metric: RunChartMetric
    let unit: DistanceUnit
    let axisTitle: String
    let series: [DistributionSeries]
    let expanded: Bool
    @State private var threshold: Double?

    var body: some View {
        let low = series.compactMap { $0.distribution.steps.first?.value }.min() ?? 0
        let high = series.compactMap { $0.distribution.steps.last?.value }.max() ?? 1
        let pad = max(1, (high - low) * 0.04)
        let domain = (metric == .elevation ? low - pad : max(0, low - pad))...(high + pad)
        VStack(alignment: .leading, spacing: LayoutMetrics.compactSpacing) {
            ZoomableChart(domain: domain, minimumSpan: 1) { window in
                Chart {
                    ForEach(series.indices, id: \.self) { index in
                        let curve = series[index].distribution
                        if curve.count > 0 {
                            line(x: domain.lowerBound, fraction: 0, seriesIndex: index)
                            ForEach(curve.steps) { step in
                                line(x: step.value, fraction: Double(step.count) / Double(curve.count), seriesIndex: index)
                            }
                            line(x: domain.upperBound, fraction: 1, seriesIndex: index)
                        }
                    }
                    if let threshold {
                        RuleMark(x: .value("Threshold", threshold)).foregroundStyle(.secondary.opacity(0.5))
                    }
                }
                .chartXScale(domain: window)
                .chartYScale(domain: 0.0...1.0)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [0.0, 0.25, 0.5, 0.75, 1.0]) {
                        AxisGridLine()
                        AxisValueLabel(format: FloatingPointFormatStyle<Double>.Percent.percent)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { tick in
                        AxisGridLine()
                        if let x = tick.as(Double.self) { AxisValueLabel { Text(metric.label(x)) } }
                    }
                }
                .chartXAxisLabel("\(axisTitle) (\(metric.unit(unit)))")
                .chartXSelection(value: Binding(get: { threshold }, set: { if let x = $0 { threshold = x.rounded() } }))
            }
            .frame(height: expanded ? nil : 148)
            if let threshold {
                Text("At or below \(metric.label(threshold)) \(metric.unit(unit))").font(.caption.bold())
            }
            ChartReadouts {
                ForEach(series.indices, id: \.self) { index in
                    let curve = series[index].distribution
                    if curve.count == 0 {
                        Text("\(series[index].name) · No data")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if let threshold {
                        let n = curve.count(atOrBelow: threshold)
                        let percent = (Double(n) / Double(curve.count)).formatted(.percent.precision(.fractionLength(0...1)))
                        Text("\(series[index].name) · \(percent) (\(n) of \(curve.count))")
                            .font(.caption)
                    }
                }
            }
        }
    }

    private func line(x: Double, fraction: Double, seriesIndex: Int) -> some ChartContent {
        LineMark(x: .value(metric.rawValue, x), y: .value("Cumulative proportion", fraction),
                 series: .value("Session", seriesIndex))
            .interpolationMethod(.stepEnd)
            .foregroundStyle(series[seriesIndex].color)
            .lineStyle(StrokeStyle(lineWidth: 2.2, dash: series[seriesIndex].dash))
    }
}
