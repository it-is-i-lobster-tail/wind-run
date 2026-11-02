//
//  AccentForeground.swift
//  Wind Run
//

import SwiftUI

extension ShapeStyle where Self == Color {
    /// Text and symbols on an accent fill. The light-mode accent is the logo's deep teal,
    /// which needs white; the dark-mode and watch accent is a bright teal, which needs black.
    static var onAccent: Color {
        #if os(watchOS)
        .black
        #else
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? .black : .white
        })
        #endif
    }
}
