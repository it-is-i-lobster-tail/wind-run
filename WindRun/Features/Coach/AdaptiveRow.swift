//
//  AdaptiveRow.swift
//  Wind Run
//

import SwiftUI

/// Side by side normally, stacked at accessibility text sizes so neither side gets squeezed.
struct AdaptiveRow<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var spacing: CGFloat = LayoutMetrics.compactSpacing
    @ViewBuilder let content: () -> Content

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: spacing))
        layout(content)
    }
}

extension View {
    /// The prominent accent button, with its text through `onAccent` so it reads on the deep teal in
    /// light mode and the bright teal in dark mode.
    func prominentAccentButton() -> some View {
        buttonStyle(.glassProminent)
            .foregroundStyle(.onAccent)
    }
}
