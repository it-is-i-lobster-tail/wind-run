//
//  WatchRunScreen.swift
//  Wind Run Watch
//

import SwiftUI

/// The Watch screen mid-run, made to be read at a glance while running. It lays out the runner's display
/// screen: the two headline numbers, biggest first, then the 2×2 grid. While an open step waits for the
/// runner, the grid's bottom row gives way to what comes next and a big Next step button.
///
/// Every state is drawn at the same scale, so the numbers never change size as steps come and go.
///
/// Sizes are set for the 46 mm watch and scale with the screen, so every size of watch shows the same.
struct WatchRunScreen: View {
    let display: WatchRunDisplay
    let readings: DisplayScreenReadings
    let nextStep: () -> Void

    /// The sizes on the 46 mm watch.
    static let style = DisplayStyle(primarySize: 58, secondarySize: 44, tileSize: 26, labelSize: 11, gridSpacing: 8)

    /// The 46 mm watch's screen, which the sizes are set for.
    private static let designWidth: CGFloat = 208
    private static let designScreenHeight: CGFloat = 248
    /// The header row: the clock's line runs through its middle at 25.5 pt on the 46 mm watch.
    private static let headerHeight: CGFloat = 38
    private static let headerCenter: CGFloat = 25.5
    private static let bottomMargin: CGFloat = 6

    /// The height the body needs at the 46 mm sizes, under the header, in its tallest state: an open step,
    /// with the grid's top row, the next step and the button.
    private static let designBodyHeight: CGFloat = 232

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
        let style = Self.style.scaled(by: scale)
        return VStack(spacing: 0) {
            DisplayHeadline(reading: readings.primary, size: style.primarySize, labelSize: style.labelSize)
            Spacer(minLength: 2 * scale)
            DisplayHeadline(reading: readings.secondary, size: style.secondarySize, labelSize: style.labelSize)
            Spacer(minLength: 6 * scale)
            switch display.lower {
            case .grid:
                DisplayTileGrid(tiles: readings.tiles, style: style)
            case .nextStep(let preview):
                // The top row stays, so heart rate can be watched coming down before the tap.
                DisplayTileGrid(tiles: Array(readings.tiles.prefix(2)), style: style)
                Spacer(minLength: 5 * scale)
                nextStepBlock(preview, scale: scale)
            }
            Spacer(minLength: 0)
        }
        .tint(Color.accentColor)
    }

    // MARK: Next step

    private func nextStepBlock(_ preview: WatchRunDisplay.Line, scale: CGFloat) -> some View {
        VStack(spacing: 5 * scale) {
            line(preview, scale: scale)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: nextStep) {
                HStack(spacing: 8 * scale) {
                    Text("Next step")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 20 * scale, weight: .bold, design: .rounded))
                .foregroundStyle(.onAccent)
                .frame(maxWidth: .infinity, minHeight: 40 * scale)
                .background(Capsule().fill(Color.accentColor))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            // The screen's corners are round, so the button's ends sit in from the edges.
            .padding(.horizontal, 10 * scale)
            .padding(.bottom, 4 * scale)
            .accessibilityLabel("Next step")
            .accessibilityHint(preview.value)
        }
    }

    /// "NEXT Work · 3:00".
    private func line(_ line: WatchRunDisplay.Line, scale: CGFloat) -> some View {
        let size: CGFloat = 15
        return HStack(alignment: .firstTextBaseline, spacing: 5 * scale) {
            if let caption = line.caption {
                Text(caption)
                    .font(.system(size: (size - 4) * scale, weight: .bold, design: .rounded))
                    .tracking(0.8 * scale)
                    .foregroundStyle(.secondary)
            }
            Text(line.value)
                .font(.system(size: size * scale, weight: .bold, design: .rounded).monospacedDigit())
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityElement(children: .combine)
    }
}
