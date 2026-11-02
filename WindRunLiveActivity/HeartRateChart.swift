//
//  HeartRateChart.swift
//  Wind Run Live Activity
//

import Charts
import SwiftUI

/// A line of heart rate over the last five minutes, with a dot on the newest reading.
struct HeartRateChart: View {
    let window: HeartRateWindow
    /// When the run started. Early in a run the line starts here, so it fills the width.
    var runStart: Date?
    var lineWidth: CGFloat = 2.5

    private var points: [HeartRateWindow.Point] { window.points }

    /// A little room above and below the line, and a sensible range before any readings arrive.
    private var range: ClosedRange<Int> {
        let values = points.map(\.beatsPerMinute)
        guard let low = values.min(), let high = values.max() else { return 60...180 }
        let padding = max(5, (high - low) / 5)
        return max(0, low - padding)...(high + padding)
    }

    private var timeSpan: ClosedRange<Date> {
        let start = max(window.start, runStart ?? window.start)
        // Right at the start there's no time to show yet, so keep the full five minutes.
        return start < window.end ? start...window.end : window.start...window.end
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Heart rate", point.beatsPerMinute)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
            if let newest = points.last {
                PointMark(
                    x: .value("Time", newest.date),
                    y: .value("Heart rate", newest.beatsPerMinute)
                )
                .symbolSize(lineWidth * 12)
            }
        }
        .foregroundStyle(.red)
        .chartXScale(domain: timeSpan)
        .chartYScale(domain: range)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .accessibilityLabel("Heart rate over the last five minutes")
    }
}
