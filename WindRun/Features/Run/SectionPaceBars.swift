//
//  SectionPaceBars.swift
//  Wind Run
//

import SwiftUI

/// The pace of each step of a structured run as a bar, longer for faster, that grows in from the left
/// the first time it scrolls into view. Hard steps are blue, with their average dashed, and easy steps tan
/// (`RunChartColor`, which the Color Blind setting swaps).
struct SectionPaceBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(RunChartColor.colorBlindKey) private var colorBlind = false

    let sections: [RunSection]
    let unit: DistanceUnit

    @State private var hasGrown = false
    @State private var isOnScreen = false

    /// The fastest step fills the bar; slower ones are shorter by how much slower they were.
    private var fastestSpeed: Double {
        sections.compactMap(\.pace).map { 1 / $0 }.max() ?? 1
    }

    /// Average pace over all the hard steps together, or nil when there's only one.
    private var workAverage: TimeInterval? {
        let work = sections.filter(\.isWork)
        let seconds = work.reduce(0) { $0 + $1.seconds }
        let meters = work.reduce(0) { $0 + $1.meters }
        guard work.count > 1, meters >= 10 else { return nil }
        return seconds / (meters / 1_000)
    }

    private func fraction(for pace: TimeInterval?) -> Double {
        guard let pace else { return 0 }
        return (1 / pace) / fastestSpeed
    }

    var body: some View {
        MetricChartCard(metric: .pace, unit: unit, name: "Pace", axis: .sections,
                        detail: workAverage.map { "Work avg \(RunFormat.pace($0, unit: unit))" },
                        distributions: {
            [DistributionSeries(name: "This run", rawValues: sections.compactMap(\.pace),
                                metric: .pace, unit: unit, color: palette.pace)]
        }, legend: { EmptyView() }) { expanded in
            if expanded { ScrollView { bars(expanded: true) } }
            else { bars(expanded: false) }
        }
        .onScrollVisibilityChange(threshold: 0.3) { isVisible in
            isOnScreen = isVisible
        }
        // Wait out the page sliding in, so the runner sees the bars grow. With Reduce Motion there's
        // nothing to watch grow, so the bars are there straight away rather than popping in late.
        .task(id: isOnScreen) {
            guard isOnScreen, !hasGrown else { return }
            if reduceMotion {
                hasGrown = true
                return
            }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            hasGrown = true
        }
    }

    private var palette: RunChartColor { .palette(colorBlind: colorBlind) }

    private func bars(expanded: Bool) -> some View {
        let rowSpacing: CGFloat = expanded ? 12 : 6
        return Grid(alignment: .leading, horizontalSpacing: LayoutMetrics.compactSpacing, verticalSpacing: rowSpacing) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { order, section in
                GridRow {
                    Text(section.name)
                        .font(expanded ? .headline : .subheadline)
                        .foregroundStyle(section.isWork ? .primary : .secondary)
                        .lineLimit(1)
                        .gridColumnAlignment(.leading)
                        // A modifier on the GridRow would turn it into one cell, so the name reads for the row.
                        .accessibilityLabel("\(section.name), \(RunFormat.pace(section.pace, unit: unit)), \(RunFormat.distance(section.meters, unit: unit)) in \(RunFormat.duration(section.seconds))")
                    bar(for: section, order: order, expanded: expanded)
                        .accessibilityHidden(true)
                    Text(RunFormat.pace(section.pace, unit: unit, withUnit: false))
                        .font((expanded ? Font.headline : Font.subheadline).monospacedDigit().weight(section.isWork ? .semibold : .regular))
                        .foregroundStyle(section.isWork ? .primary : .secondary)
                        .gridColumnAlignment(.trailing)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func bar(for section: RunSection, order: Int, expanded: Bool) -> some View {
        let barHeight: CGFloat = expanded ? 24 : 14
        let rowSpacing: CGFloat = expanded ? 12 : 6
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(section.isWork ? palette.workStep : palette.easyStep)
                    .frame(width: (expanded || hasGrown) ? proxy.size.width * fraction(for: section.pace) : 0)
                    .animation(
                        reduceMotion ? nil : .spring(duration: 0.7, bounce: 0.15).delay(Double(order) * 0.06),
                        value: hasGrown
                    )

                // Each row draws its piece of the average line, reaching into the gaps so the pieces join.
                if let workAverage {
                    let x = proxy.size.width * fraction(for: workAverage)
                    Path { path in
                        path.move(to: CGPoint(x: x, y: -rowSpacing / 2))
                        path.addLine(to: CGPoint(x: x, y: barHeight + rowSpacing / 2))
                    }
                    .stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .opacity((expanded || hasGrown) ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeIn.delay(0.5), value: hasGrown)
                }
            }
        }
        .frame(height: barHeight)
    }
}

#Preview("Pace by section") {
    let paces: [(String, Bool, Double)] = [
        ("Warm up", false, 372), ("Work 1", true, 252), ("Recover", false, 410), ("Work 2", true, 247),
        ("Recover", false, 418), ("Work 3", true, 255), ("Recover", false, 405), ("Work 4", true, 262),
        ("Recover", false, 425), ("Cool down", false, 380),
    ]
    var start: TimeInterval = 0
    let sections = paces.enumerated().map { index, entry in
        let seconds: TimeInterval = entry.1 ? 240 : 90
        defer { start += seconds }
        return RunSection(id: index, name: entry.0, isWork: entry.1, startTime: start, endTime: start + seconds, meters: seconds / entry.2 * 1_000)
    }
    return ScrollView {
        SectionPaceBars(sections: sections, unit: .kilometers)
            .padding()
    }
}
