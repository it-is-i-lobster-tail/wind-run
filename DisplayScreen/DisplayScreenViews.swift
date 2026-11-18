//
//  DisplayScreenViews.swift
//  Wind Run
//
//  The pieces every run screen is built from. Each device picks the sizes; the words come from the readings.
//

import SwiftUI

/// The sizes a device draws a display screen at.
struct DisplayStyle {
    /// The biggest number.
    var primarySize: CGFloat
    /// The second biggest.
    var secondarySize: CGFloat
    /// The numbers in the grid.
    var tileSize: CGFloat
    /// Captions under or over the numbers.
    var labelSize: CGFloat
    /// Space between the grid's rows and columns.
    var gridSpacing: CGFloat
    /// Lets a number sit closer to its caption: numerals have no descenders. 1 keeps the full line.
    var numeralLineHeight: CGFloat = DisplayStyle.standardNumeralLineHeight

    /// The line height every style, headline and tile starts with.
    static let standardNumeralLineHeight: CGFloat = 0.84

    /// The same style, every size multiplied by `factor`.
    func scaled(by factor: CGFloat) -> DisplayStyle {
        var style = self
        style.primarySize *= factor
        style.secondarySize *= factor
        style.tileSize *= factor
        style.labelSize *= factor
        style.gridSpacing *= factor
        return style
    }
}

/// The display screen's sizes on each device, here so the app's Edit Display previews can draw them at the
/// same proportions.
enum DisplaySizes {
    /// The iPhone's run screen.
    static let iPhone = DisplayStyle(primarySize: 76, secondarySize: 56, tileSize: 34, labelSize: 13, gridSpacing: 20)
    /// The 46 mm watch.
    static let watch = DisplayStyle(primarySize: 58, secondarySize: 44, tileSize: 26, labelSize: 11, gridSpacing: 8)
    /// Edit Display's watch preview. Its own sizes, not a scale of `watch`.
    static let watchPreview = DisplayStyle(primarySize: 40, secondarySize: 30, tileSize: 20, labelSize: 9, gridSpacing: 8)
    static let lockScreen = DisplayStyle(primarySize: 40, secondarySize: 40, tileSize: 20, labelSize: 9, gridSpacing: 8)
    /// Smaller, to leave room for the step.
    static let lockScreenWithStep = DisplayStyle(primarySize: 30, secondarySize: 30, tileSize: 18, labelSize: 9, gridSpacing: 8)
    static let island = DisplayStyle(primarySize: 26, secondarySize: 26, tileSize: 16, labelSize: 8, gridSpacing: 6)
}

/// A headline number with its unit beside it and its caption under it: "32:48 / ELAPSED", "6.40 km / DISTANCE".
struct DisplayHeadline: View {
    let reading: DisplayReading
    let size: CGFloat
    let labelSize: CGFloat
    var numeralLineHeight: CGFloat = DisplayStyle.standardNumeralLineHeight

    var body: some View {
        VStack(spacing: labelSize * 0.1) {
            HStack(alignment: .firstTextBaseline, spacing: size * 0.06) {
                if let then = reading.then {
                    // A headline leaves out a lone symbol, but a reading with two numbers needs its arrows
                    // to tell them apart.
                    DisplayPairLine(reading: reading, then: then, size: size, unitScale: 0.45)
                } else {
                    DisplayValueText(reading: reading)
                        .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
                    if let unit = reading.unit {
                        Text(unit)
                            .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(reading.isDimmed ? .secondary : .primary)
            .frame(height: size * numeralLineHeight)
            DisplayCaption(text: reading.label, size: labelSize)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.spoken)
    }
}

/// One spot in the grid: its caption in the accent colour over its number.
struct DisplayTile: View {
    let reading: DisplayReading
    let size: CGFloat
    let labelSize: CGFloat
    var numeralLineHeight: CGFloat = DisplayStyle.standardNumeralLineHeight

    var body: some View {
        VStack(spacing: labelSize * 0.15) {
            DisplayCaption(text: reading.label, size: labelSize)
                .foregroundStyle(.tint)
            HStack(alignment: .firstTextBaseline, spacing: size * 0.1) {
                if let then = reading.then {
                    DisplayPairLine(reading: reading, then: then, size: size, unitScale: 0.5, unitIsQuiet: true)
                } else {
                    if let symbol = reading.symbol {
                        DisplaySymbol(name: symbol, tint: reading.tint, size: size)
                    }
                    DisplayValueText(reading: reading)
                        .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
                    if let unit = reading.unit {
                        Text(unit)
                            .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(reading.isDimmed ? .secondary : .primary)
            .frame(height: size * numeralLineHeight)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.spoken)
    }
}

/// How the grid's readings fall into rows of two.
enum DisplayTileLayout {
    /// The tiles in each row, two to a row, the last row shorter when the count is odd.
    static func rows(count: Int) -> [Range<Int>] {
        stride(from: 0, to: count, by: 2).map { start in start..<min(start + 2, count) }
    }
}

/// The four smaller readings, two by two. `cell` wraps each tile, by its place in the grid, such as to make
/// it tappable in Edit Display's preview.
struct DisplayTileGrid<Cell: View>: View {
    let tiles: [DisplayReading]
    let style: DisplayStyle
    let cell: (Int, DisplayTile) -> Cell

    init(tiles: [DisplayReading], style: DisplayStyle, @ViewBuilder cell: @escaping (Int, DisplayTile) -> Cell) {
        self.tiles = tiles
        self.style = style
        self.cell = cell
    }

    var body: some View {
        Grid(horizontalSpacing: style.gridSpacing, verticalSpacing: style.gridSpacing) {
            ForEach(DisplayTileLayout.rows(count: tiles.count), id: \.lowerBound) { row in
                GridRow {
                    ForEach(row, id: \.self) { index in
                        cell(index, DisplayTile(reading: tiles[index], size: style.tileSize, labelSize: style.labelSize, numeralLineHeight: style.numeralLineHeight))
                    }
                }
            }
        }
    }
}

extension DisplayTileGrid where Cell == DisplayTile {
    /// The tiles as they are.
    init(tiles: [DisplayReading], style: DisplayStyle) {
        self.init(tiles: tiles, style: style) { _, tile in tile }
    }
}

/// The four smaller readings side by side, for a wide, short space such as the Lock Screen. `cell` wraps
/// each tile, by its place in the row.
struct DisplayTileRow<Cell: View>: View {
    let tiles: [DisplayReading]
    let style: DisplayStyle
    let cell: (Int, DisplayTile) -> Cell

    init(tiles: [DisplayReading], style: DisplayStyle, @ViewBuilder cell: @escaping (Int, DisplayTile) -> Cell) {
        self.tiles = tiles
        self.style = style
        self.cell = cell
    }

    var body: some View {
        HStack(alignment: .top, spacing: style.gridSpacing) {
            ForEach(tiles.indices, id: \.self) { index in
                cell(index, DisplayTile(reading: tiles[index], size: style.tileSize, labelSize: style.labelSize, numeralLineHeight: style.numeralLineHeight))
            }
        }
    }
}

extension DisplayTileRow where Cell == DisplayTile {
    /// The tiles as they are.
    init(tiles: [DisplayReading], style: DisplayStyle) {
        self.init(tiles: tiles, style: style) { _, tile in tile }
    }
}

/// The symbol before a number, such as the heart or an arrow, in the reading's tint or the accent.
struct DisplaySymbol: View {
    let name: String
    let tint: DisplayReading.Tint?
    /// The number's size.
    let size: CGFloat

    var body: some View {
        Image(systemName: name)
            .font(.system(size: size * 0.6, weight: .bold))
            .foregroundStyle(tint.map { DisplaySymbolTint.style($0) } ?? AnyShapeStyle(.tint))
    }
}

/// A reading with two numbers, Elevation's "↑ 186  ↓ 143 m", drawn like any tile's number, unit and all.
/// Where it doesn't fit, the whole line steps down in size together, so the second number is never cut
/// off and the unit keeps its share of the numbers' size.
struct DisplayPairLine: View {
    let reading: DisplayReading
    let then: DisplayReading.Then
    /// The numbers' size.
    let size: CGFloat
    /// The unit's size, as a share of the numbers'.
    let unitScale: CGFloat
    /// Whether the unit is greyed, as a tile's is.
    var unitIsQuiet = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            line(size).fixedSize()
            line(size * 0.85).fixedSize()
            line(size * 0.72).fixedSize()
            line(size * 0.6).fixedSize()
            line(size * 0.5).fixedSize()
            // The last resort shrinks further as any number does.
            line(size * 0.5)
        }
    }

    private func line(_ size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.1) {
            if let symbol = reading.symbol {
                DisplaySymbol(name: symbol, tint: reading.tint, size: size)
            }
            number(reading.value, size: size)
            DisplaySymbol(name: then.symbol, tint: reading.tint, size: size)
                .padding(.leading, size * 0.15)
            number(then.value, size: size)
            if let unit = reading.unit {
                Text(unit)
                    .font(.system(size: size * unitScale, weight: .semibold, design: .rounded))
                    .foregroundStyle(unitIsQuiet ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            }
        }
    }

    private func number(_ value: String, size: CGFloat) -> some View {
        Text(value)
            .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
            .contentTransition(.numericText())
    }
}

/// A reading's number. Elapsed time counts on its own between redraws while the run is going.
struct DisplayValueText: View {
    let reading: DisplayReading

    var body: some View {
        if let start = reading.clockStart {
            Text(start, style: .timer)
                .multilineTextAlignment(.center)
        } else {
            Text(reading.value)
                .contentTransition(.numericText())
        }
    }
}

/// "ELAPSED", "PACE": small, bold, spaced out. Grows with the runner's text size, to half again at most,
/// since it's what tells "AVG PACE" from "CURRENT PACE"; the numbers keep their size so the grid still fits.
struct DisplayCaption: View {
    let text: String
    let size: CGFloat

    @ScaledMetric(relativeTo: .caption2) private var textScale: CGFloat = 1

    var body: some View {
        let size = size * min(max(textScale, 1), 1.5)
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded))
            .tracking(size * 0.07)
            .lineLimit(1)
            // Narrowed to fit a long caption, but never squeezed for height: the layout makes room.
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The colour a reading's symbol takes: the accent, red for heart rate, or a heart rate zone's own colour.
enum DisplaySymbolTint {
    static func style(_ tint: DisplayReading.Tint) -> AnyShapeStyle {
        switch tint {
        case .accent: AnyShapeStyle(.tint)
        case .heartRate: AnyShapeStyle(Color.red)
        case .zone1: AnyShapeStyle(Color.gray)
        case .zone2: AnyShapeStyle(Color.blue)
        case .zone3: AnyShapeStyle(Color.green)
        case .zone4: AnyShapeStyle(Color.orange)
        case .zone5: AnyShapeStyle(Color.red)
        }
    }
}
