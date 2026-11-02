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

    func windRunGlassSelection(interactive: Bool = false) -> some View {
        glassEffect(
            .regular
                .tint(.glassSurface.opacity(VisualOpacity.heavy))
                .interactive(interactive),
            in: .rect(cornerRadius: LayoutMetrics.curvedCornerRadius)
        )
    }

    /// Matches `windRunGlassSelection` for round buttons that sit beside it.
    func windRunGlassCircle(interactive: Bool = false) -> some View {
        glassEffect(
            .regular
                .tint(.glassSurface.opacity(VisualOpacity.heavy))
                .interactive(interactive),
            in: .circle
        )
    }
}
