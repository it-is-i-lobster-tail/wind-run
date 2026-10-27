//
//  HeartRateChart.swift
//  Wind Run
//

import Charts
import SwiftUI

/// Heart rate across the whole run against time spent running, with the mean as a dashed line.
struct HeartRateChart: View {
    let points: [HeartRatePoint]
    let mean: Double
    /// Time spent running in the whole run, so the line spans the chart from start to finish.
    let duration: TimeInterval
    /// A structured run's steps, so its hard steps show as bands.
    var sections: [RunSection] = []

    private var total: TimeInterval {
        RunChartAxis.total(duration: duration, lastPoint: points.last?.activeTime)
    }

    var body: some View {
        Chart {
            WorkBands(sections: sections)

            ForEach(points, id: \.self) { point in
                LineMark(
                    x: .value("Time", point.activeTime),
                    y: .value("Heart rate", point.beatsPerMinute)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.red)
            }

            // The Avg card below gives the number, so the line goes unlabeled.
            RuleMark(y: .value("Average", mean))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary)
        }
        .runTimeAxis(total: total)
        // Heart rate sits well above zero, so start the axis near the lowest reading.
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityLabel("Heart rate over the run")
    }
}

#Preview("Heart rate chart") {
    let points = (0...120).map { step in
        let seconds = Double(step) * 15
        return HeartRatePoint(activeTime: seconds, beatsPerMinute: 135 + seconds / 60 + 6 * sin(seconds / 120))
    }
    return HeartRateChart(points: points, mean: 150, duration: 1_800)
        .frame(height: 200)
        .padding()
}
