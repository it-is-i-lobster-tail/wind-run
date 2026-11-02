//
//  EasyStepColor.swift
//  Wind Run
//

import SwiftUI

extension ShapeStyle where Self == Color {
    /// The easy steps of a structured run (warm up, recoveries, cool down) next to the accent-colored hard
    /// ones. Amber against teal is a blue–orange pair, which stays apart for red-green and blue-yellow
    /// color blindness. A deeper amber in light mode keeps it 3:1 against white; the dark-mode and watch
    /// amber is Okabe–Ito orange.
    static var easyStep: Color {
        #if os(watchOS)
        EasyStepAmber.dark
        #else
        Color(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? EasyStepAmber.dark : EasyStepAmber.light)
        })
        #endif
    }
}

private enum EasyStepAmber {
    /// #C77700
    static let light = Color(red: 0.780, green: 0.467, blue: 0)
    /// #E69F00
    static let dark = Color(red: 0.902, green: 0.624, blue: 0)
}
