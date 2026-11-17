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
    var numeralLineHeight: CGFloat = 0.84

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

/// A headline number with its unit beside it and its caption under it: "32:48 / ELAPSED", "6.40 km / DISTANCE".
struct DisplayHeadline: View {
    let reading: DisplayReading
    let size: CGFloat
    let labelSize: CGFloat
    var numeralLineHeight: CGFloat = 0.84

    var body: some View {
        VStack(spacing: labelSize * 0.1) {
            HStack(alignment: .firstTextBaseline, spacing: size * 0.06) {
                DisplayValueText(reading: reading)
                    .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
                if let unit = reading.unit {
                    Text(unit)
                        .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
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
    var numeralLineHeight: CGFloat = 0.84

    var body: some View {
        VStack(spacing: labelSize * 0.15) {
            DisplayCaption(text: reading.label, size: labelSize)
                .foregroundStyle(.tint)
            HStack(alignment: .firstTextBaseline, spacing: size * 0.1) {
                if let symbol = reading.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.6, weight: .bold))
                        .foregroundStyle(reading.tint.map(DisplaySymbolTint.style) ?? AnyShapeStyle(.tint))
                }
                DisplayValueText(reading: reading)
                    .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
                if let unit = reading.unit {
                    Text(unit)
                        .font(.system(size: size * 0.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
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

/// The four smaller readings, two by two.
struct DisplayTileGrid: View {
    let tiles: [DisplayReading]
    let style: DisplayStyle

    var body: some View {
        Grid(horizontalSpacing: style.gridSpacing, verticalSpacing: style.gridSpacing) {
            ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { start in
                GridRow {
                    ForEach(start..<min(start + 2, tiles.count), id: \.self) { index in
                        DisplayTile(reading: tiles[index], size: style.tileSize, labelSize: style.labelSize, numeralLineHeight: style.numeralLineHeight)
                    }
                }
            }
        }
    }
}

/// The four smaller readings side by side, for a wide, short space such as the Lock Screen.
struct DisplayTileRow: View {
    let tiles: [DisplayReading]
    let style: DisplayStyle

    var body: some View {
        HStack(alignment: .top, spacing: style.gridSpacing) {
            ForEach(tiles.indices, id: \.self) { index in
                DisplayTile(reading: tiles[index], size: style.tileSize, labelSize: style.labelSize, numeralLineHeight: style.numeralLineHeight)
            }
        }
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

/// "ELAPSED", "PACE": small, bold, spaced out.
struct DisplayCaption: View {
    let text: String
    let size: CGFloat

    var body: some View {
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
