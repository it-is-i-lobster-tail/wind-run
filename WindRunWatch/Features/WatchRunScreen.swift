//
//  WatchRunScreen.swift
//  Wind Run Watch
//

import SwiftUI

/// The Watch screen mid-run, made to be read at a glance while running: time running biggest, distance
/// next, a heart rate line, then the pace now and one line under it. While an open step waits for the
/// runner, the pace gives way to what comes next and a big Next step button.
///
/// Sizes are set for the 46 mm watch and scale with the screen, so every size of watch shows the same.
struct WatchRunScreen: View {
    struct HeartRate {
        /// The readings from the last 15 minutes, oldest first.
        var points: [HeartRateHistory.Point]
        /// The newest reading, or nil before the first.
        var beatsPerMinute: Double?
    }

    let display: WatchRunDisplay
    /// Nil when this run doesn't measure heart rate.
    let heartRate: HeartRate?
    let nextStep: () -> Void

    /// The 46 mm watch's screen, which the sizes below are set for.
    private static let designWidth: CGFloat = 208
    private static let designScreenHeight: CGFloat = 248
    /// The height the body needs at those sizes, under the header.
    private static let designBodyHeight: CGFloat = 222
    /// The header row: the clock's line runs through its middle at 25 pt on the 46 mm watch.
    private static let headerHeight: CGFloat = 38
    private static let headerCenter: CGFloat = 25.5
    private static let bottomMargin: CGFloat = 6

    var body: some View {
        // The whole screen, measured from its top edge, so the header can sit on the clock's line.
        GeometryReader { proxy in
            let screen = proxy.size.height / Self.designScreenHeight
            let headerHeight = Self.headerHeight * screen
            let bodyHeight = proxy.size.height - headerHeight - Self.bottomMargin * screen
            let scale = min(proxy.size.width / Self.designWidth, bodyHeight / Self.designBodyHeight)
            VStack(spacing: 0) {
                header(scale)
                    .frame(height: Self.headerCenter * 2 * screen)
                    .frame(height: headerHeight, alignment: .top)
                content(scale)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 6 * scale)
                    .padding(.bottom, Self.bottomMargin * screen)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: Header

    /// The run or the step, in the top left on the clock's line.
    private func header(_ scale: CGFloat) -> some View {
        Text(display.title)
            .font(.system(size: 17 * scale, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Clear of the screen's rounded corner, and of the clock on the right.
            .padding(.leading, 16 * scale)
            .padding(.trailing, 72 * scale)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Body

    private func content(_ scale: CGFloat) -> some View {
        VStack(spacing: 0) {
            bigNumber(display.elapsed, size: 58 * scale, label: display.elapsedLabel, scale: scale)
                .foregroundStyle(display.isPaused ? .secondary : .primary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(display.elapsedLabel.capitalized), \(display.elapsed)")
            Spacer(minLength: 2 * scale)
            distance(scale)
            Spacer(minLength: 4 * scale)
            if let heartRate {
                heartRateRow(heartRate, scale: scale)
                Spacer(minLength: 4 * scale)
            }
            lower(scale)
        }
    }

    private func bigNumber(_ value: String, size: CGFloat, label: String, scale: CGFloat) -> some View {
        VStack(spacing: 1 * scale) {
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                // Numerals have no descenders, so their line can sit close to the label.
                .frame(height: size * 0.84)
            caption(label, scale: scale)
                .foregroundStyle(.secondary)
        }
    }

    private func distance(_ scale: CGFloat) -> some View {
        VStack(spacing: 1 * scale) {
            HStack(alignment: .firstTextBaseline, spacing: 3 * scale) {
                Text(display.distance)
                    .font(.system(size: 44 * scale, weight: .bold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text(display.distanceUnit)
                    .font(.system(size: 20 * scale, weight: .semibold, design: .rounded))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(height: 44 * scale * 0.84)
            caption(display.distanceLabel, scale: scale)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(display.distanceLabel.capitalized), \(display.distance) \(display.distanceUnit)")
    }

    private func caption(_ text: String, scale: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 11 * scale, weight: .bold, design: .rounded).monospacedDigit())
            .tracking(0.8 * scale)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    // MARK: Heart rate

    private func heartRateRow(_ heartRate: HeartRate, scale: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 6 * scale) {
            HeartRateLine(points: heartRate.points)
                .stroke(Color.red, style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round, lineJoin: .round))
                .frame(maxWidth: .infinity)
                .frame(height: 24 * scale)
                .accessibilityHidden(true)
            HStack(alignment: .center, spacing: 3 * scale) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14 * scale, weight: .bold))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: -3 * scale) {
                    Text(RunFormat.heartRate(heartRate.beatsPerMinute, withUnit: false))
                        .font(.system(size: 21 * scale, weight: .bold, design: .rounded).monospacedDigit())
                    Text("bpm")
                        .font(.system(size: 13 * scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Heart rate, \(RunFormat.heartRate(heartRate.beatsPerMinute))")
    }

    // MARK: Pace or next step

    @ViewBuilder
    private func lower(_ scale: CGFloat) -> some View {
        switch display.lower {
        case .pace(let value, let unit, let footer):
            VStack(spacing: 0) {
                Text("Current Pace")
                    .font(.system(size: 14 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                HStack(alignment: .firstTextBaseline, spacing: 3 * scale) {
                    Text(value)
                        .font(.system(size: 30 * scale, weight: .bold, design: .rounded).monospacedDigit())
                    Text(unit)
                        .font(.system(size: 14 * scale, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(display.isPaused ? .secondary : .primary)
                .frame(height: 30 * scale * 0.9)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Current pace, \(value) \(unit)")
                if let footer {
                    Spacer(minLength: 4 * scale)
                    line(footer, scale: scale)
                }
            }
        case .nextStep(let preview):
            VStack(spacing: 6 * scale) {
                line(preview, scale: scale)
                Button(action: nextStep) {
                    HStack(spacing: 8 * scale) {
                        Text("Next step")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 21 * scale, weight: .bold, design: .rounded))
                    .foregroundStyle(.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 50 * scale)
                    .background(Capsule().fill(Color.accentColor))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next step")
                .accessibilityHint(preview.value)
            }
        }
    }

    /// "↓ 43 m below start", "NEXT Work · 3:00".
    private func line(_ line: WatchRunDisplay.Line, scale: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5 * scale) {
            if let symbol = line.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 15 * scale, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
            if let caption = line.caption {
                Text(caption)
                    .font(.system(size: 12 * scale, weight: .bold, design: .rounded))
                    .tracking(0.8 * scale)
                    .foregroundStyle(.secondary)
            }
            Text(line.value)
                .font(.system(size: 17 * scale, weight: .bold, design: .rounded).monospacedDigit())
            if let detail = line.detail {
                Text(detail)
                    .font(.system(size: 15 * scale, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .combine)
    }
}

/// Heart rate over the last 15 minutes as a bare line: time left to right, beats up. No axes or fill.
/// Readings are averaged into even slices of time first, so the line reads as a trend, not every beat.
struct HeartRateLine: Shape {
    let points: [HeartRateHistory.Point]

    /// How many slices of time the line is drawn through.
    static let slices = 60
    /// The line never spreads a smaller range of beats over its full height, so a steady heart rate
    /// looks steady.
    static let minimumSpan: Double = 20

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let first = points.first?.date, let last = points.last?.date, last > first else { return path }
        let duration = last.timeIntervalSince(first)

        var totals = Array(repeating: 0.0, count: Self.slices)
        var counts = Array(repeating: 0, count: Self.slices)
        for point in points {
            let slice = min(Self.slices - 1, Int(point.date.timeIntervalSince(first) / duration * Double(Self.slices)))
            totals[slice] += point.beatsPerMinute
            counts[slice] += 1
        }
        let averaged: [(x: Double, bpm: Double)] = totals.indices.compactMap { index in
            counts[index] > 0 ? ((Double(index) + 0.5) / Double(Self.slices), totals[index] / Double(counts[index])) : nil
        }
        guard averaged.count > 1, let low = averaged.map(\.bpm).min(), let high = averaged.map(\.bpm).max() else { return path }

        let span = max(high - low, Self.minimumSpan)
        let floor = (low + high) / 2 - span / 2
        let firstX = averaged[0].x, lastX = averaged[averaged.count - 1].x
        func position(_ point: (x: Double, bpm: Double)) -> CGPoint {
            CGPoint(
                x: rect.minX + (point.x - firstX) / (lastX - firstX) * rect.width,
                y: rect.maxY - (point.bpm - floor) / span * rect.height
            )
        }
        path.move(to: position(averaged[0]))
        for point in averaged.dropFirst() {
            path.addLine(to: position(point))
        }
        return path
    }
}
