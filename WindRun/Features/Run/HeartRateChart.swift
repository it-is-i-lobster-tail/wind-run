//
//  HeartRateChart.swift
//  Wind Run
//

import Charts
import SwiftUI

/// Heart rate across the whole run against time spent running, with the mean as a dashed line. The first
/// minutes, which the stats leave out, are grey.
struct HeartRateChart: View {
    let points: [HeartRatePoint]
    let mean: Double
    /// Time spent running in the whole run, so the line spans the chart from start to finish.
    let duration: TimeInterval
    /// A structured run's steps, so its hard steps show as bands.
    var sections: [RunSection] = []

    /// The readings the stats leave out, up to the first one they use, so the grey line meets the red one.
    /// Empty when the run has no readings past the settling time, since the stats then use them all.
    private var settling: [HeartRatePoint] {
        guard let first = points.firstIndex(where: { $0.activeTime >= Run.heartRateSettlingTime }) else { return [] }
        return Array(points[...first])
    }

    private var settled: [HeartRatePoint] {
        let points = points.filter { $0.activeTime >= Run.heartRateSettlingTime }
        return points.isEmpty ? self.points : points
    }

    /// Whether the line starts grey, for the legend under the chart.
    static func hasSettlingStretch(_ points: [HeartRatePoint]) -> Bool {
        guard let first = points.first else { return false }
        return first.activeTime < Run.heartRateSettlingTime && points.contains { $0.activeTime >= Run.heartRateSettlingTime }
    }

    private var total: TimeInterval {
        RunChartAxis.total(duration: duration, lastPoint: points.last?.activeTime)
    }

    /// Heart rate sits well above zero, so the axis spans the readings, to the nearest 20 bpm.
    private var domain: ClosedRange<Double> {
        let readings = points.map(\.beatsPerMinute)
        let low = ((readings.min() ?? 100) / 20).rounded(.down) * 20
        let high = ((readings.max() ?? 180) / 20).rounded(.up) * 20
        return low...max(high, low + 20)
    }

    var body: some View {
        Chart {
            WorkBands(sections: sections)

            ForEach(settling, id: \.self) { point in
                LineMark(
                    x: .value("Time", point.activeTime),
                    y: .value("Heart rate", point.beatsPerMinute),
                    series: .value("Part", "Settling")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.gray)
            }

            ForEach(settled, id: \.self) { point in
                LineMark(
                    x: .value("Time", point.activeTime),
                    y: .value("Heart rate", point.beatsPerMinute),
                    series: .value("Part", "Settled")
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.red)
            }

            // The Avg card below gives the number, so the line goes unlabeled. It leaves out the grey start.
            RuleMark(y: .value("Average", mean))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary)
        }
        .runTimeAxis(total: total)
        .chartYScale(domain: domain)
        .runValueAxis(values: Array(stride(from: domain.lowerBound, through: domain.upperBound, by: 20))) {
            "\(Int($0))"
        }
        .accessibilityLabel("Heart rate over the run")
    }
}

#Preview("Heart rate chart") {
    let points = (0...160).map { step in
        let seconds = Double(step) * 15
        return HeartRatePoint(activeTime: seconds, beatsPerMinute: 135 + seconds / 60 + 6 * sin(seconds / 120))
    }
    return HeartRateChart(points: points, mean: 152, duration: 2_400)
        .frame(height: 200)
        .padding()
}
