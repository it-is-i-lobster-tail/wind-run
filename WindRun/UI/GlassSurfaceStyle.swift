//
//  GlassSurfaceStyle.swift
//  Wind Run
//

import SwiftUI

extension Color {
    /// Glass tint that follows the system theme: white in light mode, black in dark mode.
    static let glassSurface = Color(uiColor: .systemBackground)
}

extension View {
    func windRunGlassCard(interactive: Bool = false) -> some View {
        glassEffect(
            .regular
                .tint(.glassSurface.opacity(VisualOpacity.standard))
                .interactive(interactive),
            in: .rect(cornerRadius: LayoutMetrics.cardCornerRadius)
        )
    }

    /// The floating section switcher's glass. Nearly solid, so the page scrolling under it barely shows through.
    func windRunGlassSelection(interactive: Bool = false) -> some View {
        glassEffect(
            .regular
                .tint(.glassSurface.opacity(VisualOpacity.nearlyOpaque))
                .interactive(interactive),
            in: .rect(cornerRadius: LayoutMetrics.curvedCornerRadius)
        )
    }

    /// Matches `windRunGlassSelection` for round buttons that sit beside it.
    func windRunGlassCircle(interactive: Bool = false) -> some View {
        glassEffect(
            .regular
                .tint(.glassSurface.opacity(VisualOpacity.nearlyOpaque))
                .interactive(interactive),
            in: .circle
        )
    }
}
