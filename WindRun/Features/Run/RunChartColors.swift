//
//  RunChartColors.swift
//  Wind Run
//

import SwiftUI
import UIKit

/// The run charts' colors: one hue per chart, from CARTO's palettes as Plotly ships them. Pastel in dark mode,
/// where its light tints stand off black, and Prism in light mode, whose deep tones stand off white. Each line
/// keeps at least 3.8:1 contrast over a work band, the lowest point it crosses.
enum RunChartColor {
    /// Blue: Pastel #9EB9F3, Prism #1D6996.
    static let pace = dynamic(light: 0x1D6996, dark: 0x9EB9F3)
    /// Green: Pastel #8BE0A4, Prism #0F8554.
    static let elevation = dynamic(light: 0x0F8554, dark: 0x8BE0A4)
    /// Purple: Pastel #DCB0F2, Prism #5F4690.
    static let cadence = dynamic(light: 0x5F4690, dark: 0xDCB0F2)
    /// Red-orange: Pastel #F89C74, Prism #CC503E.
    static let heartRate = dynamic(light: 0xCC503E, dark: 0xF89C74)

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
