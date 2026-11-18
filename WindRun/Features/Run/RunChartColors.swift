//
//  RunChartColors.swift
//  Wind Run
//

import SwiftUI
import UIKit

/// The run charts' colors: one hue per chart, from CARTO's palettes as Plotly ships them. Normally Pastel in dark
/// mode, where its light tints stand off black, and Prism in light mode, whose deep tones stand off white, each
/// line at least 3.8:1 over a work band. With Settings → Appearance → Color Blind on, Paul Tol's color-blind-safe
/// set instead (CARTO's Safe): sky, teal, sand and rose in dark mode, and its deep indigo, green, purple and wine
/// in light mode, each at least 3.2:1.
struct RunChartColor {
    /// The Color Blind switch's setting.
    static let colorBlindKey = "colorBlindCharts"

    let pace: Color
    let elevation: Color
    let cadence: Color
    let heartRate: Color

    /// The colors for the Color Blind switch's setting.
    static func palette(colorBlind: Bool) -> RunChartColor {
        colorBlind ? colorBlindSafe : standard
    }

    /// Blue, green, purple and red-orange: Pastel #9EB9F3, #8BE0A4, #DCB0F2, #F89C74 in dark mode, Prism
    /// #1D6996, #0F8554, #5F4690, #CC503E in light mode.
    static let standard = RunChartColor(
        pace: dynamic(light: 0x1D6996, dark: 0x9EB9F3),
        elevation: dynamic(light: 0x0F8554, dark: 0x8BE0A4),
        cadence: dynamic(light: 0x5F4690, dark: 0xDCB0F2),
        heartRate: dynamic(light: 0xCC503E, dark: 0xF89C74)
    )

    /// Safe #88CCEE, #44AA99, #DDCC77, #CC6677 in dark mode, and #332288, #117733, #AA4499, #882255 from the same
    /// set in light mode.
    static let colorBlindSafe = RunChartColor(
        pace: dynamic(light: 0x332288, dark: 0x88CCEE),
        elevation: dynamic(light: 0x117733, dark: 0x44AA99),
        cadence: dynamic(light: 0xAA4499, dark: 0xDDCC77),
        heartRate: dynamic(light: 0x882255, dark: 0xCC6677)
    )

    /// The bands where the hard steps were: neutral, so every line color reads over them.
    static let workBand = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.12) : UIColor(white: 0, alpha: 0.07)
    })

    /// Every chart line's width, thick enough to follow at a glance.
    static let lineWidth: CGFloat = 2

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            color(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
