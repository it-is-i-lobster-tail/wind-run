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

    private var total: TimeInterval {
        max(duration, points.last?.activeTime ?? 0, 1)
    }

    /// Ticks every 1, 5, 10, 15, 30 or 60 minutes, whichever keeps the axis to about five labels.
    private var tickSpacing: TimeInterval {
        let choices: [TimeInterval] = [60, 300, 600, 900, 1_800, 3_600]
        return choices.first { total / $0 <= 5 } ?? 7_200
    }

    var body: some View {
        Chart {
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
        .chartXScale(domain: 0...total)
        // Heart rate sits well above zero, so start the axis near the lowest reading.
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .stride(by: tickSpacing)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(RunFormat.duration(seconds))
                    }
                }
            }
        }
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
