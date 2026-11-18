//
//  LayoutMetrics.swift
//  Wind Run
//

import SwiftUI

enum LayoutMetrics {
    static let compactSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 20

    static let compactCornerRadius: CGFloat = 8
    static let cardCornerRadius: CGFloat = 12
    static let panelCornerRadius: CGFloat = 14
    static let curvedCornerRadius: CGFloat = 28

    /// The round glass buttons in the navigation bar, like Back, measure this across.
    static let navigationButtonSize: CGFloat = 44
    /// How far the navigation bar's round buttons sit in from the side of the screen.
    static let navigationButtonInset: CGFloat = 16

    /// The shortest a section switcher pill gets, a comfortable tap target.
    static let sectionPillMinHeight: CGFloat = 44
    /// The gap between two section switcher pills.
    static let sectionPillSpacing: CGFloat = 4
    /// The switcher's padding around its pills.
    static let sectionBarInset: CGFloat = 4
    /// The switcher's height at standard text sizes: a pill plus the padding above and below it.
    static var sectionBarHeight: CGFloat {
        sectionPillMinHeight + 2 * sectionBarInset
    }
}
